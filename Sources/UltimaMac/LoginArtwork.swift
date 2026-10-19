import AppKit
import UOCore

@MainActor final class LoginArtwork:NSView {
    private let assets:ClientAssets
    private lazy var text=ClassicText(assets.fonts)
    private var images:[Int:NSImage] = [:]
    var mainMenu = false { didSet { needsDisplay=true } }
    var showsForm = true { didSet { needsDisplay=true } }
    var shardSelection = false { didSet { needsDisplay=true } }
    override var isFlipped:Bool { true }
    init(assets:ClientAssets) { self.assets=assets; super.init(frame:NSRect(x:0,y:0,width:640,height:480)) }
    required init?(coder:NSCoder) { fatalError() }
    func image(_ id:Int)->NSImage? {
        if let image=images[id] { return image }
        guard let s=try? assets.gumps?.sprite(id),let provider=CGDataProvider(data:Data(s.rgba) as CFData),
              let cg=CGImage(width:s.width,height:s.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:s.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { return nil }
        let result=NSImage(cgImage:cg,size:NSSize(width:s.width,height:s.height)); images[id]=result; return result
    }
    func drawImage(_ id:Int,at point:NSPoint) {
        if let image=image(id) { image.draw(in:NSRect(origin:point,size:image.size),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    }
    private func panel(_ id:Int,_ rect:NSRect) {
        guard let tl=image(id),let br=image(id+8) else { return }
        let xs=[rect.minX,rect.minX+tl.size.width,rect.maxX-br.size.width,rect.maxX]
        let ys=[rect.minY,rect.minY+tl.size.height,rect.maxY-br.size.height,rect.maxY]
        for row in 0..<3 { for col in 0..<3 {
            image(id+row*3+col)?.draw(in:NSRect(x:xs[col],y:ys[row],width:xs[col+1]-xs[col],height:ys[row+1]-ys[row]),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        } }
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        NSColor.black.setFill(); bounds.fill()
        drawImage(0x3E8,at:.zero)
        if mainMenu { drawImage(0x3F2,at:NSPoint(x:109,y:120)); return }
        guard showsForm else { return }
        let heading=shardSelection ? "Choose your shard" : "Log in to Ultima Online"
        text.draw(heading,at:NSPoint(x:320-text.size(heading).width/2,y:80))
        if !shardSelection {
            panel(0xA28,NSRect(x:135,y:110,width:371,height:256))
            drawImage(0x412,at:NSPoint(x:226,y:140))
            drawImage(0x414,at:NSPoint(x:224,y:175))

        } else { panel(0xA28,NSRect(x:135,y:110,width:371,height:256)) }
    }
}
