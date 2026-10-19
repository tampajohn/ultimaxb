import AppKit
import UOCore

@MainActor
final class SpellbookPanel:NSView {
    let serial:UInt32
    private let assets:ClientAssets
    private let bitmap:ClassicText
    private var known:Set<Int> = []
    private var pair = 0
    private var detailPair:Int?
    private var pendingSelection:DispatchWorkItem?
    private var ordered:[Int] { known.sorted() }
    private var drag:NSPoint?
    private var spellDrag:(id:Int,start:NSPoint)?
    var onClose:(()->Void)?
    var onShortcut:((Int,NSPoint)->Void)?
    var onCast: ((Int)->Void)?
    override var isFlipped:Bool { true }
    init(serial:UInt32,assets:ClientAssets) {
        self.serial = serial; self.assets = assets
        bitmap=ClassicText(assets.fonts,color:(45,30,15),outlined:false)
        super.init(frame:NSRect(x:310,y:70,width:406,height:229))
        toolTip = "Spellbook · Double-click a known spell to cast · Click a name for details · Circle tabs return to the index · Right-click closes · Drag blank paper to move"
        setAccessibilityLabel("Spellbook")
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(_ items:[ContainerItem]) {
        let updated = ClassicSpells.contents(book:serial,items:items)
        guard updated != known else { return }
        pendingSelection?.cancel()
        let visibleIDs=detailPair.map { Array(ordered.dropFirst($0*2).prefix(2)) } ?? []
        known = updated
        if detailPair != nil {
            // Inventory packets can insert lower-numbered spells ahead of the
            // current page. Preserve a visible spell, not its old array offset.
            self.detailPair=visibleIDs.compactMap { ordered.firstIndex(of:$0) }.first.map { $0/2 }
        }
        needsDisplay = true
    }
    private func label(_ text:String,x:Int,y:Int,width:Int = 140,height:Int = 22,size:CGFloat = 13) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:NSRect(x:x,y:y,width:width,height:height)).addClip()
        for (index,line) in bitmap.lines(text,width:CGFloat(width)).enumerated() where index*14<height {
            bitmap.draw(line,at:NSPoint(x:x,y:y+index*14))
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    private func turn(_ delta:Int) {
        pendingSelection?.cancel()
        let current = detailPair.map { $0+4 } ?? pair
        let last = 3+(known.count+1)/2
        let next = max(0,min(last,current+delta))
        if next<4 { pair = next; detailPair = nil } else { detailPair = next-4 }
        needsDisplay = true
    }
    private func sprite(_ id:Int,at point:NSPoint) {
        guard let s = try? assets.gumps?.sprite(id), let provider = CGDataProvider(data:Data(s.rgba) as CFData),
              let cg = CGImage(width:s.width,height:s.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:s.width*4,
                               space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),
                               provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { return }
        NSImage(cgImage:cg,size:.zero).draw(in:NSRect(x:point.x,y:point.y,width:CGFloat(s.width),height:CGFloat(s.height)),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        sprite(0x8AC,at:.zero)
        if let detailPair {
            let ids = ordered
            for side in 0..<2 {
                let index = detailPair*2+side
                guard index<ids.count,let detail = ClassicSpells.detail(id:ids[index]) else { continue }
                let id = ids[index], x = side == 0 ? 56 : 224
                label("Circle \((id-1)/8+1)",x:x+28,y:10)
                sprite(detail.icon,at:NSPoint(x:x,y:57))
                label(ClassicSpells.names[id-1],x:x+48,y:38,width:94,height:28)
                label(detail.words,x:x+48,y:70,width:94,height:28,size:11)
                label("Reagents:",x:x,y:101)
                label(detail.reagents.joined(separator:"\n"),x:x,y:116,height:56,size:11)
            }
        } else {
            for page in 0..<2 {
                let circle = pair*2+page, x = page == 0 ? 58 : 228
                label("Circle \(circle+1)",x:x,y:23,size:14)
                for row in 0..<8 {
                    let id = circle*8+row+1
                    let text = known.contains(id) ? ClassicSpells.names[id-1] : "-"
                    label(text,x:x,y:48+row*15)
                }
            }
        }
        let current = detailPair.map { $0+4 } ?? pair
        if current>0 { sprite(0x8BB,at:NSPoint(x:50,y:8)) }
        if current<3+(known.count+1)/2 { sprite(0x8BC,at:NSPoint(x:321,y:8)) }
        for (i,x) in [58,93,130,164,227,260,297,332].enumerated() { sprite(0x8B1+i,at:NSPoint(x:x,y:175)) }
    }
    private func spell(at point:NSPoint)->Int? {
        if let detailPair {
            for side in 0..<2 {
                let x = side == 0 ? 56 : 224, index = detailPair*2+side
                if NSRect(x:x,y:32,width:142,height:65).contains(point),index<ordered.count { return ordered[index] }
            }
            return nil
        }
        let page:Int
        if (58..<199).contains(point.x) { page = 0 }
        else if (228..<370).contains(point.x) { page = 1 }
        else { return nil }
        guard (48..<168).contains(point.y) else { return nil }
        let id = (pair*2+page)*8+Int((point.y-48)/15)+1
        return known.contains(id) ? id : nil
    }
    override func mouseDown(with event:NSEvent) {
        let p = convert(event.locationInWindow,from:nil)
        pendingSelection?.cancel()
        spellDrag = nil; drag = nil
        if NSRect(x:50,y:8,width:28,height:16).contains(p) { turn(-1); return }
        if NSRect(x:321,y:8,width:28,height:16).contains(p) { turn(1); return }
        if NSRect(x:0,y:95,width:25,height:30).contains(p) { removeFromSuperview(); onClose?(); return }
        if (175..<195).contains(p.y), let tab = [58,93,130,164,227,260,297,332].firstIndex(where: { CGFloat($0)<=p.x && p.x<CGFloat($0+19) }) {
            pair = tab/2; detailPair = nil; needsDisplay = true; return
        }
        if let id = spell(at:p) {
            if event.clickCount == 1 { spellDrag = (id,event.locationInWindow) }
            if event.clickCount == 2 { onCast?(id) }
            else if detailPair == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.superview != nil || self.window != nil,
                          let index = self.ordered.firstIndex(of:id) else { return }
                    self.detailPair = index/2; self.needsDisplay = true
                }
                pendingSelection = work
                DispatchQueue.main.asyncAfter(deadline:.now()+NSEvent.doubleClickInterval,execute:work)
            }
            drag = nil; return
        }
        drag = event.locationInWindow
    }
    override func mouseDragged(with event:NSEvent) {
        if let spellDrag {
            let point = event.locationInWindow
            guard hypot(point.x-spellDrag.start.x,point.y-spellDrag.start.y)>=5 else { return }
            pendingSelection?.cancel()
            guard known.contains(spellDrag.id) else { return }
            onShortcut?(spellDrag.id,point)
            return
        }
        guard let drag else { return }
        frame.origin.x += event.locationInWindow.x-drag.x
        frame.origin.y -= event.locationInWindow.y-drag.y
        self.drag = event.locationInWindow
    }
    override func mouseUp(with event:NSEvent) { drag = nil; spellDrag = nil }
    override func rightMouseDown(with event:NSEvent) { pendingSelection?.cancel(); removeFromSuperview(); onClose?() }
}
