import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("audit", Path(__file__).parents[1] / "tools/audit_assets.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class AssetAuditTests(unittest.TestCase):
    def test_empty_directory_and_zero_length_assets_are_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "map0.mul").touch()
            report = audit.audit(root)
            self.assertIn("map0", report["missing_for_first_terrain_milestone"])
            self.assertEqual(report["status"], "missing_assets")

    def test_mul_requires_art_index_and_hashes_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("MAP0.MUL", "art.mul", "statics0.mul", "staidx0.mul", "tiledata.mul"):
                (root / name).write_bytes(b"fixture")
            self.assertEqual(audit.audit(root)["missing_for_first_terrain_milestone"], ["art"])
            (root / "artidx.mul").write_bytes(b"fixture")
            report = audit.audit(root, True)
            self.assertEqual(report["status"], "candidate_assets_present")
            self.assertTrue(all(len(item["sha256"]) == 64 for item in report["files"]))

    def test_uop_alternatives(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("map0LegacyMUL.uop", "artLegacyMUL.uop", "statics0.mul", "staidx0.mul", "tiledata.mul"):
                (root / name).write_bytes(b"fixture")
            self.assertEqual(audit.audit(root)["status"], "candidate_assets_present")


if __name__ == "__main__":
    unittest.main()
