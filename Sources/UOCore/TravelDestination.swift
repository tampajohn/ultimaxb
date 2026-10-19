import Foundation
public struct TravelDestination:Codable,Equatable,Sendable {
    public var name:String
    public var x:Int,y:Int
    public init(name:String,x:Int,y:Int) { self.name=name; self.x=x; self.y=y }
    public func valid(width:Int,height:Int)->Bool {
        !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && name.count<=64 && (0..<width).contains(x) && (0..<height).contains(y)
    }
    // Classic Britannia inn coordinates from RunUO Scripts/Accounting/AccountHandler.cs.
    // Deliberately excludes the later New Haven location. Island destinations may
    // require manual boat/moongate travel; these are destinations, not teleports.
    public static let cities:[TravelDestination] = [
        .init(name:"Minoc",x:2476,y:413),.init(name:"Vesper",x:2771,y:976),
        .init(name:"Britain",x:1602,y:1591),.init(name:"Yew",x:633,y:858),
        .init(name:"Trinsic",x:1845,y:2745),.init(name:"Skara Brae",x:618,y:2234),
        .init(name:"Moonglow",x:4408,y:1168),.init(name:"Jhelom",x:1374,y:3826)
    ]
}
