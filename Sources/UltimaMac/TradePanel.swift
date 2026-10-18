import AppKit
import UOCore

@MainActor final class TradePanel:NSView {
    private(set) var trade:SecureTrade
    private let assets:ClientAssets
    private let accept = NSButton(title:"Accept trade",target:nil,action:nil)
    private let partner = NSTextField(labelWithString:"")
    private var drag:NSPoint?, candidate:ContainerItem?, start:NSPoint?
    private var quantityPanel:StackQuantityPanel?
    private var hits:[(NSRect,ContainerItem)] = []
    var onAccept:((Bool,UInt64)->Void)?
    var onCancel:(()->Void)?
    var onReturn:((ContainerItem)->Void)?
    var onDrop:((ContainerItem,NSPoint)->Void)?
    override var isFlipped:Bool { true }
    init(trade:SecureTrade,assets:ClientAssets) {
        self.trade = trade; self.assets = assets
        super.init(frame:NSRect(x:320,y:180,width:350,height:210))
        if let image = gump(0x866) { frame.size = image.size }
        accept.frame = NSRect(x:52,y:29,width:24,height:24); accept.isBordered = false; accept.imagePosition = .imageOnly
        accept.target = self; accept.action = #selector(confirm); accept.setAccessibilityLabel("Accept trade"); addSubview(accept)
        let own = NSTextField(labelWithString:"Your offer"); own.frame = NSRect(x:84,y:40,width:140,height:20); own.textColor = .black; addSubview(own)
        partner.frame = NSRect(x:130,y:170,width:130,height:22); partner.alignment = .right; partner.textColor = .black; addSubview(partner)
        toolTip = "Drag items into your left offer. Drag them back out to remove them. Right-click cancels the trade."
        update(trade)
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(_ value:SecureTrade) {
        if value.revision != trade.revision || value.closed || value.cancelling || value.pendingAcceptance != nil || value.awaitingOfferUpdate {
            candidate = nil; start = nil
            quantityPanel?.removeFromSuperview(); quantityPanel = nil
        }
        trade = value; partner.stringValue = value.partnerName
        accept.image = gump(value.ownAccepted ? 0x869 : 0x867)
        accept.alternateImage = gump(value.ownAccepted ? 0x86A : 0x868)
        accept.isEnabled = !value.closed && !value.cancelling && value.pendingAcceptance == nil && !value.awaitingOfferUpdate
        accept.setAccessibilityLabel(value.ownAccepted ? "Withdraw trade acceptance" : "Accept trade")
        needsDisplay = true
    }
    func dropDestination(windowPoint:NSPoint)->(UInt32,NSPoint)? {
        let p = convert(windowPoint,from:nil)
        guard !trade.closed,!trade.cancelling,trade.pendingAcceptance == nil,!trade.awaitingOfferUpdate,
              NSRect(x:45,y:70,width:110,height:80).contains(p) else { return nil }
        return (trade.ownContainer,NSPoint(x:p.x-45,y:p.y-70))
    }
    private func gump(_ id:Int)->NSImage? { (try? assets.gumps?.sprite(id)).flatMap { image($0) } }
    private func image(_ sprite:Sprite,hue:Int = 0,art:Int? = nil)->NSImage? {
        var pixels = sprite.rgba
        if let palette = try? assets.huePalette(hue,art:art) { for i in stride(from:0,to:pixels.count,by:4) where pixels[i+3] != 0 {
            let c = palette.color(red:pixels[i],green:pixels[i+1],blue:pixels[i+2]); pixels[i] = c.0; pixels[i+1] = c.1; pixels[i+2] = c.2
        } }
        guard let provider = CGDataProvider(data:Data(pixels) as CFData),let cg = CGImage(width:sprite.width,height:sprite.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:sprite.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { return nil }
        return NSImage(cgImage:cg,size:NSSize(width:sprite.width,height:sprite.height))
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        gump(0x866)?.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        if let check = gump(trade.otherAccepted ? 0x869 : 0x867) { check.draw(in:NSRect(origin:NSPoint(x:266,y:160),size:check.size),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
        hits.removeAll()
        for (container,x) in [(trade.ownContainer,45),(trade.otherContainer,192)] {
            let area = NSRect(x:x,y:70,width:110,height:80)
            NSGraphicsContext.saveGraphicsState(); area.clip()
            for item in trade.items where item.container == container {
                guard let sprite = try? assets.sprite(item.displayGraphic+0x4000),let image = image(sprite,hue:item.hue,art:item.displayGraphic+0x4000) else { continue }
                let rect = NSRect(x:x+max(0,min(109,item.x)),y:70+max(0,min(79,item.y)),width:sprite.width,height:sprite.height)
                image.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
                if container == trade.ownContainer { hits.append((rect.intersection(area),item)) }
                if item.amount > 1 { (String(item.amount) as NSString).draw(at:NSPoint(x:rect.minX,y:rect.maxY-12),withAttributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:NSColor.white,.backgroundColor:NSColor.black]) }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        if trade.pendingAcceptance != nil || trade.awaitingOfferUpdate || trade.cancelling {
            ("Waiting for server…" as NSString).draw(at:NSPoint(x:90,y:151),withAttributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:NSColor.black])
        }
    }
    @objc private func confirm() { onAccept?(!trade.ownAccepted,trade.revision) }
    override func rightMouseDown(with event:NSEvent) { if !trade.cancelling { onCancel?() } }
    override func mouseDown(with event:NSEvent) {
        let p = convert(event.locationInWindow,from:nil)
        candidate = hits.reversed().first { $0.0.contains(p) }?.1
        start = event.locationInWindow
        if let candidate,event.clickCount == 2,trade.pendingAcceptance == nil,!trade.awaitingOfferUpdate,!trade.cancelling { onReturn?(candidate); self.candidate = nil }
        drag = candidate == nil ? event.locationInWindow : nil
    }
    override func mouseDragged(with event:NSEvent) {
        guard let drag else { return }
        frame.origin.x += event.locationInWindow.x-drag.x; frame.origin.y -= event.locationInWindow.y-drag.y; self.drag = event.locationInWindow
    }
    override func mouseUp(with event:NSEvent) {
        defer { candidate = nil; start = nil; drag = nil }
        guard let candidate,let start,trade.pendingAcceptance == nil,!trade.awaitingOfferUpdate,!trade.cancelling,
              hypot(event.locationInWindow.x-start.x,event.locationInWindow.y-start.y)>3 else { return }
        let point = event.locationInWindow
        guard quantityPanel == nil else { return }
        let revision = trade.revision
        let finish:(Int)->Void = { [weak self] amount in
            guard let self, self.trade.revision == revision, !self.trade.closed,
                  !self.trade.cancelling, self.trade.pendingAcceptance == nil,
                  !self.trade.awaitingOfferUpdate, self.trade.items.contains(candidate) else { return }
            self.onDrop?(ContainerItem(serial:candidate.serial,graphic:candidate.graphic,
                amount:amount,x:candidate.x,y:candidate.y,container:candidate.container,hue:candidate.hue),point)
        }
        if candidate.amount > 1 && (try? assets.isStackable(graphic:candidate.graphic)) == true {
            let picker = StackQuantityPanel(maximum:min(65535,candidate.amount),assets:assets)
            picker.frame.origin = .zero
            picker.onConfirm = { [weak self, weak picker] amount in
                picker?.removeFromSuperview(); self?.quantityPanel = nil
                finish(amount)
            }
            picker.onCancel = { [weak self, weak picker] in
                picker?.removeFromSuperview(); self?.quantityPanel = nil
            }
            quantityPanel = picker; addSubview(picker)
        } else { finish(1) }
    }
}
