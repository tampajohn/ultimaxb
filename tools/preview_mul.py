#!/usr/bin/env python3
"""Render a bounded legacy MUL region to BMP. Host decoder experiment, not a game renderer.

Format references: ClassicUO.Assets ArtLoader.cs, MapLoader.cs, UOFileManager.cs
at https://github.com/ClassicUO/ClassicUO/tree/main/src/ClassicUO.Assets.
Independent implementation using the documented binary layouts.
"""
import argparse
from contextlib import ExitStack
from functools import lru_cache
import json
import mmap
from pathlib import Path
import struct
import sys


def span(data, offset, length):
    if offset < 0 or length < 0 or offset + length > len(data):
        raise ValueError(f"Truncated record: offset={offset}, length={length}, file={len(data)}")
    return data[offset:offset + length]


def color(value):
    return tuple(((value >> shift) & 31) * 255 // 31 for shift in (10, 5, 0))


def land_art(raw):
    span(raw, 0, 2024)
    pixels = [None] * (44 * 44)
    offset = 0
    for y in range(44):
        half = min(y + 1, 44 - y)
        for x in range(22 - half, 22 + half):
            pixels[y * 44 + x] = color(struct.unpack_from("<H", raw, offset)[0])
            offset += 2
    return 44, 44, pixels


def static_art(raw):
    span(raw, 0, 8)
    width, height = struct.unpack_from("<HH", raw, 4)
    if not (0 < width <= 1024 and 0 < height <= 1024):
        raise ValueError(f"Invalid static dimensions {width}x{height}")
    table = span(raw, 8, height * 2)
    pixels = [None] * (width * height)
    for y in range(height):
        pos = 8 + height * 2 + struct.unpack_from("<H", table, y * 2)[0] * 2
        x = 0
        while True:
            skip, count = struct.unpack("<HH", span(raw, pos, 4))
            pos += 4
            if skip == count == 0:
                break
            x += skip
            if x + count > width:
                raise ValueError("Static run extends beyond row")
            run = span(raw, pos, count * 2)
            for i in range(count):
                value = struct.unpack_from("<H", run, i * 2)[0]
                if value:
                    pixels[y * width + x + i] = color(value)
            pos += count * 2
            x += count
    return width, height, pixels


class Client:
    def __init__(self, directory, stack):
        files = {p.name.lower(): p for p in directory.iterdir() if p.is_file()}
        self.files = {}
        for name in ("map0.mul", "art.mul", "artidx.mul", "statics0.mul", "staidx0.mul", "verdata.mul"):
            if name == "verdata.mul" and name not in files:
                continue
            if name not in files:
                raise ValueError(f"Missing {name}")
            stream = stack.enter_context(files[name].open("rb"))
            self.files[name] = stack.enter_context(mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ))
        size = len(self.files["map0.mul"])
        if size not in (6144 * 4096 // 64 * 196, 7168 * 4096 // 64 * 196):
            raise ValueError(f"Unsupported map0 size: {size}; expected classic 6144/7168 x 4096")
        self.width, self.height = size // 196 // 512 * 8, 4096
        if len(self.files["staidx0.mul"]) != size // 196 * 12:
            raise ValueError("Static index size does not match map dimensions")
        self.patches = {}
        if "verdata.mul" in self.files:
            data = self.files["verdata.mul"]
            count, = struct.unpack("<I", span(data, 0, 4))
            records = span(data, 4, count * 20)
            for file_id, block, offset, length, extra in struct.iter_unpack("<5I", records):
                span(data, offset, length)
                self.patches[file_id, block] = offset, length
            # Other patches affect fonts/gumps/tile metadata, unused by this preview.
            if any(file_id in (0, 1, 2) for file_id, _ in self.patches):
                raise ValueError("Map/static VERDATA patches are not supported by this preview")

    @lru_cache(maxsize=256)
    def art(self, index):
        if (4, index) in self.patches:
            offset, length = self.patches[4, index]
            raw = span(self.files["verdata.mul"], offset, length)
        else:
            offset, length, _ = struct.unpack("<III", span(self.files["artidx.mul"], index * 12, 12))
            if offset == 0xFFFFFFFF or length in (0, 0xFFFFFFFF):
                return None
            raw = span(self.files["art.mul"], offset, length)
        return land_art(raw) if index < 0x4000 else static_art(raw)

    def region(self, cx, cy, radius):
        x0, x1 = max(0, cx - radius), min(self.width, cx + radius + 1)
        y0, y1 = max(0, cy - radius), min(self.height, cy + radius + 1)
        entries = []
        for bx in range(x0 // 8, (x1 - 1) // 8 + 1):
            for by in range(y0 // 8, (y1 - 1) // 8 + 1):
                block = bx * (self.height // 8) + by
                land = span(self.files["map0.mul"], block * 196 + 4, 192)
                for i, (tile, z) in enumerate(struct.iter_unpack("<Hb", land)):
                    x, y = bx * 8 + i % 8, by * 8 + i // 8
                    if x0 <= x < x1 and y0 <= y < y1:
                        entries.append((x, y, z, tile & 0x3FFF, 0))
                offset, length, _ = struct.unpack("<III", span(self.files["staidx0.mul"], block * 12, 12))
                if offset == 0xFFFFFFFF or length in (0, 0xFFFFFFFF):
                    continue
                if length % 7:
                    raise ValueError("Static block length is not a multiple of seven")
                for tile, dx, dy, z, hue in struct.iter_unpack("<HBBbH", span(self.files["statics0.mul"], offset, length)):
                    if dx >= 8 or dy >= 8:
                        raise ValueError("Static coordinate outside its 8x8 block")
                    x, y = bx * 8 + dx, by * 8 + dy
                    if x0 <= x < x1 and y0 <= y < y1:
                        entries.append((x, y, z, tile + 0x4000, hue))
        return sorted(entries, key=lambda e: (e[0] + e[1], e[2], e[3] >= 0x4000, e[0]))


def write_bmp(path, width, height, pixels):
    stride = (width * 3 + 3) & ~3
    size = stride * height
    with path.open("wb") as stream:
        stream.write(struct.pack("<2sIHHI", b"BM", 54 + size, 0, 0, 54))
        stream.write(struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0, size, 0, 0, 0, 0))
        for y in reversed(range(height)):
            row = pixels[y * width * 3:(y + 1) * width * 3]
            bgr = bytearray(len(row))
            bgr[0::3], bgr[1::3], bgr[2::3] = row[2::3], row[1::3], row[0::3]
            stream.write(bgr)
            stream.write(b"\0" * (stride - len(row)))


def render(client, output, cx, cy, radius, statics=True):
    width, height = 960, 720
    pixels = bytearray((16, 22, 27)) * (width * height)
    missing, land_count, static_count, hued = set(), 0, 0, 0
    for x, y, z, index, hue in client.region(cx, cy, radius):
        is_static = index >= 0x4000
        if is_static and not statics:
            continue
        art = client.art(index)
        if art is None:
            missing.add(index)
            continue
        w, h, sprite = art
        sx = width // 2 + ((x - cx) - (y - cy)) * 22 - w // 2
        sy = height // 2 + ((x - cx) + (y - cy)) * 22 - z * 4 + 44 - h
        if sx >= width or sy >= height or sx + w <= 0 or sy + h <= 0:
            continue
        land_count += not is_static
        static_count += is_static
        hued += bool(hue)
        for yy in range(max(0, -sy), min(h, height - sy)):
            for xx in range(max(0, -sx), min(w, width - sx)):
                rgb = sprite[yy * w + xx]
                if rgb is not None:
                    pos = ((sy + yy) * width + sx + xx) * 3
                    pixels[pos:pos + 3] = bytes(rgb)
    output.parent.mkdir(parents=True, exist_ok=True)
    write_bmp(output, width, height, pixels)
    return {"output": str(output), "map_size": [client.width, client.height], "center": [cx, cy],
            "land_sprites": land_count, "static_sprites": static_count, "hued_sprites_unapplied": hued,
            "missing_art_indices": sorted(missing), "verdata_art_overrides": sum(k[0] == 4 for k in client.patches),
            "limitations": ["Flat land diamonds at tile elevation; no slope texturing", "Approximate painter order",
                            "No hues, roof hiding, lighting, animation, mobiles or dynamic items"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("client", type=Path)
    parser.add_argument("--output", type=Path, default=Path("build/britain.bmp"))
    parser.add_argument("--x", type=int, default=1435)
    parser.add_argument("--y", type=int, default=1695)
    parser.add_argument("--radius", type=int, default=24)
    parser.add_argument("--land-only", action="store_true")
    args = parser.parse_args()
    try:
        with ExitStack() as stack:
            client = Client(args.client, stack)
            if not (0 <= args.x < client.width and 0 <= args.y < client.height and 1 <= args.radius <= 64):
                raise ValueError("Center must be on map and radius must be 1..64")
            report = render(client, args.output, args.x, args.y, args.radius, not args.land_only)
        print(json.dumps(report, indent=2))
        args.output.with_suffix(".json").write_text(json.dumps(report, indent=2) + "\n")
        return 0
    except (OSError, ValueError, struct.error) as error:
        print(f"Preview failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
