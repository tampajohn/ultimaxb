import AppKit
import UOCore

/// A classic server layout, rendered locally without executing markup.
@MainActor final class ServerGumpPanel: NSView, NSTextFieldDelegate {
    let definition: ServerGump
    private let assets: ClientAssets
    private var pages: [(NSView, Int)] = []
    private var choices: [(NSButton, UInt32, Int?)] = []
    private var entries: [(NSTextField, UInt16)] = []
    private var entryLimits:[ObjectIdentifier:Int] = [:]
    private var replies: [Int: (Int, UInt32)] = [:]
    private var drag: NSPoint?
    private var movable = true, closable = true
    var onReply: ((UInt32, [UInt32], [(UInt16,String)]) -> Void)?
    override var isFlipped: Bool { true }

    init(definition: ServerGump, assets: ClientAssets) {
        self.definition = definition; self.assets = assets
        super.init(frame: NSRect(x:max(0,min(800,Int(definition.x))),y:max(0,min(500,Int(definition.y))),width:1,height:1))
        var page = 0, group = 0
        var unsupported = 0
        for command in definition.commands {
            let a = command.arguments.compactMap(Int.init)
            func valid(_ count:Int)->Bool { a.count >= count && a.count == command.arguments.count && a.allSatisfy { Int32(exactly:$0) != nil } }
            func rect(_ x:Int,_ y:Int,_ w:Int,_ h:Int)->NSRect {
                NSRect(x:max(-2048,min(2048,x)),y:max(-2048,min(2048,y)),width:max(0,min(2048,w)),height:max(0,min(2048,h)))
            }
            func add(_ view:NSView) {
                addSubview(view); pages.append((view,page))
                frame.size.width = max(frame.width,min(2048,view.frame.maxX))
                frame.size.height = max(frame.height,min(2048,view.frame.maxY))
            }
            func art(_ id:Int,_ x:Int,_ y:Int,hue:Int=0) {
                guard let image = image(id,hue:hue) else { return }
                let view = GumpArtwork(frame:rect(x,y,Int(image.size.width),Int(image.size.height)))
                view.image = image; add(view)
            }
            switch command.name {
            case "page": if valid(1) { page = a[0] }
            case "group": if valid(1) { group = a[0] }
            case "endgroup": group = 0
            case "nomove": movable = false
            case "noclose": closable = false
            case "nodispose": break // Disposal is controlled by replies and connection lifecycle.
            case "gumppic":
                let tokens=command.arguments
                let position=tokens.prefix(3).compactMap(Int.init)
                guard position.count==3,position.allSatisfy({Int32(exactly:$0) != nil}) else {
                    unsupported += 1; continue
                }
                var hue=0
                if tokens.count>3 {
                    let option=tokens[3].split(separator:"=",omittingEmptySubsequences:false)
                    let value=option.count==1 ? Int(option[0]) :
                        (option.count==2 && option[0].lowercased()=="hue" ? Int(option[1]):nil)
                    if let value,(0...65535).contains(value) { hue=value }
                    else { unsupported += 1 }
                }
                if tokens.count>4 { unsupported += 1 }
                art(position[2],position[0],position[1],hue:hue)
            case "tilepic", "tilepichue":
                guard valid(command.name == "tilepichue" ? 4 : 3), (0..<0x4000).contains(a[2]),
                      let sprite = try? assets.sprite(a[2]+0x4000) else { continue }
                let palette = try? assets.huePalette(a.count > 3 ? a[3] : 0,art:a[2]+0x4000)
                let view = GumpArtwork(frame:rect(a[0],a[1],sprite.width,sprite.height))
                view.image = Self.spriteImage(sprite,palette:palette); add(view)
            case "gumppictiled":
                guard valid(5) else { continue }
                let view = GumpArtwork(frame:rect(a[0],a[1],a[2],a[3]))
                view.image = image(a[4]); view.tiled = true; add(view)
            case "htmlgump":
                guard valid(7), definition.texts.indices.contains(a[4]), a[2] > 0, a[3] > 0 else { continue }
                let scroll = NSScrollView(frame:rect(a[0],a[1],a[2],a[3]))
                scroll.hasVerticalScroller = a[6] != 0; scroll.drawsBackground = a[5] != 0
                scroll.backgroundColor = NSColor(calibratedRed:0.92,green:0.89,blue:0.79,alpha:1)
                let width = max(1,scroll.contentSize.width)
                let text = NSTextView(frame:NSRect(x:0,y:0,width:width,height:scroll.contentSize.height))
                text.isEditable = false; text.isSelectable = false; text.drawsBackground = false
                text.isHorizontallyResizable = false; text.isVerticallyResizable = true
                text.textContainer?.containerSize = NSSize(width:width,height:CGFloat.greatestFiniteMagnitude)
                text.textContainer?.widthTracksTextView = true
                text.textStorage?.setAttributedString(GumpText.attributed(definition.texts[a[4]],color:a[5] != 0 ? .black : .white))
                text.layoutManager?.ensureLayout(for:text.textContainer!)
                text.setFrameSize(NSSize(width:width,height:max(scroll.contentSize.height,(text.layoutManager?.usedRect(for:text.textContainer!).height ?? 0)+16)))
                scroll.documentView = text; add(scroll)
            case "resizepic":
                guard valid(5), a[3] > 0, a[4] > 0 else { continue }
                let w = min(2048,a[3]), h = min(2048,a[4])
                let left = min(w/2,Int(image(a[2])?.size.width ?? 0))
                let right = min(w/2,Int(image(a[2]+2)?.size.width ?? 0))
                let top = min(h/2,Int(image(a[2])?.size.height ?? 0))
                let bottom = min(h/2,Int(image(a[2]+6)?.size.height ?? 0))
                let xs = [0,left,w-right,w], ys = [0,top,h-bottom,h]
                for row in 0..<3 { for col in 0..<3 {
                    let view = GumpArtwork(frame:rect(a[0]+xs[col],a[1]+ys[row],xs[col+1]-xs[col],ys[row+1]-ys[row]))
                    view.image = image(a[2]+row*3+col)
                    // Classic resizepic repeats its edges and center at native
                    // pixel size; stretching blurs and distorts the stonework.
                    view.tiled = row == 1 || col == 1
                    add(view)
                } }
            case "text", "croppedtext":
                let cropped = command.name == "croppedtext"
                guard valid(cropped ? 6 : 4) else { continue }
                let index = a[cropped ? 5 : 3]
                guard definition.texts.indices.contains(index) else { continue }
                let label = NSTextField(labelWithString:definition.texts[index])
                label.font = ClassicNativeFont.uiFont; label.textColor = textColor(a[cropped ? 4 : 2],increment:true)
                label.sizeToFit()
                label.frame = rect(a[0],a[1],cropped ? a[2] : Int(label.frame.width),cropped ? a[3] : 22)
                add(label)
            case "button":
                guard valid(7), a[6] >= 0, a[6] <= Int(UInt32.max) else { continue }
                let button = NSButton(title:"",target:self,action:#selector(buttonPressed(_:)))
                button.image = image(a[2]); button.alternateImage = image(a[3]); button.isBordered = false
                button.frame = rect(a[0],a[1],Int(button.image?.size.width ?? 24),Int(button.image?.size.height ?? 24))
                button.tag = replies.count
                replies[button.tag] = (a[4] == 0 ? a[5] : -1,UInt32(a[6]))
                add(button)
            case "checkbox", "radio":
                guard valid(6), a[5] >= 0, a[5] <= Int(UInt32.max) else { continue }
                let button = NSButton(title:"",target:self,action:#selector(choicePressed(_:)))
                button.setButtonType(.toggle); button.isBordered = false
                button.image = image(a[2]); button.alternateImage = image(a[3]); button.state = a[4] == 0 ? .off : .on
                button.frame = rect(a[0],a[1],Int(button.image?.size.width ?? 24),Int(button.image?.size.height ?? 24))
                choices.append((button,UInt32(a[5]),command.name == "radio" ? group : nil)); add(button)
            case "textentry", "textentrylimited":
                let limited=command.name == "textentrylimited"
                guard valid(limited ? 8:7), (0...65535).contains(a[5]), definition.texts.indices.contains(a[6]),
                      !limited || (0...65535).contains(a[7]) else { continue }
                let field = ClassicEntry(string:definition.texts[a[6]])
                if limited,a[7]>0 {
                    entryLimits[ObjectIdentifier(field)]=a[7]
                    field.stringValue=ServerGump.limitedText(field.stringValue,units:a[7])
                    field.delegate=self
                }
                field.font = ClassicNativeFont.uiFont
                field.frame = rect(a[0],a[1],a[2],a[3]); field.isBordered = false; field.drawsBackground = false
                field.textColor = textColor(a[4],increment:false); entries.append((field,UInt16(a[5]))); add(field)
            default: unsupported += 1
            }
        }
        showPage(pages.contains { $0.1 == 1 } ? 1 : pages.first(where: { $0.1 > 0 })?.1 ?? 0)
        Telemetry.shared.record("gump_layout",["id":definition.id,"commands":definition.commands.count,"unsupported":unsupported])
    }
    required init?(coder:NSCoder) { fatalError() }
    private func textColor(_ hue:Int,increment:Bool)->NSColor {
        guard hue > 0, hue < 0x3FFF, let palette = try? assets.huePalette(hue+(increment ? 1 : 0)) else { return .white }
        let c = palette.color(red:255,green:255,blue:255)
        return NSColor(srgbRed:CGFloat(c.0)/255,green:CGFloat(c.1)/255,blue:CGFloat(c.2)/255,alpha:1)
    }
    private func image(_ id:Int,hue:Int=0)->NSImage? {
        guard id >= 0, id <= 65535, let sprite = try? assets.gumps?.sprite(id) else { return nil }
        return Self.spriteImage(sprite,palette:try? assets.huePalette(hue))
    }
    private static func spriteImage(_ sprite:Sprite,palette:HuePalette? = nil)->NSImage? {
        var pixels = sprite.rgba
        if let palette {
            for i in stride(from:0,to:pixels.count,by:4) where pixels[i+3] != 0 {
                let c = palette.color(red:pixels[i],green:pixels[i+1],blue:pixels[i+2])
                pixels[i] = c.0; pixels[i+1] = c.1; pixels[i+2] = c.2
            }
        }
        guard let provider = CGDataProvider(data:Data(pixels) as CFData),
              let cg = CGImage(width:sprite.width,height:sprite.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:sprite.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { return nil }
        return NSImage(cgImage:cg,size:NSSize(width:sprite.width,height:sprite.height))
    }
    private func showPage(_ page:Int) {
        for (view,p) in pages { view.isHidden = p != 0 && p != page }
    }
    @objc private func buttonPressed(_ button:NSButton) {
        guard let (page,id) = replies[button.tag] else { return }
        if page >= 0 { if page > 0 { showPage(page) }; return }
        reply(id)
    }
    @objc private func choicePressed(_ button:NSButton) {
        guard let choice = choices.first(where: { $0.0 === button }), let group = choice.2 else { return }
        for (other,_,g) in choices where g == group { other.state = other === button ? .on : .off }
    }
    func controlTextDidChange(_ notification:Notification) {
        guard let field=notification.object as? NSTextField,let limit=entryLimits[ObjectIdentifier(field)] else { return }
        let editor=field.currentEditor() as? NSTextView
        guard editor?.hasMarkedText() != true else { return }
        let text=ServerGump.limitedText(field.stringValue,units:limit)
        guard text != field.stringValue else { return }
        let selection=editor?.selectedRange()
        field.stringValue=text
        if let editor {
            editor.string=text
            editor.setSelectedRange(NSRange(location:min(selection?.location ?? text.utf16.count,text.utf16.count),length:0))
        }
    }
    private func reply(_ id:UInt32) {
        window?.makeFirstResponder(self)
        onReply?(id,choices.filter { $0.0.state == .on }.map { $0.1 },entries.map { field,id in
            let text=entryLimits[ObjectIdentifier(field)].map { limit in ServerGump.limitedText(field.stringValue,units:limit) } ?? field.stringValue
            return (id,text)
        })
    }
    override func rightMouseDown(with event:NSEvent) { if closable { reply(0) } }
    override func mouseDown(with event:NSEvent) { if movable { drag = event.locationInWindow } }
    override func mouseDragged(with event:NSEvent) {
        guard let drag else { return }
        frame.origin.x += event.locationInWindow.x-drag.x; frame.origin.y -= event.locationInWindow.y-drag.y
        self.drag = event.locationInWindow
    }
    override func mouseUp(with event:NSEvent) { drag = nil }
}
@MainActor private final class GumpArtwork:NSView {
    var image:NSImage?
    var tiled = false
    override func hitTest(_ point:NSPoint)->NSView? { nil }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        guard let image else { return }
        if tiled, image.size.width > 0, image.size.height > 0 {
            NSGraphicsContext.saveGraphicsState(); bounds.clip()
            for y in stride(from:CGFloat(0),to:bounds.height,by:image.size.height) {
                for x in stride(from:CGFloat(0),to:bounds.width,by:image.size.width) {
                    image.draw(in:NSRect(origin:NSPoint(x:x,y:y),size:image.size),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        } else { image.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    }
    override var isFlipped:Bool { true }
}
