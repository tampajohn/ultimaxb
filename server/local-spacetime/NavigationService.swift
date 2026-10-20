import Foundation

// Compiled alongside a snapshot of UOCore. Uses exactly the client's asset
// readers, VERDATA overrides, slope averaging, and living-player collision rules.
@main
struct NavigationService {
    struct Object: Decodable, Equatable {
        let serial: UInt32
        let graphic: Int
        let x: Int, y: Int, z: Int
    }
    struct Request: Decodable {
        let op: String
        let x: Int, y: Int, z: Int
        let direction: Int?
        let graphic: Int?
        let objects: [Object]?
    }
    struct Target: Encodable {
        let x: Int, y: Int, z: Int, graphic: Int
    }
    struct Reply: Encodable {
        var x: Int? = nil, y: Int? = nil, z: Int? = nil
        var blocked = false
        var error: String? = nil
        var target: Target? = nil
        init(_ point: WalkPoint?) {
            if let point { x = point.x; y = point.y; z = point.z }
            else { blocked = true }
        }
        init(error: String) { self.error = error }
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw AssetError("Expected client asset directory") }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        // UOCore allows missing tiledata for rendering; authoritative collision must not.
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).map { $0.lowercased() }
        guard names.contains("tiledata.mul") else { throw AssetError("Collision requires tiledata.mul") }
        let assets = try ClientAssets(directory: directory)
        guard assets.width == 6144 else { throw AssetError("This server supports the classic 6144-wide map") }
        var cached: NavigationMap?
        var objects: [Object] = []
        var center = WalkPoint(x: -100, y: -100, z: 0)
        func map(_ point: WalkPoint) throws -> NavigationMap {
            if cached == nil || max(abs(point.x-center.x), abs(point.y-center.y)) > 16 {
                let tiles = objects.map { object -> WorldTile in
                    var tile = WorldTile(x:object.x,y:object.y,z:object.z,art:object.graphic+0x4000,hue:0)
                    tile.isDynamic = true; tile.sourceSerial = object.serial
                    return tile
                }
                cached = try NavigationMap(assets: assets, center: point, additional: tiles, radius: 24)
                center = point
            }
            return cached!
        }
        let encoder = JSONEncoder()
        func respond(_ reply: Reply) throws {
            FileHandle.standardOutput.write(try encoder.encode(reply) + Data([10]))
        }
        // Startup handshake ensures missing/corrupt assets fail before accepting players.
        try respond(Reply(WalkPoint(x: assets.width, y: assets.height, z: 0)))
        while let line = readLine() {
            do {
                guard line.utf8.count < 16384 else { throw AssetError("Oversized request") }
                let request = try JSONDecoder().decode(Request.self, from: Data(line.utf8))
                if let incoming = request.objects {
                    guard incoming.count <= 128, incoming.allSatisfy({
                        (0..<0x4000).contains($0.graphic) && (0..<6143).contains($0.x) &&
                        (0..<4095).contains($0.y) && (-128...127).contains($0.z)
                    }) else { throw AssetError("Invalid dynamic obstacles") }
                    if incoming != objects { objects = incoming; cached = nil }
                }
                guard (0..<assets.width-1).contains(request.x), (0..<assets.height-1).contains(request.y),
                      (-128...127).contains(request.z) else { try respond(Reply(nil)); continue }
                let point = WalkPoint(x: request.x, y: request.y, z: request.z)
                if ["tree","ore","forge"].contains(request.op) {
                    let tiles = try assets.region(x:point.x,y:point.y,radius:0)
                    let valid = tiles.contains {
                        guard !$0.isDynamic && $0.x == point.x && $0.y == point.y && $0.z == point.z else { return false }
                        let graphic = $0.isStatic ? $0.art-0x4000 : $0.art
                        if request.op == "forge" {
                            return $0.isStatic && graphic == request.graphic && SmeltOutcome.isForge(graphic)
                        }
                        let kind:HarvestOutcome.Kind = request.op == "ore" ? .mining : .lumberjacking
                        return ($0.isStatic ? graphic : 0) == request.graphic &&
                            HarvestSitePlanner.accepts(kind:kind,graphic:graphic,isStatic:$0.isStatic)
                    }
                    try respond(Reply(valid ? point : nil)); continue
                }
                if request.op == "tree_site" || request.op == "ore_site" {
                    // Diagnostic/discovery helper; never authorizes harvesting.
                    let zone = try HarvestWorkflow.Zone(x1:max(0,point.x-32),y1:max(0,point.y-32),
                        x2:min(6142,point.x+32),y2:min(4094,point.y+32))
                    let dynamic = objects.map { object -> WorldTile in
                        var tile = WorldTile(x:object.x,y:object.y,z:object.z,art:object.graphic+0x4000,hue:0)
                        tile.isDynamic=true; tile.sourceSerial=object.serial
                        return tile
                    }
                    let plan = try HarvestSitePlanner.discover(assets:assets,zone:zone,kind:request.op == "ore_site" ? .mining : .lumberjacking,start:point,additional:dynamic)
                    let reachMap = try NavigationMap(assets:assets,center:point,additional:dynamic,radius:32)
                    if let site = plan.sites.first(where: {
                        guard abs($0.standing.z-$0.target.z) <= 16 else { return false }
                        let dx = $0.target.x-$0.standing.x, dy = $0.target.y-$0.standing.y
                        return dx == 0 || dy == 0 ||
                            (reachMap.step(from:$0.standing,direction:dx > 0 ? 2 : 6) != nil &&
                             reachMap.step(from:$0.standing,direction:dy > 0 ? 4 : 0) != nil)
                    }) {
                        var reply = Reply(site.standing)
                        reply.target = Target(x:site.target.x,y:site.target.y,z:site.target.z,graphic:site.target.graphic)
                        try respond(reply)
                    } else { try respond(Reply(nil)) }
                    continue
                }
                if request.op == "near_forge" {
                    let tiles = try assets.region(x:point.x,y:point.y,radius:2)
                    if let tile = tiles.filter({ $0.isStatic && !$0.isDynamic &&
                        abs($0.z-point.z)<=16 && SmeltOutcome.isForge($0.art-0x4000)
                    }).sorted(by:{ ($0.x,$0.y,$0.z,$0.art)<($1.x,$1.y,$1.z,$1.art) }).first {
                        var reply = Reply(WalkPoint(x:tile.x,y:tile.y,z:tile.z))
                        reply.target = Target(x:tile.x,y:tile.y,z:tile.z,graphic:tile.art-0x4000)
                        try respond(reply)
                    } else { try respond(Reply(nil)) }
                    continue
                }
                let navigation = try map(point)
                let result: WalkPoint?
                switch request.op {
                case "stand": result = navigation.standingPoint(x: point.x, y: point.y, fromZ: point.z)
                case "settle":
                    // Recover old flat-sandbox saves that stopped inside an obstacle.
                    // Prefer the same tile; otherwise choose nearest safe tile within 8.
                    var found = navigation.standingPoint(x: point.x, y: point.y, fromZ: point.z)
                    if found == nil {
                        for radius in 1...8 {
                            for dy in -radius...radius {
                                for dx in -radius...radius where max(abs(dx),abs(dy)) == radius {
                                    if found == nil {
                                        found = navigation.standingPoint(x: point.x+dx, y: point.y+dy, fromZ: point.z)
                                    }
                                }
                            }
                            if found != nil { break }
                        }
                    }
                    result = found
                case "step":
                    guard let direction = request.direction, direction >= 0, direction & ~0x87 == 0 else {
                        throw AssetError("Invalid direction")
                    }
                    result = navigation.step(from: point, direction: UInt8(direction))
                default: throw AssetError("Unknown operation")
                }
                // The legacy protocol and persisted avatar use signed 8-bit Z.
                try respond(Reply(result.flatMap { (-128...127).contains($0.z) ? $0 : nil }))
            } catch {
                try respond(Reply(error: "Navigation request failed"))
            }
        }
    }
}
