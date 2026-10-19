import AppKit
import UOCore

/// Classic 640x480 selection coordinates and gumps; see LICENSES/ClassicUO.txt.
@MainActor
final class CharacterSelectionPanel: NSView {
    private let assets: ClientAssets
    private var images: [Int:NSImage] = [:]
    private var characters: [GameCharacter] = []
    private var selected: UInt32?
    private var confirming = false
    private var busy = false
    private var message = ""
    var onPlay: ((GameCharacter) -> Void)?
    var onCreate: (() -> Void)?
    var onDelete: ((GameCharacter) -> Void)?
    var onBack: (() -> Void)?
    override var isFlipped: Bool { true }
    init(assets: ClientAssets) { self.assets = assets; super.init(frame:NSRect(x:0,y:0,width:448,height:430)) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    func update(_ characters: [GameCharacter], message: String = "") {
        self.characters = characters; self.message = message; confirming = false; busy = false
        if !characters.contains(where: { $0.slot == selected }) { selected = characters.first?.slot }
        rebuild()
    }
    func waiting(_ message: String) { self.message = message; busy = true; confirming = false; rebuild() }
    private func image(_ id: Int) -> NSImage? {
        if let image = images[id] { return image }
        guard let sprite = try? assets.gumps?.sprite(id), let provider = CGDataProvider(data:Data(sprite.rgba) as CFData),
              let cg = CGImage(width:sprite.width,height:sprite.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:sprite.width*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { return nil }
        let image = NSImage(cgImage:cg,size:NSSize(width:sprite.width,height:sprite.height)); images[id] = image; return image
    }
    private func drawImage(_ id:Int, _ rect:NSRect) {
        image(id)?.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
    private func panel(_ id:Int, _ rect:NSRect) {
        guard let tl = image(id), let br = image(id+8) else { return }
        let xs = [rect.minX,rect.minX+tl.size.width,rect.maxX-br.size.width,rect.maxX]
        let ys = [rect.minY,rect.minY+tl.size.height,rect.maxY-br.size.height,rect.maxY]
        for row in 0..<3 { for col in 0..<3 {
            drawImage(id+row*3+col,NSRect(x:xs[col],y:ys[row],width:xs[col+1]-xs[col],height:ys[row+1]-ys[row]))
        } }
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        panel(0x0A28,NSRect(x:20,y:20,width:408,height:390))
        if !confirming {
            for (i,_) in characters.enumerated() { panel(0x0BB8,NSRect(x:84,y:100+i*40,width:280,height:30)) }
        }
    }
    private func label(_ text:String, rect:NSRect, size:CGFloat = 16, selected:Bool = false) {
        let label = NSTextField(wrappingLabelWithString:text); label.frame = rect
        label.font = ClassicNativeFont.uiFont
        label.textColor = selected ? .systemRed : NSColor(calibratedWhite:0.94,alpha:1)
        label.alignment = .center; addSubview(label)
    }
    private func button(_ id:Int, x:Int, y:Int, title:String, action:Selector, tag:Int = 0, enabled:Bool = true) {
        let button = NSButton(title:title,target:self,action:action); button.tag = tag
        if let image = image(id) {
            button.image = image; button.alternateImage = self.image(id+1); button.imagePosition = .imageOnly; button.isBordered = false
            button.frame = NSRect(x:CGFloat(x),y:CGFloat(y),width:image.size.width,height:image.size.height)
        } else { button.frame = NSRect(x:x,y:y,width:80,height:30) }
        button.setAccessibilityLabel(title); button.toolTip = title; button.isEnabled = enabled && !busy
        addSubview(button)
    }
    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        if confirming, let character = characters.first(where: { $0.slot == selected }) {
            label("Permanently delete \(character.name)?\nThis cannot be undone.",rect:NSRect(x:50,y:100,width:350,height:100),size:20)
            button(0x047B,x:124,y:254,title:"Confirm deletion",action:#selector(confirmDelete))
            button(0x0478,x:208,y:254,title:"Cancel",action:#selector(cancelDelete))
        } else {
            label("Character Selection",rect:NSRect(x:100,y:56,width:250,height:30),size:20)
            for (i,character) in characters.enumerated() {
                let button = NSButton(title:character.name,target:self,action:#selector(selectCharacter(_:)))
                button.frame = NSRect(x:84,y:100+i*40,width:280,height:30); button.tag = Int(character.slot)
                button.isBordered = false; button.font = ClassicNativeFont.uiFont
                button.contentTintColor = character.slot == selected ? .systemRed : .white
                button.isEnabled = !busy; addSubview(button)
            }
            button(0x0453,x:142,y:355,title:"New Character",action:#selector(createCharacter),enabled:characters.count < 5)
            button(0x044D,x:234,y:355,title:"Delete Character",action:#selector(askDelete),enabled:selected != nil)
            button(0x0456,x:50,y:355,title:"Back",action:#selector(back))
            button(0x0459,x:326,y:355,title:"Enter World",action:#selector(play),enabled:selected != nil)
            label(message,rect:NSRect(x:50,y:300,width:348,height:44),size:14)
        }
        needsDisplay = true
    }
    @objc private func selectCharacter(_ sender:NSButton) { selected = UInt32(sender.tag); rebuild() }
    @objc private func askDelete() { confirming = true; rebuild() }
    @objc private func cancelDelete() { confirming = false; rebuild() }
    @objc private func confirmDelete() {
        guard !busy, let character = characters.first(where: { $0.slot == selected }) else { return }
        onDelete?(character)
    }
    @objc private func createCharacter() { onCreate?() }
    @objc private func play() { if let character = characters.first(where: { $0.slot == selected }) { onPlay?(character) } }
    @objc private func back() { onBack?() }
}
