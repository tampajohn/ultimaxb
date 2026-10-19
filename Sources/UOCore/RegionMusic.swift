import Foundation

/// Optional classic regions.txt music lookup. The original region assignment is
/// block-based (8×8), not an exact rectangle or a terrain-art heuristic.
/// Callers must let live server music override this spawn fallback.
public struct RegionMusic {
    private struct Region {
        let x:Int, y:Int, width:Int, height:Int, music:UInt16, weather:UInt16, order:Int
        var hasWeather:Bool { (music != 0 && music != .max) || (weather != 0 && weather != .max) }
    }
    private let blocks:[UInt16]
    public init(text:String) throws {
        let lines=text.split(whereSeparator: \.isNewline).map { $0.split(whereSeparator: \.isWhitespace) }
        guard let header=lines.first,header.count==2,header[0]=="version",
              let version=Int(header[1]),version==0xFACE || version==0xFACF,
              lines.count<=16385 else { throw AssetError("Unsupported region music format") }
        var regions:[Region]=[]
        for (order,row) in lines.dropFirst().enumerated() {
            guard row.count >= (version==0xFACF ? 14:12),
                  let x=Int(row[1]),let y=Int(row[2]),let width=Int(row[3]),let height=Int(row[4]),
                  (0..<6144).contains(x),(0..<4096).contains(y),
                  (1...6144).contains(width),(1...4096).contains(height),
                  let music=UInt16(row[9]),let weather=UInt16(row[10]) else {
                throw AssetError("Invalid region music record")
            }
            regions.append(Region(x:x,y:y,width:width,height:height,music:music,weather:weather,order:order))
        }
        // Weatherless regions are applied first. Smaller weather regions then
        // override larger ones. Equal-area records retain their input order.
        regions.sort {
            if $0.hasWeather != $1.hasWeather { return !$0.hasWeather }
            if !$0.hasWeather { return $0.order > $1.order }
            let a=$0.width*$0.height,b=$1.width*$1.height
            return a == b ? $0.order < $1.order : a > b
        }
        var grid=[UInt16](repeating:.max,count:768*512)
        for r in regions {
            for x in (r.x/8)...min(767,(r.x+r.width)/8) {
                for y in (r.y/8)...min(511,(r.y+r.height)/8) {
                    grid[x*512+y]=r.music==0 ? .max:r.music
                }
            }
        }
        blocks=grid
    }
    /// Nil means there is no known playable regional assignment. Silence and
    /// unknown IDs do not justify inventing a default song.
    public func track(x:Int,y:Int)->Int? {
        guard (0..<6144).contains(x),(0..<4096).contains(y) else { return nil }
        let id=Int(blocks[(x/8)*512+y/8])
        return MusicCatalog.track(id) == nil ? nil:id
    }
}
