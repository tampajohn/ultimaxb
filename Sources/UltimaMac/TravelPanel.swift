import AppKit
import UOCore

@MainActor final class TravelPanel:ClassicPanel {
    private let defaults=UserDefaults(suiteName:"com.ultimaxb.UltimaMac")!
    private let key:String
    private let assets:ClientAssets
    private var destinations:[TravelDestination]
    private var selected=0
    private let name=ClassicEntry(string:"")
    private let x=ClassicEntry(string:"")
    private let y=ClassicEntry(string:"")
    private let message:ClassicLabel
    private let list=TravelRows()
    private(set) var dropGatheredWhenOverloaded=false
    private(set) var bankGatheredOnArrival=false
    private var bankPoints:[String:[Int]]=[:]
    var onGo:((Int,Int)->Void)?
    var onStop:(()->Void)?
    var onPick:(()->Void)?
    init(assets:ClientAssets,scope:String) {
        self.assets=assets; key="travel.v1.\(scope)"
        message=ClassicLabel("Choose a town, or pick a point on the world map.",fonts:assets.fonts)
        if let data=defaults.data(forKey:key),let saved=try? JSONDecoder().decode([TravelDestination].self,from:data),!saved.isEmpty {
            destinations=Array(saved.filter { $0.valid(width:assets.width,height:assets.height) }.prefix(16))
        } else { destinations=TravelDestination.cities.filter { $0.valid(width:assets.width,height:assets.height) } }
        if destinations.isEmpty { destinations=TravelDestination.cities }
        super.init(assets:assets); frame=NSRect(x:310,y:20,width:420,height:575)
        dropGatheredWhenOverloaded=defaults.bool(forKey:key+".dropGathered")
        bankGatheredOnArrival=defaults.bool(forKey:key+".bankGathered")
        if let data=defaults.data(forKey:key+".banks"),let saved=try? JSONDecoder().decode([String:[Int]].self,from:data) { bankPoints=saved }
        let title=ClassicLabel("Travel journal",fonts:assets.fonts); title.frame=NSRect(x:24,y:16,width:340,height:24); addSubview(title)
        let close=ClassicButton("X",fonts:assets.fonts,target:self,action:#selector(close)); close.frame=NSRect(x:380,y:12,width:26,height:26); addSubview(close)
        list.frame=NSRect(x:20,y:48,width:380,height:216); addSubview(list)
        for (label,field,rect) in [("Name",name,NSRect(x:90,y:270,width:300,height:24)),("X",x,NSRect(x:90,y:300,width:105,height:24)),("Y",y,NSRect(x:280,y:300,width:110,height:24))] {
            let caption=ClassicLabel(label,fonts:assets.fonts); caption.frame=NSRect(x:rect.minX-55,y:rect.minY,width:50,height:24); addSubview(caption)
            field.frame=rect; field.font=ClassicNativeFont.uiFont; field.isBezeled=false; field.backgroundColor=NSColor(calibratedRed:0.76,green:0.71,blue:0.57,alpha:1); field.textColor = .black; field.setAccessibilityLabel(label); addSubview(field)
        }
        for (title,selector,rect) in [
            ("Save",#selector(save),NSRect(x:20,y:334,width:75,height:28)),
            ("Add",#selector(add),NSRect(x:102,y:334,width:65,height:28)),
            ("Remove",#selector(remove),NSRect(x:174,y:334,width:80,height:28)),
            ("Pick on map",#selector(pick),NSRect(x:262,y:334,width:138,height:28)),
            ("Go / resume",#selector(go),NSRect(x:20,y:370,width:175,height:30)),
            ("Stop",#selector(stop),NSRect(x:215,y:370,width:185,height:30))] {
            let button=ClassicButton(title,fonts:assets.fonts,target:self,action:selector); button.frame=rect; addSubview(button)
        }
        let recovery=ClassicButton("",fonts:assets.fonts,target:self,action:#selector(toggleRecovery(_:)))
        recovery.frame=NSRect(x:20,y:406,width:380,height:30)
        updateRecoveryTitle(recovery); addSubview(recovery)
        let banking=ClassicButton("",fonts:assets.fonts,target:self,action:#selector(toggleBanking(_:)))
        banking.frame=NSRect(x:20,y:442,width:380,height:30)
        updateBankingTitle(banking); addSubview(banking)
        message.frame=NSRect(x:20,y:480,width:380,height:80); addSubview(message)
        reload()
    }
    required init?(coder:NSCoder) { fatalError() }
    private func updateRecoveryTitle(_ button:NSButton) {
        button.title="Drop gathered excess: "+(dropGatheredWhenOverloaded ? "on" : "off")
        button.setAccessibilityLabel("Drop newly gathered non-gold goods when overloaded")
        button.needsDisplay=true
    }
    @objc private func toggleRecovery(_ button:NSButton) {
        dropGatheredWhenOverloaded.toggle()
        defaults.set(dropGatheredWhenOverloaded,forKey:key+".dropGathered")
        updateRecoveryTitle(button)
        message.stringValue="Applies on Go / resume. Drops only newly gathered goods; keeps gold and existing belongings."
    }
    // Official town landmarks; see docs/ASSISTANT.md. Editable for shard/era differences.
    private static let bankLandmarks:[String:[Int]] = [
        "Minoc":[2503,554],"Britain":[1427,1685],"Vesper":[2880,683],
        "Jhelom":[1319,3775],"Skara Brae":[591,2142]
    ]
    private func updateBankingTitle(_ button:NSButton) {
        button.title="Bank gathered goods: "+(bankGatheredOnArrival ? "on" : "off")
        button.needsDisplay=true
    }
    @objc private func toggleBanking(_ button:NSButton) {
        bankGatheredOnArrival.toggle(); defaults.set(bankGatheredOnArrival,forKey:key+".bankGathered")
        updateBankingTitle(button); reload()
        message.stringValue=bankGatheredOnArrival ? "X/Y now edit the bank point. Pick on map and Save to adjust it. Go opens the bank and deposits gathered goods." : "X/Y now edit the town destination."
    }
    private func reload() {
        selected=max(0,min(selected,destinations.count-1))
        list.subviews.forEach { $0.removeFromSuperview() }
        // Two columns keep the standard cities visible without a native popup.
        for (i,destination) in destinations.prefix(16).enumerated() {
            let button=ClassicButton((i==selected ? "> " : "")+destination.name,fonts:assets.fonts,target:self,action:#selector(selectDestination(_:)))
            button.tag=i; button.frame=NSRect(x:(i%2)*192,y:(i/2)*27,width:186,height:25); list.addSubview(button)
        }
        let destination=destinations[selected]; name.stringValue=destination.name
        name.isEditable = !bankGatheredOnArrival
        if bankGatheredOnArrival {
            let point=bankPoints[destination.name] ?? Self.bankLandmarks[destination.name]
            x.stringValue=point?.count == 2 ? String(point![0]) : ""
            y.stringValue=point?.count == 2 ? String(point![1]) : ""
        } else { x.stringValue=String(destination.x); y.stringValue=String(destination.y) }
    }
    private func value()->TravelDestination? {
        guard let px=Int(x.stringValue),let py=Int(y.stringValue) else { message.stringValue="Enter valid map coordinates."; return nil }
        let destination=TravelDestination(name:name.stringValue,x:px,y:py)
        guard destination.valid(width:assets.width,height:assets.height) else { message.stringValue="Choose a name and coordinates within this map."; return nil }
        return destination
    }
    private func persist() { if let data=try? JSONEncoder().encode(destinations) { defaults.set(data,forKey:key) } }
    @objc private func selectDestination(_ sender:NSButton) { selected=sender.tag; reload() }
    @objc private func save() {
        guard let value=value() else { return }
        if bankGatheredOnArrival {
            bankPoints[destinations[selected].name]=[value.x,value.y]
            if let data=try? JSONEncoder().encode(bankPoints) { defaults.set(data,forKey:key+".banks") }
        } else { destinations[selected]=value; persist() }
        reload(); message.stringValue=bankGatheredOnArrival ? "Bank destination saved." : "Destination saved."
    }
    @objc private func add() {
        guard !bankGatheredOnArrival else { message.stringValue="Turn banking off to add a town destination."; return }
        guard destinations.count<16,let value=value() else { message.stringValue="Up to 16 destinations are supported."; return }
        destinations.append(value); selected=destinations.count-1; persist(); reload()
    }
    @objc private func remove() { guard destinations.count>1 else { return }; destinations.remove(at:selected); persist(); reload() }
    @objc private func pick() { onPick?() }
    func picked(x:Int,y:Int) { self.x.stringValue=String(x); self.y.stringValue=String(y); message.stringValue="Map point selected. Save to update this destination." }
    @objc private func go() {
        guard let destination=value() else { return }
        message.stringValue=bankGatheredOnArrival ? "Traveling to the bank point. Gathered goods will be deposited after the bank opens." : "Roads preferred; known enemies avoided. Manual movement stops travel."
        onGo?(destination.x,destination.y)
    }
    @objc private func stop() { onStop?(); message.stringValue="Travel stopped. Go / resume replans from your current position." }
    @objc private func close() { removeFromSuperview() }
}

@MainActor private final class TravelRows:NSView { override var isFlipped:Bool { true } }
