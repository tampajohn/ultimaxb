import AppKit
import UOCore

@MainActor final class TextPromptPanel:NSView,NSTextFieldDelegate {
    let request:TextPrompt
    private let assets:ClientAssets
    private let entry = ClassicEntry(string:"")
    private let errorLabel = NSTextField(wrappingLabelWithString:"")
    var onReply:((String,Bool)->Void)?
    override var isFlipped:Bool { true }
    init(request:TextPrompt,assets:ClientAssets) {
        self.request = request; self.assets = assets
        super.init(frame:NSRect(x:320,y:150,width:380,height:260))
        if let image = image(0x474) { frame.size = image.size }
        for (text,y,height) in [(request.title,40,60),(request.detail,102,26)] {
            let label = NSTextField(wrappingLabelWithString:text); label.textColor = .black
            label.frame = NSRect(x:60,y:y,width:270,height:height); addSubview(label)
        }
        entry.frame = NSRect(x:71,y:137,width:230,height:24)
        entry.isBordered = false; entry.drawsBackground = false; entry.textColor = .black
        entry.delegate = self; entry.target = self; entry.action = #selector(submit); entry.isEditable = request.variant != 0; addSubview(entry)
        for (id,x,title,selector) in [(0x47B,117,"Submit",#selector(submit)),(0x478,204,"Cancel",#selector(cancel))] {
            if title == "Cancel" && !request.allowsCancel { continue }
            let button = ClassicButton(title,fonts:assets.fonts,target:self,action:selector)
            button.image = image(id); button.alternateImage = image(id+1); button.imagePosition = .imageOnly; button.isBordered = false
            button.frame = NSRect(x:x,y:190,width:Int(button.image?.size.width ?? 70),height:Int(button.image?.size.height ?? 24))
            button.setAccessibilityLabel(title); addSubview(button)
        }
        errorLabel.textColor = .systemRed; errorLabel.font = ClassicNativeFont.uiFont
        errorLabel.frame = NSRect(x:60,y:163,width:270,height:25); addSubview(errorLabel)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window != nil { window?.makeFirstResponder(entry) } }
    private func image(_ id:Int)->NSImage? {
        guard let sprite = try? assets.gumps?.sprite(id), let provider = CGDataProvider(data:Data(sprite.rgba) as CFData),
              let cg = CGImage(width:sprite.width,height:sprite.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:sprite.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { return nil }
        return NSImage(cgImage:cg,size:NSSize(width:sprite.width,height:sprite.height))
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        image(0x474)?.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        if let field = image(0x477) { field.draw(in:NSRect(origin:NSPoint(x:60,y:130),size:field.size),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    }
    @objc private func submit() {
        do { _ = try request.response(text:entry.stringValue,accepted:true); onReply?(entry.stringValue,true) }
        catch { errorLabel.stringValue = String(describing:error) }
    }
    @objc private func cancel() { if request.allowsCancel { onReply?("",false) } }
    override func rightMouseDown(with event:NSEvent) { cancel() }
    func control(_ control:NSControl,textView:NSTextView,doCommandBy selector:Selector)->Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { cancel(); return true }
        return false
    }
}
