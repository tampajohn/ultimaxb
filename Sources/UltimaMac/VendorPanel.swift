import AppKit
import UOCore

@MainActor
final class VendorPanel: NSView {
    let serial: UInt32
    private let assets: ClientAssets
    private let selling: Bool
    private let offers: [VendorOffer]
    private var pendingPurchase = false
    private var quantities: [UInt32:Int] = [:]
    private let stock = NSStackView(), cart = NSStackView()
    private let gold = NSTextField(labelWithString:"—")
    private let total = NSTextField(labelWithString:"0")
    private let status = NSTextField(wrappingLabelWithString:"")
    private var buttons: [NSButton] = []
    private var documents: [(NSScrollView, NSStackView)] = []
    var onBuy: (([UInt32:Int]) -> Void)?
    var onClose: (() -> Void)?
    override var isFlipped: Bool { true }
    init(serial:UInt32, offers:[VendorOffer], assets:ClientAssets, selling:Bool = false) {
        self.selling = selling
        self.serial = serial; self.offers = offers; self.assets = assets
        super.init(frame:NSRect(x:24,y:24,width:550,height:420))
        setup(stock,rect:NSRect(x:32,y:64,width:220,height:165))
        setup(cart,rect:NSRect(x:283,y:185,width:220,height:90))
        gold.frame = NSRect(x:395,y:303,width:95,height:22); gold.isHidden = selling; gold.textColor = .black; gold.toolTip = "Gold reported by the server; bank balance is separate."; addSubview(gold)
        total.frame = NSRect(x:selling ? 395 : 315,y:303,width:150,height:22); total.textColor = .black; addSubview(total)
        status.frame = NSRect(x:20,y:375,width:510,height:40); status.textColor = .white
        status.stringValue = offers.isEmpty ? "The vendor has no eligible items to trade. Right-click closes." : "Double-click items, then Accept to \(selling ? "sell" : "buy"). Right-click closes."; addSubview(status)
        let accept = NSButton(title:"",target:self,action:#selector(buy)); accept.frame = NSRect(x:283,y:319,width:34,height:30)
        accept.isBordered = false; accept.toolTip = selling ? "Sell selected items" : "Buy selected items"; accept.setAccessibilityLabel(selling ? "Sell selected items" : "Buy selected items"); addSubview(accept); buttons.append(accept)
        let clear = NSButton(title:"",target:self,action:#selector(clearCart)); clear.frame = NSRect(x:458,y:319,width:20,height:20)
        clear.isBordered = false; clear.toolTip = "Clear selection"; clear.setAccessibilityLabel("Clear selection"); addSubview(clear); buttons.append(clear)
        for offer in offers {
            let row = VendorStockRow(offer:offer, icon:(try? assets.sprite(offer.item.displayGraphic+0x4000)).flatMap(Self.image))
            row.onAdd = { [weak self] in self?.add(serial:offer.item.serial) }
            row.widthAnchor.constraint(equalToConstant:200).isActive = true
            row.heightAnchor.constraint(equalToConstant:52).isActive = true
            stock.addArrangedSubview(row)
        }
        layoutDocuments()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) unsupported") }
    private func setup(_ stack:NSStackView, rect:NSRect) {
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        let scroll = NSScrollView(frame:rect); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.documentView = VendorDocument(frame:NSRect(origin:.zero,size:rect.size))
        scroll.documentView!.addSubview(stack)
        stack.widthAnchor.constraint(equalToConstant:rect.width-14).isActive = true
        addSubview(scroll); documents.append((scroll,stack))
    }
    private func layoutDocuments() {
        for (scroll,stack) in documents {
            let height = max(1,stack.fittingSize.height)
            scroll.documentView?.frame = NSRect(x:0,y:0,width:scroll.contentSize.width,height:max(height,scroll.contentSize.height))
            stack.frame = NSRect(x:0,y:0,width:scroll.contentSize.width,height:height)
            scroll.contentView.scroll(to:.zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
    private static func image(_ sprite:Sprite) -> NSImage? {
        guard let provider = CGDataProvider(data:Data(sprite.rgba) as CFData), let cg = CGImage(width:sprite.width,height:sprite.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:sprite.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { return nil }
        return NSImage(cgImage:cg,size:NSSize(width:sprite.width,height:sprite.height))
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        for (id,x,y) in [(selling ? 0x872 : 0x870,0,0),(selling ? 0x873 : 0x871,251,121)] {
            if let sprite = try? assets.gumps?.sprite(id), let image = Self.image(sprite) {
                image.draw(in:NSRect(x:x,y:y,width:sprite.width,height:sprite.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            }
        }
    }
    func updateGold(_ value:UInt32?) { gold.stringValue = value.map(String.init) ?? "—" }
    private func add(serial:UInt32) {
        guard !pendingPurchase else { return }
        guard let offer = offers.first(where: { $0.item.serial == serial }), quantities[serial,default:0] < offer.item.amount else { return }
        quantities[serial,default:0] += 1; refreshCart()
    }
    @objc private func removeItem(_ sender:NSButton) { guard !pendingPurchase else { return }; quantities[UInt32(sender.tag)] = max(0,quantities[UInt32(sender.tag),default:0]-1); refreshCart() }
    @objc private func clearCart() { guard !pendingPurchase else { return }; quantities = [:]; refreshCart() }
    private func refreshCart() {
        for row in cart.arrangedSubviews { cart.removeArrangedSubview(row); row.removeFromSuperview() }
        var sum: UInt64 = 0
        for offer in offers where quantities[offer.item.serial,default:0] > 0 {
            let quantity = quantities[offer.item.serial]!
            sum += UInt64(quantity)*UInt64(offer.price)
            let label = NSTextField(wrappingLabelWithString:"\(quantity) × \(offer.name)")
            label.textColor = .black; label.font = .systemFont(ofSize:12); label.widthAnchor.constraint(equalToConstant:160).isActive = true
            let remove = NSButton(title:"−",target:self,action:#selector(removeItem(_:))); remove.tag = Int(offer.item.serial)
            cart.addArrangedSubview(NSStackView(views:[label,remove]))
        }
        total.stringValue = String(sum); layoutDocuments()
    }
    @objc private func buy() {
        guard !pendingPurchase, quantities.values.contains(where: { $0 > 0 }) else { return }
        pendingPurchase = true
        buttons.forEach { $0.isEnabled = false }; status.stringValue = "Trade sent. Waiting for the server…"
        onBuy?(quantities)
    }
    override func rightMouseDown(with event:NSEvent) { onClose?() }
}

@MainActor
private final class VendorDocument: NSView { override var isFlipped: Bool { true } }

@MainActor
private final class VendorStockRow: NSView {
    let offer: VendorOffer
    let icon: NSImage?
    var onAdd: (() -> Void)?
    override var isFlipped: Bool { true }
    init(offer:VendorOffer, icon:NSImage?) {
        self.offer = offer; self.icon = icon
        super.init(frame:NSRect(x:0,y:0,width:200,height:52))
        let add = NSButton(title:"+",target:self,action:#selector(addOne))
        add.frame = NSRect(x:177,y:13,width:23,height:24); add.isBordered = false
        add.contentTintColor = .black; add.setAccessibilityLabel("Add \(offer.name)"); addSubview(add)
        setAccessibilityLabel("\(offer.name), \(offer.price) gold, \(offer.item.amount) available")
    }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        if let icon {
            let scale = min(1, min(34/icon.size.width,44/icon.size.height))
            let size = NSSize(width:icon.size.width*scale,height:icon.size.height*scale)
            icon.draw(in:NSRect(x:(36-size.width)/2,y:(52-size.height)/2,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.black,.paragraphStyle:style]
        (offer.name as NSString).draw(in:NSRect(x:40,y:3,width:135,height:30),withAttributes:attrs)
        ("\(offer.price) gold · \(offer.item.amount) avail." as NSString).draw(in:NSRect(x:40,y:34,width:135,height:16),withAttributes:attrs)
    }
    override func mouseDown(with event:NSEvent) { if event.clickCount == 2 { onAdd?() } }
    @objc private func addOne() { onAdd?() }
}
