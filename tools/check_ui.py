#!/usr/bin/env python3
"""Build and run existing AppKit fixtures without connecting a game client.

Swift owns the client and checks; Python only assembles and invokes the tools.
Generated source/executable/screenshots stay under ignored build/.
"""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = [
    "check_login_flow", "check_login_profiles", "check_classic_ui",
    "check_character_creation", "check_vendor_panel", "check_spellbook", "check_graphic_effects",
    "check_journal", "check_death_panel", "check_shortcut_layout", "check_arrival_invalidation", "check_telemetry_rotation", "check_container_interactions", "check_mobile_route_recovery", "check_gathered_banking", "check_entry_alignment", "check_travel_interactions", "check_harvest_panel", "check_auto_harvest", "check_herding", "check_server_menu", "check_server_gump",
]


def main():
    subprocess.run(["python3", "tools/check_font_policy.py"], cwd=ROOT, check=True)
    subprocess.run([
        "swift", "build", "-c", "release", "--cache-path", "build/swift-cache",
        "--scratch-path", ".build",
    ], cwd=ROOT, check=True)
    chunks = []
    for index, name in enumerate(FIXTURES):
        source = (ROOT / "tools" / (name + ".swift")).read_text()
        source, count = re.subn(r"@main\s+struct\s+\w+", "struct UIFixture" + str(index), source, count=1)
        if count != 1:
            raise RuntimeError(f"Expected one entry point in {name}")
        chunks.append(source)
    calls = "\n".join(
        f'print("Checking {name}"); try UIFixture{index}.main()'
        for index, name in enumerate(FIXTURES)
    )
    chunks.append("@main struct UIRegression { @MainActor static func main() throws {\n" + calls + '\nprint("All offline UI fixtures passed")\n} }')
    generated = ROOT / "build/UIFixtures.swift"
    generated.write_text("\n".join(chunks))
    binary = ROOT / "build/check_ui"
    release = ROOT / ".build/release"
    sources = sorted(p for p in (ROOT / "Sources/UltimaMac").glob("*.swift") if p.name != "main.swift")
    objects = sorted((release / "UOCore.build").glob("*.o"))
    if not objects:
        raise RuntimeError("Release core objects missing")
    subprocess.run([
        "swiftc", "-parse-as-library", "-I", str(release / "Modules"),
        str(generated), *map(str, sources), *map(str, objects), "-o", str(binary),
    ], cwd=ROOT, check=True)
    # The second pass exercises the vendor sell parchment as well as buy mode.
    for args in [[], ["--sell"]]:
        subprocess.run([str(binary), *args], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
