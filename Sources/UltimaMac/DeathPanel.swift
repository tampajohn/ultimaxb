import AppKit
import UOCore

@MainActor
final class DeathPanel:NSView {
    private let message = NSTextField(wrappingLabelWithString:"You are dead.")
    private let remain = NSButton(title:"Remain a ghost",target:nil,action:nil)
    private let resurrect = NSButton(title:"Request resurrection",target:nil,action:nil)
    private let assets:ClientAssets
    var onChoice: ((Bool)->Void)?
    override var isFlipped:Bool { true }
    init(assets:ClientAssets) {
        self.assets = assets
        super.init(frame:NSRect(x:320,y:180,width:400,height:160))
        message.frame = NSRect(x:28,y:28,width:344,height:45); message.font = .boldSystemFont(ofSize:18); message.textColor = .white; addSubview(message)
        remain.frame = NSRect(x:24,y:100,width:155,height:28); remain.target = self; remain.action = #selector(stay); addSubview(remain)
        resurrect.frame = NSRect(x:185,y:100,width:190,height:28); resurrect.target = self; resurrect.action = #selector(request); addSubview(resurrect)
    }
    required init?(coder:NSCoder) { fatalError() }
    func update(_ state:DeathState) {
        remain.isEnabled = state.phase == .offered; resurrect.isEnabled = state.phase == .offered
        message.stringValue = state.phase == .awaitingResurrection ? "Waiting for the server to resurrect you…" : "You are dead."
    }
    @objc private func stay() { onChoice?(false) }
    @objc private func request() { onChoice?(true) }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        for row in 0..<3 { for col in 0..<3 {
            guard let s = try? assets.gumps?.sprite(0xA28+row*3+col), let provider = CGDataProvider(data:Data(s.rgba) as CFData),
                  let cg = CGImage(width:s.width,height:s.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:s.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { continue }
            let xs:[CGFloat] = [0,24,376,400], ys:[CGFloat] = [0,24,136,160]
            NSImage(cgImage:cg,size:.zero).draw(in:NSRect(x:xs[col],y:ys[row],width:xs[col+1]-xs[col],height:ys[row+1]-ys[row]),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        } }
    }
}
