#!/usr/bin/env python3
"""Inventory local UO assets or an installer without executing the installer."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def audit(path, hashes=False):
    if path.is_file():
        tar = shutil.which("bsdtar")
        if not tar:
            raise ValueError("Installer inspection requires bsdtar (libarchive).")
        result = subprocess.run([tar, "-tf", str(path.resolve())],
                                capture_output=True, text=True, check=True)
        names = result.stdout.splitlines()
        assets = [n for n in names if Path(n).suffix.lower() in (".mul", ".uop", ".idx")]
        return {"source": str(path), "kind": "archive", "size_bytes": path.stat().st_size,
                "sha256": digest(path), "entry_count": len(names), "asset_entries": assets,
                "status": "contains_asset_entries" if assets else "no_game_assets",
                "note": "Archive listing only; nested archives are not inspected. Filename is not a verified client version."}
    if not path.is_dir():
        raise ValueError(f"Not a file or directory: {path}")
    files = sorted(p for p in path.rglob("*") if p.is_file()
                   and p.suffix.lower() in (".mul", ".uop", ".idx", ".exe"))
    names = {p.name.lower() for p in files if p.stat().st_size > 0}
    requirements = {
        "map0": [("map0.mul",), ("map0legacymul.uop",)],
        "art": [("art.mul", "artidx.mul"), ("artlegacymul.uop",)],
        "statics0": [("statics0.mul", "staidx0.mul")],
        "tiledata": [("tiledata.mul",)],
    }
    missing = [key for key, choices in requirements.items()
               if not any(all(name in names for name in choice) for choice in choices)]
    inventory = []
    for item in files:
        entry = {"path": str(item.relative_to(path)), "size_bytes": item.stat().st_size}
        if hashes:
            entry["sha256"] = digest(item)
        inventory.append(entry)
    markers = {}
    for item in path.iterdir():
        if item.is_file() and item.name.lower() in ("version.txt", "readme.md"):
            markers[item.name] = {"text": item.read_text(errors="replace"), "sha256": digest(item)}
    return {"source": str(path), "kind": "directory", "files": inventory,
            "version_evidence": markers,
            "missing_for_first_terrain_milestone": missing,
            "status": "missing_assets" if missing else "candidate_assets_present",
            "note": "Presence check only, not format or version validation. Hash a frozen installation; keep original paths."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--hash", action="store_true", help="SHA-256 each client file (may take time)")
    args = parser.parse_args()
    try:
        report = audit(args.source, args.hash)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Asset audit failed: {error}", file=sys.stderr)
        return 2
    print(json.dumps(report, indent=2))
    return 1 if report["status"] in ("no_game_assets", "missing_assets") else 0


if __name__ == "__main__":
    sys.exit(main())
