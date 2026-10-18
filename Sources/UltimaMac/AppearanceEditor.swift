import AppKit
import UOCore

@MainActor
final class AppearanceEditor: NSView {
    private let assets: ClientAssets
    private let skin = NSPopUpButton(), hair = NSPopUpButton(), hairColor = NSPopUpButton(), beard = NSPopUpButton(), beardColor = NSPopUpButton()
    private var layers: [(width:Int,height:Int,rgba:[UInt8])] = []
    private let creationGumps: GumpAssets?
    // Use the installed client's art first. This workspace's optional 1.26 pack
    // supplies creation-only art; it never replaces world assets or the protocol.
    private static func creationArtwork(_ assets:ClientAssets) -> GumpAssets? {
        if (try? assets.gumps?.sprite(0x708)) != nil { return assets.gumps }
        let directory = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
            .appendingPathComponent("data/uo-1.26.0")
        do {
            func read(_ name:String) throws -> Data {
                try Data(contentsOf:directory.appendingPathComponent(name),options:.alwaysMapped)
            }
            let gumps = try GumpAssets(index:read("gumpidx.mul"),data:read("gumpart.mul"),verdata:read("verdata.mul"))
            return try gumps.sprite(0x708) == nil ? nil : gumps
        } catch { return nil }
    }
    private var female = false
    override var isFlipped: Bool { true }
    var selection: CharacterAppearance {
        var a = CharacterAppearance()
        a.skinHue = skin.selectedTag(); a.hairStyle = hair.selectedTag(); a.hairHue = hairColor.selectedTag()
        a.beardStyle = female ? 0 : beard.selectedTag(); a.beardHue = beardColor.selectedTag()
        return a
    }
    var controls: [NSView] { [skin,hair,hairColor,beard,beardColor] }
    init(assets:ClientAssets) {
        self.assets = assets
        creationGumps = Self.creationArtwork(assets)
        super.init(frame:NSRect(x:30,y:110,width:540,height:270))
        for (i,entry) in [("Skin tone",skin),("Hair style",hair),("Hair color",hairColor),("Facial hair",beard),("Facial hair color",beardColor)].enumerated() {
            let label = NSTextField(labelWithString:entry.0); label.textColor = .white; label.frame = NSRect(x:[375,0,375,0,375][i],y:[20,40,95,110,170][i],width:160,height:20); addSubview(label)
            entry.1.frame = NSRect(x:[375,0,375,0,375][i],y:[41,61,116,131,191][i],width:160,height:26); entry.1.target = self; entry.1.action = #selector(changed); entry.1.setAccessibilityLabel(entry.0); addSubview(entry.1)
        }
        populateColors(skin,range:0x3EA...0x422)
        populateColors(hairColor,range:0x44E...0x47D); populateColors(beardColor,range:0x44E...0x47D)
        let beardNames = ["None","Long beard","Short beard","Goatee","Mustache","Short beard and mustache","Long beard and mustache","Vandyke"]
        for (id,name) in zip(CharacterAppearance.beardStyles,beardNames) { beard.addItem(withTitle:name); beard.lastItem?.tag = id }
        setFemale(false)
    }
    required init?(coder:NSCoder) { fatalError() }
    private func populateColors(_ popup:NSPopUpButton,range:ClosedRange<Int>) {
        for (index,hue) in range.enumerated() {
            popup.addItem(withTitle:"Shade \(index+1)"); popup.lastItem?.tag = hue
            if let palette = try? assets.huePalette(hue) {
                let c = palette.color(red:192,green:192,blue:192)
                let image = NSImage(size:NSSize(width:20,height:14))
                image.lockFocus(); NSColor(calibratedRed:CGFloat(c.0)/255,green:CGFloat(c.1)/255,blue:CGFloat(c.2)/255,alpha:1).setFill(); NSRect(x:0,y:0,width:20,height:14).fill(); image.unlockFocus()
                popup.lastItem?.image = image
            }
        }
    }
    func setFemale(_ value:Bool) {
        female = value
        let selected = hair.selectedTag()
        hair.removeAllItems()
        let names = ["None","Short","Long","Ponytail","Mohawk","Pageboy","Buns","Curly","Receding","Two tails","Topknot"]
        for (id,name) in zip(CharacterAppearance.hairStyles,names) where female || id != 0x2046 {
            hair.addItem(withTitle:name); hair.lastItem?.tag = id
        }
        if !hair.selectItem(withTag:selected) { hair.selectItem(withTag:0) }
        if female { beard.selectItem(withTag:0) }
        beard.isEnabled = !female; beardColor.isEnabled = !female
        changed()
    }
    @objc private func changed() {
        let a = selection
        if let creationGumps {
            let maleHair = [0x203B:0x753,0x203C:0x754,0x203D:0x757,0x2044:0x755,0x2045:0x74F,0x204A:0x752,0x2047:0x751,0x2048:0x758,0x2049:0x74E]
            let femaleHair = [0x203B:0x737,0x203C:0x732,0x203D:0x735,0x2044:0x733,0x2045:0x734,0x204A:0x730,0x2047:0x72F,0x2048:0x736,0x2049:0x72C,0x2046:0x731]
            let beards = [0x2040:0x759,0x203E:0x75B,0x203F:0x75D,0x2041:0x75C,0x204B:0x75E,0x204C:0x75A,0x204D:0x75F]
            var parts = [(0x708,0),(female ? 0x760 : 0x761,a.skinHue | 0x8000)]
            if let id = (female ? femaleHair : maleHair)[a.hairStyle] { parts.append((id,a.hairHue)) }
            if !female, let id = beards[a.beardStyle] { parts.append((id,a.beardHue)) }
            layers = parts.compactMap { id,hue in
                guard let sprite = try? creationGumps.sprite(id) else { return nil }
                var pixels = sprite.rgba
                if let palette = try? assets.huePalette(hue) {
                    for i in stride(from:0,to:pixels.count,by:4) where pixels[i+3] != 0 {
                        let c = palette.color(red:pixels[i],green:pixels[i+1],blue:pixels[i+2])
                        pixels[i] = c.0; pixels[i+1] = c.1; pixels[i+2] = c.2
                    }
                }
                return (width:sprite.width,height:sprite.height,rgba:pixels)
            }
        } else {
            layers = ((try? Paperdoll.layers(assets:assets,body:female ? 401 : 400,hue:a.skinHue,owner:1,equipment:a.equipment)) ?? []).map { (width:$0.sprite.width,height:$0.sprite.height,rgba:$0.sprite.rgba) }
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        for s in layers {
            guard let provider = CGDataProvider(data:Data(s.rgba) as CFData), let cg = CGImage(width:s.width,height:s.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:s.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { continue }
            NSImage(cgImage:cg,size:NSSize(width:s.width,height:s.height)).draw(in:NSRect(x:180,y:0,width:CGFloat(s.width)*0.7,height:CGFloat(s.height)*0.7),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
    }
}
