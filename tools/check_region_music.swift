import Foundation
import UOCore

@main struct Check {
    static func main() throws {
        guard CommandLine.arguments.count==2 else { fatalError("Supply the installed regions.txt path") }
        let map=try RegionMusic(text:String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8))
        precondition(map.track(x:2502,y:547)==16,"Minoc town music")
        precondition(map.track(x:1427,y:1685)==9,"Britain town music")
        precondition(map.track(x:2300,y:300)==27,"Minoc surrounding forest music")
        print("Installed region music resolves Minoc, Britain and surrounding forest")
    }
}
