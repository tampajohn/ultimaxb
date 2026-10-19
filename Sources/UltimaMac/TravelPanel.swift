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
        super.init(assets:assets); frame=NSRect(x:310,y:45,width:420,height:535)
        let title=ClassicLabel("Travel journal",fonts:assets.fonts); title.frame=NSRect(x:24,y:16,width:340,height:24); addSubview(title)
        let close=ClassicButton("X",fonts:assets.fonts,target:self,action:#selector(close)); close.frame=NSRect(x:380,y:12,width:26,height:26); addSubview(close)
        list.frame=NSRect(x:20,y:48,width:380,height:216); addSubview(list)
        for (label,field,rect) in [("Name",name,NSRect(x:90,y:282,width:300,height:24)),("X",x,NSRect(x:90,y:316,width:105,height:24)),("Y",y,NSRect(x:280,y:316,width:110,height:24))] {
            let caption=ClassicLabel(label,fonts:assets.fonts); caption.frame=NSRect(x:rect.minX-55,y:rect.minY,width:50,height:24); addSubview(caption)
            field.frame=rect; field.font=ClassicNativeFont.uiFont; field.isBezeled=false; field.backgroundColor=NSColor(calibratedRed:0.76,green:0.71,blue:0.57,alpha:1); field.textColor = .black; field.setAccessibilityLabel(label); addSubview(field)
        }
        for (title,selector,rect) in [
            ("Save",#selector(save),NSRect(x:20,y:356,width:75,height:28)),
            ("Add",#selector(add),NSRect(x:102,y:356,width:65,height:28)),
            ("Remove",#selector(remove),NSRect(x:174,y:356,width:80,height:28)),
            ("Pick on map",#selector(pick),NSRect(x:262,y:356,width:138,height:28)),
            ("Go / resume",#selector(go),NSRect(x:20,y:400,width:175,height:30)),
            ("Stop",#selector(stop),NSRect(x:215,y:400,width:185,height:30))] {
            let button=ClassicButton(title,fonts:assets.fonts,target:self,action:selector); button.frame=rect; addSubview(button)
        }
        message.frame=NSRect(x:20,y:448,width:380,height:70); addSubview(message)
        reload()
    }
    required init?(coder:NSCoder) { fatalError() }
    private func reload() {
        selected=max(0,min(selected,destinations.count-1))
        list.subviews.forEach { $0.removeFromSuperview() }
        // Two columns keep the standard cities visible without a native popup.
        for (i,destination) in destinations.prefix(16).enumerated() {
            let button=ClassicButton((i==selected ? "> " : "")+destination.name,fonts:assets.fonts,target:self,action:#selector(selectDestination(_:)))
            button.tag=i; button.frame=NSRect(x:(i%2)*192,y:(i/2)*27,width:186,height:25); list.addSubview(button)
        }
        let destination=destinations[selected]; name.stringValue=destination.name; x.stringValue=String(destination.x); y.stringValue=String(destination.y)
    }
    private func value()->TravelDestination? {
        guard let px=Int(x.stringValue),let py=Int(y.stringValue) else { message.stringValue="Enter valid map coordinates."; return nil }
        let destination=TravelDestination(name:name.stringValue,x:px,y:py)
        guard destination.valid(width:assets.width,height:assets.height) else { message.stringValue="Choose a name and coordinates within this map."; return nil }
        return destination
    }
    private func persist() { if let data=try? JSONEncoder().encode(destinations) { defaults.set(data,forKey:key) } }
    @objc private func selectDestination(_ sender:NSButton) { selected=sender.tag; reload() }
    @objc private func save() { guard let value=value() else { return }; destinations[selected]=value; persist(); reload(); message.stringValue="Destination saved." }
    @objc private func add() {
        guard destinations.count<16,let value=value() else { message.stringValue="Up to 16 destinations are supported."; return }
        destinations.append(value); selected=destinations.count-1; persist(); reload()
    }
    @objc private func remove() { guard destinations.count>1 else { return }; destinations.remove(at:selected); persist(); reload() }
    @objc private func pick() { onPick?() }
    func picked(x:Int,y:Int) { self.x.stringValue=String(x); self.y.stringValue=String(y); message.stringValue="Map point selected. Save to update this destination." }
    @objc private func go() {
        guard let destination=value() else { return }
        message.stringValue="Roads preferred; known enemies avoided. Manual movement stops travel."
        onGo?(destination.x,destination.y)
    }
    @objc private func stop() { onStop?(); message.stringValue="Travel stopped. Go / resume replans from your current position." }
    @objc private func close() { removeFromSuperview() }
}

@MainActor private final class TravelRows:NSView { override var isFlipped:Bool { true } }
