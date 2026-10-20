import AppKit
import UOCore

/// Explicit one-animal order. Server eligibility and arrival are never inferred.
@MainActor final class HerdPanel:ClassicPanel {
    private let assets:ClientAssets
    let animals:ClassicChoice
    let x=ClassicEntry(string:""),y=ClassicEntry(string:""),z=ClassicEntry(string:"")
    private let message:ClassicLabel
    private var candidates:[WorldMobile]=[]
    var onRefresh:(()->[WorldMobile])?
    var onPlayerPosition:(()->WalkPoint?)?
    var onStart:((UInt32,WalkPoint)->Void)?
    var onStop:(()->Void)?
    var onPick:(()->Void)?
    var onClose:(()->Void)?
    var selectedAnimal:UInt32? {
        candidates.indices.contains(animals.indexOfSelectedItem) ? candidates[animals.indexOfSelectedItem].serial:nil
    }
    var isWorking:(()->Bool)?
    init(assets:ClientAssets,position:WalkPoint) {
        self.assets=assets; animals=ClassicChoice(fonts:assets.fonts)
        message=ClassicLabel("Choose a visible animal and where to send it. You need a shepherd's crook. Eligibility is decided by the server.",fonts:assets.fonts)
        super.init(assets:assets); frame=NSRect(x:310,y:30,width:420,height:400)
        let title=ClassicLabel("Herding",fonts:assets.fonts); title.frame=NSRect(x:20,y:16,width:340,height:26); addSubview(title)
        let close=ClassicButton("X",fonts:assets.fonts,target:self,action:#selector(closePanel)); close.frame=NSRect(x:380,y:12,width:26,height:26); addSubview(close)
        animals.frame=NSRect(x:20,y:54,width:280,height:30); animals.setAccessibilityLabel("Visible creature to herd"); addSubview(animals)
        let refresh=ClassicButton("Refresh",fonts:assets.fonts,target:self,action:#selector(refreshAnimals)); refresh.frame=NSRect(x:310,y:54,width:90,height:30); addSubview(refresh)
        for (name,field,left) in [("Destination X",x,20),("Destination Y",y,155),("Height",z,290)] {
            let label=ClassicLabel(name,fonts:assets.fonts); label.frame=NSRect(x:left,y:102,width:110,height:26); addSubview(label)
            field.frame=NSRect(x:left,y:130,width:110,height:28); field.font=ClassicNativeFont.uiFont
            field.isBezeled=false; field.drawsBackground=true
            field.backgroundColor=NSColor(calibratedRed:0.76,green:0.71,blue:0.57,alpha:1); field.textColor = .black
            field.setAccessibilityLabel(name); addSubview(field)
        }
        x.nextKeyView=y; y.nextKeyView=z; z.nextKeyView=animals
        setDestination(position)
        for (title,selector,frame) in [
            ("Send to my position",#selector(centerOnMe),NSRect(x:20,y:176,width:215,height:30)),
            ("Pick on map",#selector(pickOnMap),NSRect(x:245,y:176,width:155,height:30)),
            ("Herd animal",#selector(startHerding),NSRect(x:20,y:220,width:245,height:32)),
            ("Stop",#selector(stopHerding),NSRect(x:275,y:220,width:125,height:32))] {
            let button=ClassicButton(title,fonts:assets.fonts,target:self,action:selector); button.frame=frame; addSubview(button)
        }
        message.frame=NSRect(x:20,y:274,width:380,height:106); addSubview(message)
    }
    required init?(coder:NSCoder) { fatalError() }
    func setDestination(_ point:WalkPoint) { x.stringValue=String(point.x); y.stringValue=String(point.y); z.stringValue=String(point.z) }
    @objc func centerOnMe() {
        guard isWorking?() != true else { showResult("Choose Stop before changing this order."); return }
        if let position=onPlayerPosition?() { setDestination(position) }
    }
    @objc func refreshAnimals() {
        guard isWorking?() != true else { showResult("Choose Stop before changing this order."); return }
        let selected=candidates.indices.contains(animals.indexOfSelectedItem) ? candidates[animals.indexOfSelectedItem].serial:nil
        candidates=onRefresh?() ?? []
        animals.removeAllItems()
        animals.addItems(withTitles:candidates.map { "Creature at \($0.x), \($0.y)" })
        if let selected,let index=candidates.firstIndex(where:{$0.serial==selected}) { animals.selectItem(at:index) }
        if candidates.isEmpty { showResult("No visible creatures. Move near an animal, then Refresh.") }
        ClassicNativeFont.apply(to:animals); animals.needsDisplay=true
    }
    @objc func startHerding() {
        guard isWorking?() != true else { showResult("Herding is already running. Choose Stop first."); return }
        guard candidates.indices.contains(animals.indexOfSelectedItem) else { showResult("Refresh and choose a visible animal first."); return }
        guard let x=Int(x.stringValue),let y=Int(y.stringValue),let z=Int(z.stringValue),
              (0..<assets.width).contains(x),(0..<assets.height).contains(y),(-128...127).contains(z) else {
            showResult("Enter a destination on this map and a height from -128 to 127."); return
        }
        onStart?(candidates[animals.indexOfSelectedItem].serial,.init(x:x,y:y,z:z))
    }
    @objc func pickOnMap() {
        guard isWorking?() != true else { showResult("Choose Stop before changing this order."); return }
        guard selectedAnimal != nil else { showResult("Refresh and choose a visible animal first."); return }
        onPick?()
    }
    func pickedDestination(_ point:WalkPoint?) {
        isHidden=false
        guard let point else { showResult("No nearby ground route was found for this animal. Choose another destination."); return }
        setDestination(point)
        showResult("Destination chosen. Choose Herd animal to begin.")
    }
    @objc func stopHerding() { onStop?() }
    func showResult(_ text:String) { message.stringValue=text }
    @objc func closePanel() { let parent=superview; let host=window; onStop?(); onClose?(); removeFromSuperview(); host?.makeFirstResponder(parent) }
}
