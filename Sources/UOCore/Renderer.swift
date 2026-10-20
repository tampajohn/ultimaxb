import Foundation

public struct Frame {
    public let width: Int, height: Int
    public let rgba: [UInt8]
    public let landCount: Int, staticCount: Int, missingCount: Int, huedCount: Int

    public func writeBMP(to url: URL) throws {
        let stride = (width * 3 + 3) & ~3
        var data = Data([0x42, 0x4D])
        func u16(_ n: Int) { data.append(UInt8(n & 255)); data.append(UInt8((n >> 8) & 255)) }
        func u32(_ n: Int) { u16(n & 65535); u16((n >> 16) & 65535) }
        u32(54 + stride * height); u16(0); u16(0); u32(54)
        u32(40); u32(width); u32(height); u16(1); u16(24)
        u32(0); u32(stride * height); u32(0); u32(0); u32(0); u32(0)
        for y in (0..<height).reversed() {
            for x in 0..<width {
                let p = (y * width + x) * 4
                data.append(rgba[p + 2]); data.append(rgba[p + 1]); data.append(rgba[p])
            }
            data.append(contentsOf: repeatElement(UInt8(0), count: stride - width * 3))
        }
        try data.write(to: url, options: .atomic)
    }
}

public struct WorldCamera {
    public let x: Double, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public enum WorldRenderer {
    public static func render(_ assets: ClientAssets, x: Int, y: Int,
                              statics: Bool = true, width: Int = 960, height: Int = 720,
                              legacyTerrain: Bool = false, visibility: WorldVisibility = WorldVisibility(), camera: WorldCamera? = nil, groundItems: [WorldTile] = [], mobiles: [WorldMobile] = [], equipment: [EquippedItem] = [], mobilePresentations: [UInt32: MobilePresentation] = [:], lighting:WorldLighting = WorldLighting(), animationTime:TimeInterval = 0, outlinedMobiles:Set<UInt32> = []) throws -> Frame {
        guard (1...2048).contains(width), (1...2048).contains(height) else {
            throw AssetError("Frame dimensions must be 1...2048")
        }
        let cameraX = camera?.x ?? Double(x), cameraY = camera?.y ?? Double(y)
        let offsetX = Int((((Double(x) - cameraX) - (Double(y) - cameraY)) * 22).rounded())
        let offsetY = Int((((Double(x) - cameraX) + (Double(y) - cameraY)) * 22).rounded())
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for p in stride(from: 0, to: pixels.count, by: 4) {
            pixels[p] = 16; pixels[p + 1] = 22; pixels[p + 2] = 27; pixels[p + 3] = 255
        }
        let ambient = UInt16((lighting.brightness*255).rounded())
        var illumination = ambient<255 ? [UInt16](repeating:ambient,count:width*height) : []
        var lightCount = 0
        var masks:[Int:LightMask] = [:]
        var lightOcclusion: LightOcclusion?
        func addLight(graphic:Int,atX:Int,atY:Int,worldX:Int,worldY:Int,worldZ:Int,lightID:Int? = nil) throws {
            guard !illumination.isEmpty,lightCount<100,let id = try assets.lightIndex(graphic:graphic,override:lightID) else { return }
            guard lightOcclusion?.blocks(x: worldX, y: worldY, z: worldZ) != true else { return }
            let mask:LightMask
            if let cached = masks[id] { mask = cached }
            else if let loaded = try assets.lights?.mask(id) { mask = loaded; masks[id] = loaded }
            else { return }
            let sx = atX-mask.width/2,sy = atY-mask.height/2
            let left = max(0,-sx),right = min(mask.width,width-sx),top = max(0,-sy),bottom = min(mask.height,height-sy)
            guard left<right,top<bottom else { return }
            lightCount += 1
            for yy in top..<bottom {
                for xx in left..<right {
                    let dest = (sy+yy)*width+sx+xx
                    illumination[dest] = min(255,illumination[dest]+UInt16(mask.intensity[yy*mask.width+xx]))
                }
            }
        }
        var land = 0, items = 0, missing = Set<Int>(), hued = 0
        let radius = min(64, max(24, (width + height) / 88 + 5))
        var tiles = try assets.region(x: x, y: y, radius: radius, legacyOrder: legacyTerrain)
        let visibleItems = groundItems.filter { abs($0.x - x) <= radius && abs($0.y - y) <= radius }
        if !visibleItems.isEmpty {
            tiles += visibleItems
            let entries = try tiles.enumerated().map {
                DrawEntry(tile: $0.element, priority: try assets.drawPriority($0.element), originalIndex: $0.offset)
            }
            tiles = entries.sorted(by: DrawEntry.precedes).map(\.tile)
        }
        if !illumination.isEmpty && statics {
            lightOcclusion = try LightOcclusion(tiles: tiles, visibility: visibility) { graphic in
                try !assets.isNoDraw(graphic: graphic) && assets.itemFlags(graphic: graphic) & 0x04 == 0
            }
        }
        var entries = try tiles.enumerated().map {
            DrawEntry(tile: $0.element, priority: try assets.drawPriority($0.element), originalIndex: $0.offset)
        }
        var mobileByIndex: [Int: WorldMobile] = [:]
        for mobile in mobiles where abs(mobile.x - x) <= radius && abs(mobile.y - y) <= radius {
            let index = entries.count
            mobileByIndex[index] = mobile
            entries.append(DrawEntry.mobile(mobile, presentation: mobilePresentations[mobile.serial], index: index))
        }
        if !mobileByIndex.isEmpty { entries.sort(by: DrawEntry.precedes) }
        for entry in entries {
            let tile = entry.tile
            let mobile = mobileByIndex[entry.originalIndex]
            if mobile == nil && (tile.isStatic ? visibility.hides(z: tile.z, x: tile.x, y: tile.y) : visibility.hidesTerrain(z: tile.z, x: tile.x, y: tile.y)) { continue }
            if mobile == nil && tile.isStatic {
                if !statics { continue }
                if tile.corpseBody == nil && tile.effectAge == nil, try assets.isNoDraw(graphic:tile.art-0x4000) { continue }
            }
            if !tile.isStatic && !legacyTerrain {
                if tile.art <= 2 { continue } // Invisible land markers, including NODRAW.
                let z = try [tile.z, assets.elevation(x: tile.x + 1, y: tile.y),
                             assets.elevation(x: tile.x + 1, y: tile.y + 1),
                             assets.elevation(x: tile.x, y: tile.y + 1)]
                if visibility.hidesTerrain(z: z.max()!, x: tile.x, y: tile.y) { continue }
                if z.contains(where: { $0 != z[0] }), let texture = try assets.terrainTexture(land: tile.art) {
                    let screenX = width / 2 + offsetX + ((tile.x - x) - (tile.y - y)) * 22
                    let screenY = height / 2 + offsetY + ((tile.x - x) + (tile.y - y)) * 22
                    if screenX + 22 >= 0 && screenX - 22 < width &&
                        screenY + 44 - z.min()! * 4 >= 0 && screenY - z.max()! * 4 < height {
                        TerrainRasterizer.draw(texture: texture, screenX: screenX, screenY: screenY,
                                               z: z, width: width, height: height, pixels: &pixels)
                        land += 1
                    }
                    continue
                }
            }
            let sprite: Sprite
            let sx: Int, sy: Int
            var mirrored = false
            var anchorX = width / 2 + offsetX + ((tile.x - x) - (tile.y - y)) * 22
            var anchorY = height / 2 + offsetY + ((tile.x - x) + (tile.y - y)) * 22 - tile.z * 4
            if let pose = tile.effectPose {
                anchorX = Int((Double(width/2) + ((pose.x-cameraX)-(pose.y-cameraY))*22).rounded())
                anchorY = Int((Double(height/2) + ((pose.x-cameraX)+(pose.y-cameraY))*22-pose.z*4).rounded())
            }
            if let mobile {
                let presentation = mobilePresentations[mobile.serial]
                let px = presentation?.x ?? Double(mobile.x)
                let py = presentation?.y ?? Double(mobile.y)
                let pz = presentation?.z ?? Double(mobile.z)
                let screenX = Double(width / 2) + ((px - cameraX) - (py - cameraY)) * 22
                let screenY = Double(height / 2) + ((px - cameraX) + (py - cameraY)) * 22 - pz * 4
                let mobileAction = try MobileAnimation.action(for:mobile,pose:presentation,equipment:equipment,assets:assets)
                let outlined = outlinedMobiles.contains(mobile.serial)
                var silhouette = Set<Int>()
                func drawAnimation(_ body: Int, hue: Int, art: Int? = nil) throws {
                    guard let frame = try assets.animations?.frame(body: body, direction: mobile.direction,
                        action: mobileAction, frame: presentation?.frame ?? 0) else {
                        missing.insert(-body - 1); return
                    }
                    let sprite = frame.sprite
                    let sx = Int(screenX.rounded()) - (frame.mirrored ? sprite.width - frame.centerX : frame.centerX)
                    let sy = Int(screenY.rounded()) + 22 - sprite.height - frame.centerY
                    // Classic clients tint visible hidden mobiles and all worn
                    // layers with the full hidden hue, regardless of item hues.
                    let hidden = mobile.flags & 0x80 != 0
                    let palette = try assets.huePalette(hidden ? 0x038E : hue, art: hidden ? nil : art)
                    let left = max(0, -sx), right = min(sprite.width, width - sx)
                    let top = max(0, -sy), bottom = min(sprite.height, height - sy)
                    guard left < right, top < bottom else { return }
                    if hue & 0x3FFF != 0 && palette == nil { hued += 1 }
                    for yy in top..<bottom {
                        for xx in left..<right {
                            let src = (yy * sprite.width + (frame.mirrored ? sprite.width - 1 - xx : xx)) * 4
                            if sprite.rgba[src + 3] == 0 { continue }
                            let dest = ((sy + yy) * width + sx + xx) * 4
                            if outlined { silhouette.insert(dest/4) }
                            let r = sprite.rgba[src], g = sprite.rgba[src + 1], b = sprite.rgba[src + 2]
                            let color = palette?.color(red: r, green: g, blue: b) ?? (r, g, b)
                            pixels[dest] = color.0; pixels[dest + 1] = color.1; pixels[dest + 2] = color.2
                        }
                    }
                }
                try drawAnimation(mobile.body, hue: mobile.hue)
                if mobile.body == 400 || mobile.body == 401 {
                    for item in EquipmentOrder.sorted(equipment.filter { $0.owner == mobile.serial }, direction: mobile.direction) {
                        if let animation = try assets.equipmentAnimation(graphic: item.graphic) {
                            try drawAnimation(animation, hue: item.hue, art: item.graphic + 0x4000)
                        }
                    }
                }
                if outlined {
                    for pixel in silhouette {
                        let x = pixel % width, y = pixel / width
                        for (dx,dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
                            let nx=x+dx, ny=y+dy
                            guard nx>=0,nx<width,ny>=0,ny<height else { continue }
                            let neighbor=ny*width+nx
                            if !silhouette.contains(neighbor) {
                                pixels[neighbor*4]=255; pixels[neighbor*4+1]=45; pixels[neighbor*4+2]=45
                            }
                        }
                    }
                }
                // Use the same interpolated world position as the mobile, so carried
                // illumination does not jump ahead to its next server tile.
                for item in equipment where item.owner == mobile.serial {
                    try addLight(graphic:item.graphic,atX:Int(screenX.rounded()),atY:Int(screenY.rounded())+22,worldX:mobile.x,worldY:mobile.y,worldZ:mobile.z)
                }
                items += 1
                continue
            } else if let gump = tile.effectGump {
                guard let art = try assets.gumps?.sprite(gump) else { missing.insert(-0x10000-gump); continue }
                sprite = art
                sx = anchorX - sprite.width/2
                sy = anchorY + 22 + tile.effectYOffset - sprite.height
            } else if let age = tile.effectAge {
                // Graphic effects use the same signed frame offsets as scenery, at 45 ms units.
                let graphic = assets.staticAnimations?.graphic(tile.art-0x4000, at:tile.effectFrameInterval == nil ? age * (0.08/0.045) : age, frameInterval:tile.effectFrameInterval) ?? tile.art-0x4000
                guard let art = try assets.sprite(graphic+0x4000) else { missing.insert(graphic+0x4000); continue }
                if let angle = tile.effectRotation {
                    let rotated = EffectRotation.rotate(art, radians:angle)
                    sprite = rotated.sprite
                    sx = anchorX + rotated.x
                    sy = anchorY + 22 - art.height + rotated.y
                } else {
                    sprite = art
                    sx = anchorX - sprite.width/2
                    sy = anchorY + 44 - sprite.height
                }
            } else if let body = tile.corpseBody, let corpse = try CorpseArt.frame(body:body,direction:tile.corpseDirection,assets:assets,hue:tile.hue,equipment:tile.corpseEquipment) {
                sprite = corpse.sprite; mirrored = corpse.mirrored
                sx = anchorX - (mirrored ? sprite.width-corpse.centerX : corpse.centerX)
                sy = anchorY + 22 - sprite.height - corpse.centerY
            } else {
                guard let art = try assets.worldSprite(tile.art,at:animationTime) else { missing.insert(tile.art); continue }
                sprite = art
                sx = anchorX - sprite.width / 2
                sy = anchorY + 44 - sprite.height
            }
            if tile.isStatic && tile.effectGump == nil { try addLight(graphic:tile.art-0x4000,atX:anchorX,atY:anchorY+22,worldX:tile.x,worldY:tile.y,worldZ:tile.z,lightID:tile.lightID) }
            let left = max(0, -sx), right = min(sprite.width, width - sx)
            let top = max(0, -sy), bottom = min(sprite.height, height - sy)
            if left >= right || top >= bottom { continue }
            if tile.isStatic { items += 1 } else { land += 1 }
            let hue = try assets.huePalette(tile.corpseBody == nil ? tile.hue : 0, art: mobile == nil ? tile.art : nil)
            if tile.hue & 0x3FFF != 0 && hue == nil { hued += 1 }
            for yy in top..<bottom {
                for xx in left..<right {
                    let source = (yy * sprite.width + (mirrored ? sprite.width-1-xx : xx)) * 4
                    if sprite.rgba[source + 3] == 0 { continue }
                    let dest = ((sy + yy) * width + sx + xx) * 4
                    let r = sprite.rgba[source], g = sprite.rgba[source + 1], b = sprite.rgba[source + 2]
                    let color = hue?.color(red: r, green: g, blue: b) ?? (r, g, b)
                    if tile.effectAge != nil {
                        let alpha = sprite.rgba[source + 3]
                        pixels[dest] = EffectBlend.channel(source:color.0,destination:pixels[dest],alpha:alpha,mode:tile.effectBlendMode)
                        pixels[dest + 1] = EffectBlend.channel(source:color.1,destination:pixels[dest + 1],alpha:alpha,mode:tile.effectBlendMode)
                        pixels[dest + 2] = EffectBlend.channel(source:color.2,destination:pixels[dest + 2],alpha:alpha,mode:tile.effectBlendMode)
                    } else {
                        pixels[dest] = color.0
                        pixels[dest + 1] = color.1
                        pixels[dest + 2] = color.2
                    }
                }
            }
        }
        if !illumination.isEmpty {
            for i in 0..<width*height {
                for c in 0..<3 { pixels[i*4+c] = UInt8(UInt16(pixels[i*4+c])*illumination[i]/255) }
            }
        }
        return Frame(width: width, height: height, rgba: pixels, landCount: land,
                     staticCount: items, missingCount: missing.count, huedCount: hued)
    }
}
