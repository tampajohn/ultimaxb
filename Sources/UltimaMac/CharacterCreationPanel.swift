import AppKit
import UOCore

@MainActor
final class CharacterCreationPanel: NSView {
    private let assets: ClientAssets
    private let appearanceEditor: AppearanceEditor
    private var setupViews: [NSView] = []
    private var showingAppearance = false
    private let appearanceButton:ClassicButton
    private let name = NSTextField(string:"Avatar")
    private let female:ClassicButton
    private let city:ClassicChoice
    private var cities: [StartingCity] = []
    private var stats: [NSTextField] = []
    private var skills: [NSPopUpButton] = []
    private var values: [NSTextField] = []
    private let status:ClassicLabel
    private let create:ClassicButton
    var onCreate: ((String,Bool,UInt8,CharacterAllocation,CharacterAppearance)->Void)?
    var onBack: (() -> Void)?
    override var isFlipped: Bool { true }
    init(assets:ClientAssets) {
        self.assets = assets
        female=ClassicButton("Male",fonts:assets.fonts,target:nil,action:nil)
        city=ClassicChoice(fonts:assets.fonts)
        status=ClassicLabel("",fonts:assets.fonts)
        appearanceButton=ClassicButton("Appearance",fonts:assets.fonts,target:nil,action:nil)
        create=ClassicButton("Create Character",fonts:assets.fonts,target:nil,action:nil)
        appearanceEditor = AppearanceEditor(assets:assets)
        super.init(frame:NSRect(x:0,y:0,width:600,height:500))
        label("Create Character",x:170,y:25,width:300,size:22)
        label("Name",x:40,y:72,width:80)
        styleField(name)
        female.setButtonType(.toggle)
        name.frame = NSRect(x:130,y:68,width:270,height:26); addSubview(name)
        female.frame = NSRect(x:425,y:68,width:100,height:26); addSubview(female)
        let setupStart = subviews.count
        female.target = self; female.action = #selector(sexChanged)
        label("Stats - 60 points total",x:40,y:110,width:400)
        for (i,entry) in [("Strength",30),("Dexterity",15),("Intelligence",15)].enumerated() {
            label(entry.0,x:40+i*175,y:143,width:110)
            let field = number(entry.1,x:40+i*175,y:169); stats.append(field)
        }
        label("Starting skills - 100 points total; max 50 each",x:40,y:213,width:520)
        let defaults = [27,40,17]
        for i in 0..<3 {
            let popup = ClassicChoice(fonts:assets.fonts)
            popup.frame=NSRect(x:40,y:245+i*33,width:350,height:26)
            for skill in assets.skills where skill.id < 49 {
                popup.addItem(withTitle:skill.name); popup.lastItem?.tag = skill.id
            }
            popup.selectItem(withTag:defaults[i]); addSubview(popup); skills.append(popup)
            values.append(number(i == 2 ? 0 : 50,x:420,y:245+i*33))
        }
        label("Starting city",x:40,y:354,width:120)
        city.frame = NSRect(x:170,y:350,width:380,height:26); addSubview(city)
        setupViews = Array(subviews.dropFirst(setupStart))
        appearanceEditor.isHidden = true; addSubview(appearanceEditor)
        appearanceButton.frame = NSRect(x:165,y:448,width:185,height:30); appearanceButton.target = self; appearanceButton.action = #selector(toggleAppearance); addSubview(appearanceButton)
        status.frame = NSRect(x:40,y:387,width:520,height:48); addSubview(status)
        let back = ClassicButton("Back",fonts:assets.fonts,target:self,action:#selector(goBack)); back.frame = NSRect(x:40,y:448,width:100,height:30); addSubview(back)
        create.frame = NSRect(x:375,y:448,width:180,height:30); create.target = self; create.action = #selector(submit); addSubview(create)
    }
    required init?(coder:NSCoder) { fatalError() }
    private func label(_ text:String,x:Int,y:Int,width:Int,size:CGFloat = 15) {
        let field = ClassicLabel(text,fonts:assets.fonts)
        field.frame = NSRect(x:x,y:y,width:width,height:26); addSubview(field)
    }
    private func styleField(_ field:NSTextField) {
        field.isBezeled=false; field.isBordered=true
        field.drawsBackground=true
        field.backgroundColor=NSColor(calibratedRed:0.78,green:0.76,blue:0.64,alpha:1)
        field.textColor=NSColor(calibratedRed:0.18,green:0.12,blue:0.08,alpha:1)
    }
    private func number(_ value:Int,x:Int,y:Int)->NSTextField {
        let field = NSTextField(string:String(value)); field.frame = NSRect(x:x,y:y,width:65,height:26)
        styleField(field)
        let format = NumberFormatter(); format.numberStyle = .none; format.allowsFloats = false; format.minimum = 0; format.maximum = 100
        field.formatter = format; addSubview(field); return field
    }
    func configure(cities:[StartingCity]) {
        self.cities = cities; city.removeAllItems(); city.addItems(withTitles:cities.map { "\($0.name) - \($0.location)" })
        create.isEnabled = !cities.isEmpty; status.stringValue = cities.isEmpty ? "No starting cities were offered by the server." : "Choose your stats and skills, then customize Appearance."
        updateTabOrder()
        window?.makeFirstResponder(name)
    }
    func waiting() { create.isEnabled = false; status.stringValue = "Creating character…" }
    @objc private func sexChanged() {
        female.title=female.state == .on ? "Female" : "Male"
        female.setAccessibilityLabel("Sex: \(female.title)")
        appearanceEditor.setFemale(female.state == .on); updateTabOrder()
    }
    @objc private func toggleAppearance() {
        window?.makeFirstResponder(self)
        showingAppearance.toggle()
        setupViews.forEach { $0.isHidden = showingAppearance }
        appearanceEditor.isHidden = !showingAppearance
        appearanceButton.title = showingAppearance ? "Stats and Skills" : "Appearance"
        appearanceButton.setAccessibilityLabel(appearanceButton.title)
        status.stringValue = ""
        updateTabOrder()
        window?.makeFirstResponder(showingAppearance ? appearanceEditor.controls.first : stats.first)
    }
    private func updateTabOrder() {
        func visible(_ parent:NSView)->[NSView] {
            guard !parent.isHiddenOrHasHiddenAncestor else { return [] }
            if let field=parent as? NSTextField,field.isEditable,field.isEnabled { return [field] }
            if let button=parent as? NSButton,button.isEnabled { return [button] }
            return parent.subviews.flatMap(visible)
        }
        let controls=visible(self)
        for i in controls.indices { controls[i].nextKeyView=controls[(i+1)%controls.count] }
    }
    @objc private func goBack() { onBack?() }
    @objc private func submit() {
        window?.makeFirstResponder(self)
        var allocation = CharacterAllocation()
        allocation.strength = stats[0].integerValue; allocation.dexterity = stats[1].integerValue; allocation.intelligence = stats[2].integerValue
        allocation.skillIDs = skills.map { $0.selectedTag() }; allocation.skillValues = values.map(\.integerValue)
        if let message = allocation.validationMessage { status.stringValue = message; return }
        guard !name.stringValue.trimmingCharacters(in:.whitespaces).isEmpty, name.stringValue.utf8.count < 30,
              name.stringValue.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else { status.stringValue = "Enter a name using 1–29 basic Latin characters."; return }
        guard cities.indices.contains(city.indexOfSelectedItem) else { return }
        onCreate?(name.stringValue,female.state == .on,cities[city.indexOfSelectedItem].index,allocation,appearanceEditor.selection)
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        // Original nine-part stone frame, expanded to contain the creation controls.
        for row in 0..<3 { for col in 0..<3 {
            guard let sprite = try? assets.gumps?.sprite(0xA28+row*3+col),
                  let provider = CGDataProvider(data:Data(sprite.rgba) as CFData),
                  let cg = CGImage(width:sprite.width,height:sprite.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:sprite.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { continue }
            let xs:[CGFloat] = [0,32,568,600], ys:[CGFloat] = [0,32,468,500]
            NSImage(cgImage:cg,size:.zero).draw(in:NSRect(x:xs[col],y:ys[row],width:xs[col+1]-xs[col],height:ys[row+1]-ys[row]),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        } }
    }
}
