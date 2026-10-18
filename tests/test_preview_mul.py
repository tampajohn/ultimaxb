import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("preview", Path(__file__).parents[1] / "tools/preview_mul.py")
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


class DecoderTests(unittest.TestCase):
    def test_land_geometry_and_opaque_black(self):
        w, h, pixels = preview.land_art(struct.pack("<1012H", *([0] * 1012)))
        self.assertEqual((w, h), (44, 44))
        self.assertEqual(sum(p is not None for p in pixels), 1012)
        self.assertEqual(pixels[21], (0, 0, 0))
        self.assertIsNone(pixels[20])
        self.assertEqual(sum(p is not None for p in pixels[21 * 44:22 * 44]), 44)
        with self.assertRaises(ValueError):
            preview.land_art(b"\0" * 2023)

    def test_static_runs_use_relative_skips_and_row_offsets(self):
        # Two rows, with different lookup offsets and zero treated as transparent.
        runs = struct.pack("<8H", 1, 2, 0x7C00, 0, 0, 0, 0, 0)
        raw = struct.pack("<IHHHH", 0, 4, 2, 0, 6) + runs
        w, h, pixels = preview.static_art(raw)
        self.assertEqual((w, h), (4, 2))
        self.assertEqual(pixels, [None, (255, 0, 0), None, None] + [None] * 4)
        with self.assertRaises(ValueError):
            preview.static_art(raw[:-2])

    def test_rejects_static_run_overflow(self):
        raw = struct.pack("<IHHH4H", 0, 1, 1, 0, 1, 1, 0x7FFF, 0)
        with self.assertRaises(ValueError):
            preview.static_art(raw)

    def test_map_column_major_blocks_and_signed_elevation(self):
        client = preview.Client.__new__(preview.Client)
        client.width, client.height = 16, 16
        blocks = []
        for tile in range(4):
            blocks.append(bytes(4) + struct.pack("<Hb", tile, -5) * 64)
        client.files = {"map0.mul": b"".join(blocks), "staidx0.mul":
                        struct.pack("<III", 0xFFFFFFFF, 0, 0) * 4}
        tiles = client.region(8, 0, 0)
        self.assertEqual(tiles, [(8, 0, -5, 2, 0)])

    def test_verdata_art_replaces_base_index(self):
        client = preview.Client.__new__(preview.Client)
        client.patches = {(4, 0): (0, 2024)}
        client.files = {"verdata.mul": struct.pack("<H", 0x03E0) * 1012}
        self.assertEqual(client.art(0)[2][21], (0, 255, 0))
        client.art.cache_clear()

    def test_bmp_padding_and_channel_order(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pixel.bmp"
            preview.write_bmp(path, 1, 1, bytearray((255, 0, 0)))
            data = path.read_bytes()
            self.assertEqual(len(data), 58)
            self.assertEqual(data[54:], bytes((0, 0, 255, 0)))


if __name__ == "__main__":
    unittest.main()
