import Foundation

public enum WorldHitTest {
    /// Front-to-back alpha hit test using the same static-art anchor as the renderer.
    public static func groundItem(assets: ClientAssets, items: [GroundItem], camera: WorldCamera,
                                  screenX: Double, screenY: Double, width: Int = 960, height: Int = 720) throws -> GroundItem? {
        let visible = items.filter { $0.graphic < 0x4000 && $0.flags & 0x80 == 0 }
        let entries = try visible.enumerated().map { pair in
            let item = pair.element
            let tile = WorldTile(x: item.x, y: item.y, z: item.z, art: item.graphic + 0x4000, hue: item.hue)
            return DrawEntry(tile: tile, priority: try assets.drawPriority(tile), originalIndex: pair.offset)
        }.sorted(by: DrawEntry.precedes)
        for entry in entries.reversed() {
            let item = visible[entry.originalIndex]
            guard try !assets.isNoDraw(graphic:item.graphic), let sprite = try assets.sprite(item.graphic + 0x4000) else { continue }
            let ax = Double(width / 2) + ((Double(item.x) - camera.x) - (Double(item.y) - camera.y)) * 22
            let ay = Double(height / 2) + ((Double(item.x) - camera.x) + (Double(item.y) - camera.y)) * 22 - Double(item.z * 4)
            let x = Int(floor(screenX - (ax.rounded() - Double(sprite.width / 2))))
            let y = Int(floor(screenY - (ay.rounded() + 44 - Double(sprite.height))))
            if x >= 0, y >= 0, x < sprite.width, y < sprite.height,
               sprite.rgba[(y * sprite.width + x) * 4 + 3] != 0 { return item }
        }
        return nil
    }
    public static func mobile(assets: ClientAssets, mobiles: [WorldMobile], presentations: [UInt32: MobilePresentation], camera: WorldCamera,
                              screenX: Double, screenY: Double, equipment:[EquippedItem] = []) throws -> WorldMobile? {
        let sorted = mobiles.enumerated().map { DrawEntry.mobile($0.element, presentation: presentations[$0.element.serial], index: $0.offset) }.sorted(by: DrawEntry.precedes)
        for entry in sorted.reversed() {
            let mobile = mobiles[entry.originalIndex], pose = presentations[mobiles[entry.originalIndex].serial]
            let action = try MobileAnimation.action(for:mobile,pose:pose,equipment:equipment,assets:assets)
            guard let frame = try assets.animations?.frame(body: mobile.body, direction: mobile.direction, action: action, frame: pose?.frame ?? 0) else { continue }
            let px = pose?.x ?? Double(mobile.x), py = pose?.y ?? Double(mobile.y), pz = pose?.z ?? Double(mobile.z)
            let ax = (480 + ((px-camera.x)-(py-camera.y))*22).rounded()
            let ay = (360 + ((px-camera.x)+(py-camera.y))*22-pz*4).rounded()
            let sprite = frame.sprite
            let sx = ax - Double(frame.mirrored ? sprite.width - frame.centerX : frame.centerX)
            let sy = ay + 22 - Double(sprite.height + frame.centerY)
            let x = Int(floor(screenX-sx)), y = Int(floor(screenY-sy))
            if x >= 0, y >= 0, x < sprite.width, y < sprite.height,
               sprite.rgba[(y*sprite.width + (frame.mirrored ? sprite.width-1-x : x))*4+3] != 0 { return mobile }
        }
        return nil
    }
    public static func location(assets: ClientAssets, camera: WorldCamera, screenX: Double, screenY: Double, visibility: WorldVisibility) throws -> TargetSelection? {
        let tiles = try assets.region(x: Int(camera.x), y: Int(camera.y), radius: 24)
        for tile in tiles.reversed() {
            let ax = 480 + ((Double(tile.x)-camera.x)-(Double(tile.y)-camera.y))*22
            let ay = 360 + ((Double(tile.x)-camera.x)+(Double(tile.y)-camera.y))*22
            if tile.isStatic {
                if try assets.isNoDraw(graphic:tile.art-0x4000) { continue }
                if visibility.hides(z: tile.z, x: tile.x, y: tile.y) { continue }
                guard let sprite = try assets.sprite(tile.art) else { continue }
                let x = Int(floor(screenX - (ax.rounded() - Double(sprite.width/2))))
                let y = Int(floor(screenY - (ay.rounded() - Double(tile.z*4) + 44 - Double(sprite.height))))
                if x >= 0, y >= 0, x < sprite.width, y < sprite.height, sprite.rgba[(y*sprite.width+x)*4+3] != 0 {
                    return TargetSelection(x: tile.x, y: tile.y, z: tile.z, graphic: tile.art-0x4000)
                }
            } else {
                if tile.art <= 2 { continue }
                let z = try [tile.z, assets.elevation(x: tile.x+1, y: tile.y), assets.elevation(x: tile.x+1, y: tile.y+1), assets.elevation(x: tile.x, y: tile.y+1)]
                if visibility.hidesTerrain(z: z.max()!, x: tile.x, y: tile.y) { continue }
                let points = [(ax,ay-Double(z[0]*4)),(ax+22,ay+22-Double(z[1]*4)),(ax,ay+44-Double(z[2]*4)),(ax-22,ay+22-Double(z[3]*4))]
                func triangle(_ a: Int, _ b: Int, _ c: Int) -> Bool {
                    func side(_ i: Int, _ j: Int) -> Double { (screenX-points[j].0)*(points[i].1-points[j].1)-(points[i].0-points[j].0)*(screenY-points[j].1) }
                    let area = (points[b].0-points[a].0)*(points[c].1-points[a].1)-(points[b].1-points[a].1)*(points[c].0-points[a].0)
                    guard abs(area) > 0.000001 else { return false }
                    let sides = [side(a,b),side(b,c),side(c,a)]
                    return !sides.contains(where: { $0 < 0 }) || !sides.contains(where: { $0 > 0 })
                }
                let inside = abs(z[0]-z[2]) <= abs(z[1]-z[3])
                    ? triangle(0,1,2) || triangle(0,2,3) : triangle(0,1,3) || triangle(1,2,3)
                if inside {
                    let average = abs(z[0]-z[2]) <= abs(z[1]-z[3]) ? (z[0]+z[2]) >> 1 : (z[1]+z[3]) >> 1
                    return TargetSelection(x: tile.x, y: tile.y, z: average, graphic: 0)
                }
            }
        }
        return nil
    }

}

public enum WorldInteraction {
    public static func facingItem(player: WorldMobile, items: [GroundItem], assets: ClientAssets) throws -> GroundItem? {
        let delta = [(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1)][Int(player.direction & 7)]
        let candidates = try items.filter {
            $0.x == player.x + delta.0 && $0.y == player.y + delta.1 && abs($0.z - player.z) <= 20 &&
            $0.flags & 0x80 == 0 && $0.graphic < 0x4000
        }.map { (item: $0, door: try assets.isDoor(graphic: $0.graphic)) }
        return candidates.sorted {
            if $0.door != $1.door { return $0.door }
            let a = abs($0.item.z - player.z), b = abs($1.item.z - player.z)
            if a != b { return a < b }
            return $0.item.serial < $1.item.serial
        }.first?.item
    }
}
