import AppKit
import UOCore

@MainActor final class SkillsPanel:ClassicPanel {
    private let rows:NSView = FlippedSkillRows()
    private let scroll=NSScrollView()
    private let definitions:[SkillDefinition]
    private let fonts:ClassicFonts?
    var onUse:((Int)->Void)?
    var onClose:(()->Void)?
    init(definitions:[SkillDefinition],assets:ClientAssets,docked:Bool=false) {
        self.definitions=definitions; fonts=assets.fonts
        super.init(assets:assets)
        frame=NSRect(x:24,y:24,width:350,height:520)
        let title=ClassicLabel("Skills",fonts:fonts); title.frame=NSRect(x:16,y:12,width:180,height:24); addSubview(title)
        if !docked {
            let close=ClassicButton("Close",fonts:fonts,target:self,action:#selector(closePanel)); close.frame=NSRect(x:240,y:8,width:70,height:26); addSubview(close)
        }
        scroll.hasVerticalScroller=true; scroll.drawsBackground=false; scroll.documentView=rows; addSubview(scroll)
        update(SkillState())
    }
    required init?(coder:NSCoder) { fatalError() }
    override func layout() {
        super.layout(); scroll.frame=NSRect(x:10,y:38,width:bounds.width-20,height:max(40,bounds.height-48))
        rows.setFrameSize(NSSize(width:scroll.contentSize.width,height:rows.frame.height))
        for row in rows.subviews { row.frame.size.width=max(80,scroll.contentSize.width-8) }
    }
    func update(_ state:SkillState) {
        rows.subviews.forEach { $0.removeFromSuperview() }
        var y:CGFloat=0
        for definition in definitions.sorted(by:{$0.name<$1.name}) where state.values.isEmpty || state.values[definition.id] != nil {
            let value=state.values[definition.id].map { String(format:"%.1f",Double($0)/10) } ?? "-"
            let name="\(definition.name)  \(value)"
            let row:NSView
            if definition.usable {
                let button=ClassicButton(name,fonts:fonts,target:self,action:#selector(useSkill(_:))); button.tag=definition.id
                button.toolTip="Use \(definition.name)"; row=button
            } else { row=ClassicLabel(name,fonts:fonts) }
            row.frame=NSRect(x:0,y:y,width:max(80,scroll.contentSize.width-8),height:32)
            rows.addSubview(row); y += 36
        }
        rows.frame.size.height=y; needsLayout=true
    }
    @objc private func useSkill(_ sender:NSButton) { onUse?(sender.tag) }
    @objc private func closePanel() { onClose?() }
}
@MainActor private final class FlippedSkillRows:NSView { override var isFlipped:Bool { true } }
