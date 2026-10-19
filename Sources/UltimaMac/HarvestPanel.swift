import AppKit
import UOCore

@MainActor final class HarvestPanel:ClassicPanel,NSTextFieldDelegate {
    private let assets:ClientAssets
    private let defaults:UserDefaults
    private let key:String
    let x=ClassicEntry(string:""),y=ClassicEntry(string:""),radius=ClassicEntry(string:"8")
    private(set) var kind:HarvestOutcome.Kind = .mining
    private let message:ClassicLabel
    private let mining:ClassicButton,wood:ClassicButton
    var onPreview:((HarvestWorkflow.Zone,HarvestOutcome.Kind)->Void)?
    var onClear:(()->Void)?
    var onPick:(()->Void)?
    var onPlayerPosition:(()->WalkPoint?)?
    var onStart:((HarvestWorkflow.Zone,HarvestOutcome.Kind)->Void)?
    var onStop:(()->Void)?
    var isHarvesting:(()->Bool)?
    private var validatedZone:HarvestWorkflow.Zone?
    init(assets:ClientAssets,scope:String,position:WalkPoint,defaults:UserDefaults = UserDefaults(suiteName:"com.ultimaxb.UltimaMac")!) {
        self.assets=assets; self.defaults=defaults; key="harvest.preview.v1.\(scope)"
        message=ClassicLabel("Preview reachable work sites before harvesting.",fonts:assets.fonts)
        mining=ClassicButton("Mining",fonts:assets.fonts,target:nil,action:nil)
        wood=ClassicButton("Lumberjacking",fonts:assets.fonts,target:nil,action:nil)
        super.init(assets:assets)
        frame=NSRect(x:310,y:30,width:420,height:430)
        let title=ClassicLabel("Harvest planning",fonts:assets.fonts); title.frame=NSRect(x:20,y:16,width:340,height:25); addSubview(title)
        let close=ClassicButton("X",fonts:assets.fonts,target:self,action:#selector(closePanel)); close.frame=NSRect(x:380,y:12,width:26,height:26); addSubview(close)
        mining.target=self; mining.action=#selector(selectMining); mining.frame=NSRect(x:20,y:52,width:180,height:30); addSubview(mining)
        wood.target=self; wood.action=#selector(selectWood); wood.frame=NSRect(x:210,y:52,width:190,height:30); addSubview(wood)
        x.stringValue=String(position.x); y.stringValue=String(position.y)
        if let saved=defaults.array(forKey:key) as? [Int],saved.count==4,
           (0..<assets.width).contains(saved[0]),(0..<assets.height).contains(saved[1]),(1...32).contains(saved[2]),(0...1).contains(saved[3]) {
            x.stringValue=String(saved[0]); y.stringValue=String(saved[1]); radius.stringValue=String(saved[2]); kind=saved[3]==0 ? .mining : .lumberjacking
        }
        for (name,field,left) in [("Center X",x,20),("Center Y",y,155),("Radius",radius,290)] {
            let caption=ClassicLabel(name,fonts:assets.fonts); caption.frame=NSRect(x:left,y:96,width:110,height:22); addSubview(caption)
            field.frame=NSRect(x:left,y:122,width:110,height:28); field.font=ClassicNativeFont.uiFont
            field.isBezeled=false; field.backgroundColor=NSColor(calibratedRed:0.76,green:0.71,blue:0.57,alpha:1); field.textColor = .black
            field.delegate=self; field.setAccessibilityLabel(name); addSubview(field)
        }
        x.nextKeyView=y; y.nextKeyView=radius; radius.nextKeyView=x
        for (name,selector,left,width) in [("Pick center on map",#selector(pick),20,200),("Preview zone",#selector(preview),230,170)] {
            let button=ClassicButton(name,fonts:assets.fonts,target:self,action:selector); button.frame=NSRect(x:left,y:170,width:width,height:32); addSubview(button)
        }
        let around=ClassicButton("Center on me",fonts:assets.fonts,target:self,action:#selector(centerOnMe))
        around.frame=NSRect(x:20,y:212,width:380,height:30); addSubview(around)
        let start=ClassicButton("Start harvesting",fonts:assets.fonts,target:self,action:#selector(startHarvesting))
        start.frame=NSRect(x:20,y:252,width:235,height:32); addSubview(start)
        let stop=ClassicButton("Stop",fonts:assets.fonts,target:self,action:#selector(stopHarvesting))
        stop.frame=NSRect(x:265,y:252,width:135,height:32); addSubview(stop)
        message.frame=NSRect(x:20,y:300,width:380,height:110); addSubview(message)
        updateKind()
    }
    required init?(coder:NSCoder) { fatalError() }
    private func updateKind() { mining.title=kind == .mining ? "Mining *" : "Mining"; wood.title=kind == .lumberjacking ? "Lumberjacking *" : "Lumberjacking"; mining.needsDisplay=true; wood.needsDisplay=true }
    @objc func selectMining() { kind = .mining; updateKind(); clear() }
    @objc func selectWood() { kind = .lumberjacking; updateKind(); clear() }
    private func clear() { validatedZone=nil; onStop?(); onClear?(); message.stringValue="Choose Preview zone to show the work area." }
    func controlTextDidChange(_ notification:Notification) { clear() }
    @objc private func pick() { onPick?() }
    func picked(x:Int,y:Int) { self.x.stringValue=String(x); self.y.stringValue=String(y); clear() }
    @objc func centerOnMe() {
        guard let position=onPlayerPosition?() else { showResult("Connect to center the zone on your character."); return }
        picked(x:position.x,y:position.y)
        preview()
    }
    @objc func startHarvesting() {
        guard isHarvesting?() != true else {
            showResult("Harvesting is already running. Choose Stop before starting another run."); return
        }
        preview()
        if let zone=validatedZone { onStart?(zone,kind) }
    }
    @objc func stopHarvesting() { onStop?() }
    @objc func preview() {
        validatedZone=nil; onStop?(); onClear?()
        guard let cx=Int(x.stringValue),let cy=Int(y.stringValue),let r=Int(radius.stringValue),
              (0..<assets.width).contains(cx),(0..<assets.height).contains(cy),(1...32).contains(r),
              cx-r>=0,cy-r>=0,cx+r<assets.width,cy+r<assets.height,
              let zone=try? HarvestWorkflow.Zone(x1:cx-r,y1:cy-r,x2:cx+r,y2:cy+r) else {
            message.stringValue="Enter a map center and a radius from 1 to 32. The entire zone must stay on the map."; return
        }
        defaults.set([cx,cy,r,kind == .mining ? 0 : 1],forKey:key)
        validatedZone=zone
        onPreview?(zone,kind)
    }
    func showResult(_ text:String) { message.stringValue=text }
    @objc func closePanel() { let parent=superview; let host=window; onStop?(); onClear?(); removeFromSuperview(); host?.makeFirstResponder(parent) }
}
