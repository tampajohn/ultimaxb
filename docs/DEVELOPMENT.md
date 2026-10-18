# Development history

These chronological implementation notes include superseded limitations and local
experiments. See the root README and STATUS.md for the current overview. Paths
under `build/`, `data/`, and `uo1998-client/` refer to ignored local files.

# UltimaXB

A UO client project, starting with **Swift on macOS** and retaining the original
Xbox as a longer-term target. The native macOS viewer now reads the 1998 assets
directly and redraws terrain and statics as you explore. Live UO1998 login, character creation, and world entry have been confirmed
by user testing, including a successful reconnect. This is **not yet a playable
UO client**: complete collision prediction, equipment coverage rules, and most interactions
remain unfinished.

Connected play now reserves a 280-point left sidebar for server-reported health,
stamina, mana, attributes, armor, weight, gold, and a scrollable skills list. K toggles
the skill list; P opens the classic paperdoll, B opens the backpack, and U uses a
held tool (either hand). The map and world pointer calculations share the same
shifted viewport. Unknown status values display a dash until received.

Drag worn equipment from the paperdoll into an open bag to unequip it, or onto
nearby ground to drop it. Backpack items can also be dropped onto nearby ground;
stack quantities remain selectable. Transfers wait for server confirmation.
Server 0x6E action packets now drive finite/repeating mobile animations, including
mining; walking cancels an active action. Live shard verification remains necessary.

The protocol groundwork now includes a 1.25.32 account-login packet codec,
server-list/redirect decoding, and incremental account-phase TCP framing in
`Sources/UOCore/LoginProtocol.swift`. Tests cover every split point of a fixture
stream, coalesced responses, malformed lengths, and credential field validation.
`GameStream.swift` implements incremental Huffman decoding and the 1.25.32 XOR
cipher, with C-generated reference vectors. `GameConnection.swift` adds TCP
login and redirect handling, timeouts, cancellation, and decompressed game data.
Loopback socket tests verify encrypted login, fragmented rejection, server
selection, redirect, cipher reseeding, and receipt of compressed game data.
`GamePackets.swift` frames the 1.25.32 game stream and decodes character lists
and initial world coordinates. Character lists support both count-sized slots
and the historical fixed-five-slot layout observed on UO1998 (empty-account
0xA9 packet: 872 bytes, count byte 0, nine starting cities). Command-L opens a login overlay inside the game window with
secure password entry, server selection, and existing-character selection.
World entry centers the map on the supplied coordinates. Ground-item packets
now populate a serial-keyed world model and render alongside map statics;
deletion, equipment, and container transitions remove ground sprites. This
supports server-supplied signs and doors when received. Full and partial hues
now use `hues.mul` palettes (spectral effects remain unsupported),
and multi-component objects are not expanded. Empty accounts can explicitly
create a basic character in the overlay. It hides on successful world entry;
Back to World dismisses it without disconnecting, and Command-L reopens it.
Disconnect explicitly ends the session. Basic equipped clothing/hair rendering and acknowledged player movement are now
implemented; full armor coverage, collision prediction, and interactions remain unfinished. Unknown packet lengths stop the connection; framed but
unhandled game packets currently have no effect on the viewer.
Adapted OUO code/table notices are retained in `LICENSES/OUO.txt`.

Mobile body updates (0x1B/0x20/0x77/0x78) now render standing frames from
`anim.idx`/`anim.mul` with direction mirroring and sprite anchors. The animation
cache is bounded to 8 MiB in addition to the 16 MiB art/terrain cache. Equipment
lists are retained and classic human equipment is drawn using tiledata animation
IDs and item hues. Special armor coverage and animation VERDATA replacements
remain unfinished. Nearby NPC position updates interpolate over 200 ms
(100 ms when running). Player steps interpolate at their predicted cadence,
retain animation phase across short response gaps, and use running frames; teleports snap immediately.
Idle and server-requested action animations remain unfinished. ClassicUO-derived decoding and
direction mapping notices are retained in `LICENSES/ClassicUO.txt`.

For an offline body preview, add `--preview-body 400` (human male) or
`--preview-body 401` (human female). This places a standing body at the starting
map coordinate; camera panning does not move it. It also works with `--render`.

UO1998 is the current intended server. Its [site](https://uo1998.com/main.shtml)
identifies [OUO](https://github.com/draxinar/ouo) as its server implementation.
OUO's packet handlers and builders provide a reference for the historical wire
formats; this does not establish which upstream revision the live server runs.
OUO lists tested clients from 1.25.30 to 5.0.9.1 and suggests 2.0.7 as a candidate.
The downloaded `client_2.0.7.exe` is a standalone Windows executable (version
string 2.0.7, SHA-256
`4f47c495cf350ecc002bb42635dc7960a157e50a80fc4c41d582f98a7b8a9877`),
not a replacement map/art distribution. Existing assets remain unchanged.

The Second Age disc assets are separately extracted to `data/uo-1.26.0`
(35 files, hashes in `build/iso-client-inventory.json`). The executable identifies
as 1.26.0; the disc version.txt says 1.25.35. A house comparison using these
assets reproduces the roof gap at (1448,1616); that static cell is empty in both
datasets. Use `--client data/uo-1.26.0` to preview the disc assets.

## Swift macOS client

Requires macOS 13+ and a Swift 6 toolchain (tested with Swift 6.3.3 on Apple Silicon).
No external package dependencies. Run from this repository:

```sh
swift run -c release UltimaMac --client uo1998-client
```

Drag the map or use arrows/WASD to pan. Hold Shift with a movement key to move
faster. **T** toggles statics, **R** returns to Britain, and Command-Q quits.
The window shows coordinates, visible sprite counts, render time, and decoded
sprite cache usage. Resizing scales the 960x720 view. Camera motion is tile-based;
it does not move a player. `--x 1435 --y 1695` chooses a starting location.

The Swift package has two modules:

- `UOCore`: bounds-checked legacy asset readers, read-only mapped files, VERDATA
  art overrides, a shared 16 MiB LRU sprite/terrain texture cache, and a CPU renderer.
- `UltimaMac`: an AppKit window, camera controls, status display, and headless export.

Swift decodes and draws individual sprites; it does not call the Python converter
or display its pre-rendered BMP. Total memory includes mapped files, frames, UI,
and cache overhead in addition to the 16 MiB sprite pixel budget. This desktop
implementation does not establish Swift/nxdk compatibility.

To test or export a frame without opening a window:

```sh
swift test
swift run -c release UltimaMac --client uo1998-client --render build/swift-britain.bmp
python3 tools/check_swift_preview.py
```

Create `build/` before exporting if it does not exist. The comparison script uses
`.build/release/UltimaMac` (override with `--binary`) and compares complete BMP
files against the independent Python implementation for Britain with/without
statics and the map corner, using `--legacy-terrain` to retain the original flat
terrain behavior for decoder comparisons. Unit tests cover truncated data, byte order, signed
elevation, block addressing, transparency, row runs, patch precedence, and cache
eviction, terrain textures, shared triangle edges, and invisible land markers.
These checks establish agreement with our earlier decoder, not full
accuracy against the original game.

Sloped terrain now uses the four neighboring map heights and texture IDs from
legacy `TILEDATA.MUL`, with 64x64 or 128x128 textures from `TEXIDX.MUL`/`TEXMAPS.MUL`.
Land IDs 0–2 are hidden markers, so their NODRAW artwork is no longer shown.
Terrain without an available texture falls back to land artwork. Flat terrain
retains the original diamond art. Lighting and more exact terrain/static ordering
are still unfinished; hues, roof hiding, dynamic objects, and server packets also
remain future work. Updated examples: `build/slopes-britain.png` and
`build/slopes-shop.png` (the shop doorway at 1445,1672).

Draw order now keeps each map cell together along the isometric diagonal, then
orders its contents using averaged terrain height and the static tile background
flag/height. Previously sorting all cells by Z first could obscure bridge railings
and interleave wall pieces. `build/bridge-order.png` shows the bridge at (1520,1674).
This is still a painter renderer, not a complete implementation of original-client
occlusion. Inside/outside tracking and roof/wall cutaways are not implemented.

The local Britain statics contain signposts and brackets, but not their shop-sign
panels. Sign panels and doors are server world items; this offline viewer has no
server world-item stream yet. They cannot be recovered by changing static sprite
ordering. No replacement signs or doors have been invented or added to the map.

Known source-data gap: the plaster/slate house around (1452,1616) has no static
records at (1448,1616), where adjacent cells contain slate roof art `0x0597` at
Z=40. A rear window (`0x013B`, at 1447,1615,Z=20) is visible through that opening.
The raw static block is 92874; its index points to byte 5602996, length 469,
and contains no local (0,0) record. No bundled map/static VERDATA override fills
it. `build/house-roof-records.json` records the nearby roofs and
`build/house-before.png` shows the opening. This is an observed gap in this
historical asset set, not a confirmed ordering bug. Whether the shard supplies
a world item there remains unverified. Original data is preserved.

Format/behavior references: ClassicUO's
[land handling](https://github.com/ClassicUO/ClassicUO/blob/main/src/ClassicUO.Client/Game/GameObjects/Land.cs),
[terrain texture loader](https://github.com/ClassicUO/ClassicUO/blob/main/src/ClassicUO.Assets/TexmapsLoader.cs),
and [tile metadata loader](https://github.com/ClassicUO/ClassicUO/blob/main/src/ClassicUO.Assets/TileDataLoader.cs).
Per-cell priority reference:
[ClassicUO Chunk.AddGameObject](https://github.com/ClassicUO/ClassicUO/blob/main/src/ClassicUO.Client/Game/Map/Chunk.cs).

## Local findings

`UOClassicSetup_7_0_24_0.exe` is a roughly 18 MB RAR self-extracting Windows
installer. Its archive contains a patcher, DirectX installers, and help files;
there are no `.mul`, `.uop`, or `.idx` entries. Its `data1/UO-patch.cfg` points to
the legacy EA Mythic patch service. The filename does not pin the version a
patcher would download. No installer code was executed.

The subsequently supplied `uo1998-client/` contains the needed legacy assets and
is excluded from Git in its entirety. `VERSION.TXT` reports **1.25.32**; the
included README describes a 1.25.32 executable with base data from 1.25.34 and
map/statics from 1.25.0. This is a mixed historical dataset, not a verified
unmodified release. `MAP0.MUL` is 77,070,336 bytes, matching 6144x4096 tiles.
The originals are unchanged. File hashes and version evidence are recorded in
`build/client-inventory.json`. That generated report is local and ignored by Git.

These assets are suitable for initial decoding work. They do not establish
compatibility with ModernUO or select our eventual network protocol version.

```sh
python3 tools/audit_assets.py UOClassicSetup_7_0_24_0.exe
python3 tools/audit_assets.py uo1998-client --hash > build/client-inventory.json
```

Create `build/` first, or run the CMake configuration below. Audit exits 1 when
assets are missing, 2 for inspection errors, and 0 when candidates exist. Presence
does not prove valid data, compatible versions, or completeness for the full game.

## Real asset preview

```sh
python3 tools/preview_mul.py uo1998-client
./build/ultimaxb --preview build/britain.bmp
```

The default center is Britain at (1435,1695), with a 49x49-tile input region and
960x720 output. `--x`, `--y`, `--radius`, `--land-only`, and `--output` select
another region or output. A JSON report accompanies each BMP. The initial view
contains 798 visible land sprites and 480 static sprites with no missing art.
`build/britain.png` is a convenient image of the first generated preview.

The converter handles column-major map blocks, signed elevations, 16-bit land
diamonds, static art row runs, case-insensitive filenames, and art overrides from
`VERDATA.MUL` (35 in this dataset). It checks record bounds and rejects unsupported
map/static patch records. Source files are memory-mapped read-only on the host;
the bounded decoded-art cache is a host implementation, not an Xbox memory budget.

This preview uses flat diamonds at each tile's elevation and approximate painter
ordering. Slopes have visible gaps; hues, roof hiding, lighting, animation, mobiles,
and dynamic items are absent. It is not yet compared pixel-for-pixel against a
running reference client. The BMP is a decoding/debug artifact, not the planned
streaming asset format. The Xbox client will need individual cached sprites and
world state rather than a pre-rendered image.

To check image loading without opening a window:

```sh
SDL_VIDEODRIVER=dummy ./build/ultimaxb --preview build/britain.bmp --smoke
```

## Earlier C/SDL2 scaffold

Requires CMake, a C99 compiler, and SDL2 development files.

```sh
cmake -S . -B build
cmake --build build
ctest --test-dir build --output-on-failure
python3 -m unittest discover -s tests -v
./build/ultimaxb
```

Arrow keys or a mapped controller's left stick pan the procedural grid; Escape
quits. `SDL_VIDEODRIVER=dummy ./build/ultimaxb --smoke` renders three frames without
a display. This checks startup/rendering only, not interactive input or Xbox behavior.

## Original Xbox scaffold

Install [nxdk](https://github.com/XboxDev/nxdk) with its recursive submodules and
activate its toolchain per its documentation, then:

```sh
make -C xbox NXDK=/absolute/path/to/nxdk
```

The Makefile shares the desktop source and initializes a 640x480 Xbox display.
The Xbox target has not yet been compiled or tested: nxdk and xemu were not
available on this machine during initial setup. Running the Windows installer
on the Xbox is not the approach; the eventual executable will be a native XBE.
Actual hardware must already be able to run homebrew.

## Playability goal and remaining parity

During user testing, keep exactly one UltimaMac process running. Restart by
replacing the existing instance, preserving assets and saved preferences.

The goal is full playability for the chosen classic era compared with existing
clients, with Swift/macOS first and the original Xbox later. Live UO1998 is the
integration target. Local fixtures and OUO tests precede user testing.

| Area | Current state / remaining work |
| --- | --- |
| Login and reconnect | Live entry and reconnect confirmed; in-window overlay; shard and character lists |
| Saved login | Server/port/account in macOS preferences (`com.ultimaxb.UltimaMac`); optional password in Keychain; Forget Saved Password button |
| Character creation | Basic name/sex/city and fixed starter build; appearance, stats/skills and complete slot management pending |
| World and mobiles | Terrain/statics, dynamic items, bodies, hues, walking/running and basic overhead terrain/roof cutaway; connected-building visibility, equipment coverage, action animations and mounts pending |
| Equipment | Retains 0x78 and 0x2E clothing/hair, follows removal/container transitions; classic human layers rendered |
| Controls | WASD/arrows and combined keys move; Q/E/Z/C other directions; Shift runs with keyboard or right-button hold; Space uses the object ahead; single-click doors; double-click other objects; H/Home recenters; starting movement resumes camera follow; connected panning requires --debug-camera (offline viewer still pans) |
| Movement | Immediate prediction, up to five queued steps, acknowledgements, rejection rollback, idle position/Z synchronization, approximate surface elevation and smooth following; full client collision and latency tuning pending |
| Inventory | B opens the server backpack; container contents retain art, hue, position and quantity; double-click use; original MUL container backgrounds at 2× scale and coin pile art; quantity on selection; repositioning, original stack quantity dialog, split and merge requests; multiple movable container panels and cross-container drop requests; equip/unequip requests supported |
| Character UI | P opens an in-window equipment panel with dressed character preview; server-reported health/stamina/mana, attributes, gold, armor and weight; drag wearables onto character panel to equip, Remove buttons return gear to backpack; full paperdoll, skills, journal, spellbooks and settings pending |
| Interaction | Server target cursor accepts inventory/world items, mobiles and terrain/static locations; Escape cancels. Enter opens classic speech input; incoming speech shown in a short journal; banker keywords sent to server and returned bank containers displayed. Full journal, vendors/trading, combat/spells, death/resurrection pending |
| Reliability | Protocol fixtures, bounded asset caches, local server checks; long-session parity and full reconnect stress testing pending |

Use `tools/run_macos.sh` to build, sign with the identity in ignored
`build/signing-identity.txt`, and replace the existing workspace app instance.
Stable certificate signing keeps Keychain identity consistent across rebuilds.
The first migration from an ad-hoc binary can require one Keychain approval.

Local metadata-only telemetry lives in `build/telemetry/session-*.jsonl` (16 MiB
cap per run). It records pointer locations/control classes, semantic movement
input, login stages, incoming/outgoing packet opcodes and sizes, world counts,
player position/equipment, and movement acknowledgements/corrections. It excludes
passwords, account/character names, field values, chat, and raw packet payloads.
The saved-login tuple is not included in telemetry. Logs are local and ignored by git.

For an offline outfit example, use `--preview-body 400 --preview-equipment`.
Sample clothes appear only in this explicitly requested offline preview; live
characters always use server equipment.

OUO/UO1998 is now the intended protocol reference and connection target;
a local OUO checkout and runtime are available under `build/ouo` and
`build/.rundir`. The test build binds only to 127.0.0.1 (a local-only source
change in socket.c), using port 25939 and `-client 12532 -a 127.0.0.1 -test`.
On revision 814ea87, the Swift client successfully created a disposable account
and character, received login-complete plus 28 ground items and mobile updates,
and rendered the received scene with zero missing sprites. The screenshot is
`build/ouo-live.png`. Reconnecting to that character exposed an OUO abort in
`CItem_InternalMove` ("not detached", destination z=-128), after the server
accepted character selection. No client workaround or server logic fix has been
applied. A subsequent fresh-character integration test verified equipment,
a three-byte movement request, its acknowledgement and a 0x22 position
synchronization request answered by 0x20, with zero missing sprites.

The real-server integration test is opt-in: set `UO_LOCAL_TEST_PORT=25939`
when running `swift test --filter OUOIntegrationTests`. It connects only to
loopback and creates a disposable local character by default. The ordinary
test suite skips it when no port is supplied. `UO_LOCAL_TEST_ACCOUNT` can select
a previous fixture account (same fixed test password) to exercise reconnects.
Server-side simulation does not eliminate client complexity: animation, terrain
elevation, draw ordering, UI, prediction, and cache latency all need validation.

## Reference sources

- [ClassicUO upstream](https://github.com/ClassicUO/ClassicUO) and its
  [current BSD-2-Clause license](https://github.com/ClassicUO/ClassicUO/blob/main/LICENSE.md).
  Pin a revision and retain required notices when importing or adapting code.
  Animation decoding/direction mapping is adapted with notices in
  `LICENSES/ClassicUO.txt`.
- [nxdk](https://github.com/XboxDev/nxdk): SDL2 and lwIP support;
  [SDL sample](https://github.com/XboxDev/nxdk/tree/master/samples/sdl).
- [ModernUO installation](https://modernuo.com/docs/getting-started/installation/),
  [configuration](https://modernuo.com/docs/getting-started/configuration/), and
  [packet documentation](https://modernuo.com/packets.html).

Keep proprietary client assets, account credentials, and unsanitized packet
captures out of source control.

### Inventory and speech verification

The local OUO integration test verifies opening a backpack, splitting one coin from a stack,
placing it at explicit container coordinates, merging it back, and receiving an ASCII speech echo.
Press Enter to speak (Escape cancels); H/Home recenters, and movement resumes camera follow.
Drag a stack to choose a quantity using the original quantity-panel artwork, then click its destination.
Dropping onto a matching graphic/hue requests a merge. Right-click cancels the pending placement.
The client sends pickup/drop only once a destination is chosen and retains authoritative server contents.
Banker keywords use normal speech; live banker access and cross-container transfers still require live verification.

Live ground items and mobiles are retained within 32 tiles of the player (a margin beyond
the classic server visibility range), then discarded along with equipment owned by evicted mobiles.
The server must resend returning objects; previously visited areas are not a persistent world snapshot.
Container contents have a separate lifetime and are not evicted by this world-distance policy.
Asset image caches remain bounded independently. Telemetry records world eviction counts.

Target hit testing currently uses mobile body pixels and terrain/static artwork; equipment-only silhouettes and complete occlusion-aware selection remain to refine.

Stack quantities and the split dialog are enabled only for TILEDATA stackable items; equipment moves one item even when its packet amount field is greater than one. The AppKit coordinate harness also checks gear amount=178 versus a gold stack.

### Current playability gaps (2026-10-17)

This remains a work in progress, not a full replacement for a classic client.
Implemented features must still be verified together on UO1998; local OUO checks do
not establish live-shard parity.

- Login, reconnect, shard/character selection and basic character creation exist.
  Full creation appearance/profession choices and character deletion are incomplete.
- World rendering includes terrain, statics, animated mobiles/equipment, original
  paperdoll layers, and legacy MULTI house components. Special armor coverage,
  weather/lighting/effects, mounts/death bodies and complete animation parity remain.
- Ceiling cutaway follows adjacent overhead tiles, bounded to a local region.
  Touching buildings, upper floors, caves, and multi interiors need live regression
  checks; this is not yet a complete building/room visibility model.
- Predictive movement and server reconciliation exist; full collision, diagonal
  corner restrictions, multi stairs, obstacles and latency behavior need refinement.
- Containers, quantity splitting, merging, equipping, chat and targeting exist.
  Ground pickups, bank access, house signs and multi rendering need live checks.
  Hover outlines currently cover live ground items, not every selectable object;
  selection does not yet fully account for occlusion and equipment silhouettes.
- K opens Skills: legacy displayed values and direct-use actions. Skill locks/caps
  are not part of the selected 1.25.32 protocol. Skill use needs live-shard checks.
- Spellbooks/casting, combat controls, vendors/buy/sell, secure trade,
  death/resurrection, maps and general server gumps are still incomplete or absent.
- Credentials/settings and metadata-only telemetry exist. Configurable bindings,
  complete UI persistence, inventory cache lifetimes and resource-budget testing remain.
- Original Xbox work is deferred until macOS playability is established.

Recent local checks cover original male/female paperdoll gumps, multi signed offsets
and visibility flags, connected-roof isolation, and inspection packet encoding.
Ground dragging sends a pickup/drop only after an open container destination is chosen;
stacks prompt for quantity, and the server remains authoritative about possession.

Hovering a live ground item without moving for 0.5 seconds sends one inspection
request and displays the server label above it. Shift-click attempts to move the
whole stack (one item for non-stackable equipment) into the player's backpack.
Highlighting means selectable, not unlocked or movable; the server decides whether
pickup, opening, or unlocking succeeds.

Skills verification: the local OUO server returns a legacy full skill list. Its
Anatomy action receives the correct skill ID and passes the can-use event, but
script attachment returns `Failed to get script class` with the installed fixture
data. `testSkillTargetWithCompleteScripts` is retained behind
`UO_VERIFY_SKILL_TARGET=1` plus `UO_LOCAL_TEST_PORT`; it must pass against complete
scripts before claiming end-to-end skill-use verification. UO1998 use is unverified.

Classic cursors use original ART sprites and their embedded hotspot markers: normal
gauntlet, pickup/drag, directional movement, targeting, and the player's reported
war-mode color. Native text fields retain their text cursor. Shift-pickup uses the
closed gauntlet but does not imply that the server will allow lifting the item.
Caps Lock latches always-run. Entering chat clears both the game latch and the
macOS Caps Lock state through IOHIDSystem, including the keyboard LED when supported.
The game latch still clears if macOS refuses the request; telemetry records the
return status and read-back state. Shift remains a temporary run modifier.

Movement bindings are now arrow keys (combine adjacent arrows for diagonals) and
right-mouse hold. WASD and Q/E/Z/C no longer move or pan; letter keys are available
for commands. S is reserved for the future spellbook UI. Existing commands include
K skills, P character, B backpack, H recenter, Space use, and Enter chat.

### UI fidelity requirement

Use the original client gump sprites and classic layout for menus as they are
implemented, especially shard selection, character selection, character creation,
paperdoll/status, skills, spells, and container interfaces. Read sprites from the
user's installed assets; do not replace available original artwork with generic
modern panels. Native text input and accessibility can be layered over the classic
artwork. The current login/selection/creation and Skills panels are interim UIs;
conversion to their classic layouts is explicitly outstanding, not visual parity.

Character selection now uses the original-era selection controls (0x044D delete,
0x0453 create, 0x0456 main menu, 0x0459 play) and frame artwork. New selects a vacant
slot even on nonempty accounts. Deletion requires a separate in-window confirmation;
Cancel sends no request. Server rejection codes preserve the character list. Creation
full login/shard/creation layout fidelity remains.
Local tests cover deletion encoding, vacant-slot selection, character-list refresh,
and the confirmation/cancel UI. No live character has been deleted for testing.

Vendor buying: say "vendor buy" near a merchant. The 0x74 prices pair with the preceding
0x3C contents in reverse wire order (OUO writes the contents chain backwards); 0x24/0x30 opens the original 0x0870/0x0871 shop artwork.
Double-click a stock row or use +, then click the Accept seal to send 0x3B; right-click closes.
The server remains authoritative about stock, prices, funds and delivered items.
Packet/layout tests pass; live purchase confirmation remains outstanding.
Minoc shops: Old Miners' Supplies 2453,429; The Forgery 2472,561. These match classic
region data and the official Minoc guide, but UO1998 vendor inventory is not verified.
Click-to-walk/door navigation, A war-mode/attack, and axe targeting for lumberjacking
are active requested next steps, not implemented by this vendor milestone.

Character setup now has editable Strength/Dexterity/Intelligence (classic 60-point
allocation), three distinct starting skills (100 points, maximum 50 each), sex,
name, and server-provided starting city. Invalid allocations stay in the form and
send no creation request. The stone frame uses original gumps; the native controls are still interim. Back returns to character selection.
Selection is centered around its actual artwork bounds with readable text.

Vendor regression: matching prices/names in forward wire order caused the live
axe row to buy a mace. Reversed mapping is now covered by a two-item packet test.
Stock rows draw their own nonselectable text and handle double-click; scrolling
is constrained to the parchment. Gold Avail displays the server status gold field,
with unknown shown as a dash, never an assumed zero or inferred bank balance.
OUO shopkeeper.c uses bank funds only for totals >= 2000 when carried gold is
insufficient; live-shard policy remains server-controlled. Metadata telemetry now
records offer serial, graphic, price and quantity, without names or raw packets.
Validation: 95 tests passed, 2 integration tests skipped; AppKit harnesses checked
selection confirmation, creation submission, long shop-list layout and double-click
purchase callbacks. Corrected live purchase still needs verification. Reported
boat deck/sail rendering remains under investigation.

Appearance creation is available through the Appearance button: skin tone, hair
style/color, and male facial hair style/color, with original paperdoll sprites in
the live preview. Female selection clears facial hair; buns are female-only under
OUO validation. Plain skin hue and hair/beard words are serialized in the 100-byte
1.25.32 packet. Clothing colors require the later 104-byte format and are not exposed.
No live character was created or deleted during validation.

Vendor selling: say "vendor sell" near a suitable merchant. The 0x9E server list
provides eligible item serials, art, quantities and unit prices. Double-click/+ adds
quantities; the Accept seal sends 0x9F. Right-click cancels with a zero-item reply.
Original 0x0872/0x0873 artwork is used; sell total occupies its own artwork position.
The client never infers sale eligibility or deletes inventory before server updates.
Validation: 97 tests passed, 2 integration tests skipped, plus appearance and vendor
AppKit preview/interaction checks. Live selling and custom appearance creation still
need user verification. Character selection buttons now share an inside-frame row,
with rejection/status text in a separate area above them.

Boat mast fix: the first invisible MULTI.MUL component supplies the root item's
visible graphic, as in ClassicUO Item.LoadMulti. The loader now draws that root
(mast/base on boats), while continuing to omit other invisible components that
are supplied independently by the server. Sentinel root art 0–2 remains hidden.
An offline boat fixture renders the mast/base with no missing sprites; regression
coverage distinguishes the mast from an invisible, server-owned hatch. Validation:
98 tests passed, 2 integration tests skipped. Live boat comparison remains pending.

Equipped tools can now be used by double-clicking their paperdoll sprite or clicking
Use in the equipment list. This sends the same object-use packet as inventory
items; mining/lumberjacking then follow the server's target request. Equipping a
tool alone does not activate it. An AppKit fixture verifies both pickaxe controls
send its serial; target telemetry includes coordinates and graphic without text.
Live mining still needs verification.

Classic panel presentation: the character sheet now uses a 2× paperdoll and original
Help/Options/Log Out/Journal/Skills/Chat/Peace/Status button sprites. Options opens
connection settings; Journal opens chat history; Skills and Log Out are wired.
Chat-service and war-mode buttons remain disabled. Status reveals the existing
interim statistics/equipment controls, including Use/Remove. The selected character
name is shown in the artwork's name area and is not logged. Modern outer chrome
and the separate Close button are removed. The artwork's minus closes the panel.

Containers now show only their original artwork, with no title/footer frame or
Close button. Dragging background areas moves the panel; item pixels retain
item-use and inventory drag behavior. Backpack minus closes; right-click on an
idle container closes (during an item drag it cancels instead). AppKit checks cover
background movement, minus closing, item splitting/drop coordinates, and equipped
pickaxe sprite double-click/use after the paperdoll scale change.

Mining target correction: terrain hits now send graphic 0 in 0x6C, allowing the
server to resolve land at the target coordinates. Static rocks retain their static
graphic. Sending the land-art ID as a static graphic caused live mining rejection.
Regression verifies the ground hit and zero graphic bytes. NO DRAW static/ground
markers are filtered consistently from drawing and selection, including the
internal tile flag and known marker IDs. The boat mast remains visible.
Paperdoll scale is restored to 1× at user request; its interim details view now
uses flipped coordinates so controls appear in the intended top-to-bottom order.
Validation: 99 tests passed, 2 integration tests skipped, and equipped-tool UI check
passed. Mining success on the live shard still needs confirmation.

## Remaining playability gaps

The current implementation is not at full classic-client parity. Outstanding work
includes full collision parity (mobile obstacles, corner rules, bridges and mounts), mounted combat and
special equipment animation coverage, damage/death/resurrection,
spellbooks/casting, general server gumps, secure player trade, maps, music and remaining audio behavior, and
full settings persistence. Character creation and rendering still need wider live
coverage. Inventory, buying/selling, banking, and reconnect behavior require live
regression checks alongside local fixtures.

A now requests peace/war mode, as does the original paperdoll button or sidebar
mode button. The server's 0x72 reply updates player flags, cursor, and buttons.
In war mode, double-clicking another mobile sends an attack request; single-click
still inspects. Mining/lumberjacking use U and a server target cursor, not combat.
No automatic attack is sent when entering war mode. Local combat checks cover
packet bytes, invalid item serials, and preservation of other player flags; live
combat remains unverified.

Classic human peace/war stance selection now shares one implementation between
world rendering and mouse hit testing. War walking uses group 15, standing uses
7/8 according to held weapons, and second-hand equipment uses armed walk/run
1/3. Server action packets override these default groups. A real-asset harness
(`tools/check_combat_animation.swift`) checks both sexes, all directions, pickaxe
layers, and war-stance pointer alignment. Mounted and held-light exceptions are
still pending; live combat behavior has not yet been confirmed.

Combat target confirmation (0x30/0xAA), health updates, and combat end (0x31)
now feed a sidebar target display and a world marker. Names are retained for UI
only. Peace mode, deletion, disconnect, and eviction clear the target. Fragmented
confirmation/status streams are covered by local fixtures; live behavior remains
unverified. Equipped-item transfers now share the normal pickup/drop packet
builder with inventory items, validating ownership and a quantity of one. A
regression fixture covers pickaxe equipment → transfer packets → server container
confirmation, without optimistic removal from the paperdoll.

Left-clicking an otherwise empty world location now plans a bounded local A*
route, using land/static/dynamic/multi collision surfaces and headroom. Clicking
a door approaches an adjacent tile at a compatible elevation and uses it after
movement acknowledgements. Routes use the existing prediction queue and stop on
server denial. Arrows, right-mouse movement, Escape, chat, or focus loss cancel.
Hold Shift/Caps when clicking to request a running route. The planner searches
within 24 tiles and at most 4096 nodes; it does not cross closed doors en route.
Corner clearance is conservative, mobile collision is still server-controlled,
and exact legacy collision parity is pending. The actual Minoc assets produce
straight and obstacle-detour routes in `tools/check_navigation.swift`; live routes
and door approach still require verification.

## CrossUO reference review

Reference checkout: `build/crossuo`, commit
`79d0f94a3645154dc1795045d9d89df554d6cd2a` (2026-09-08).
Upstream: https://github.com/crossuo/crossuo . This checkout is for inspection;
no CrossUO implementation has been copied into the Swift client during this review.

Useful comparison points:
- `src/Walker/PathFinder.cpp`: collision surfaces, min/max Z, diagonal clearance,
  and sliding along obstacles. Our planner checks corners but has no manual sliding.
- `src/Gumps/GumpPaperdoll.cpp`: equipment pickup, wear/drop distinction, and
  dropping onto the backpack icon itself. Icon drops are now supported from
  equipment, open containers, and the ground, using automatic bag placement.
- `src/Gumps/GumpContainer.cpp`: stack splitting, merge targets, and bag coordinates.
- `src/Gumps/GumpSpellbook.cpp`, `GumpShop.cpp`, `GumpGeneric.cpp`, and
  `GumpStatusbar.cpp`: layouts and interaction flows still incomplete in UltimaXB.
- `src/Managers/PacketManager.cpp`, `src/Network/Packets.cpp`: version-dependent
  message behavior. `xuocore/client_db.h` recognizes 1.25.32; this is identification
  evidence, not verified protocol compatibility with UO1998.
- `src/Managers/SoundManager.cpp`: sound playback integration.

The repository top-level license is AGPL-3.0. Individual files have their own
SPDX declarations: the inspected pathfinder, container, and paperdoll files are
MIT; the spellbook file is AGPL-3.0-or-later. Check the specific files and retain
applicable notices for any future reuse. The build uses CMake, C++, SDL2 and
OpenGL, and documents macOS support. This has not been built or live-tested here;
its macOS support does not establish original Xbox compatibility.

Paperdoll backpack-icon drops use the sprite's opaque pixels and retain the
server's automatic-position sentinel (65535,65535), even when a container drag
begins away from the item origin. Wearable items dropped on the character equip;
items dropped on the bag go into the bag. Buttons, transparent padding, and a
backpack self-drop are excluded. Real-asset AppKit harnesses cover these targets
and the equipped-pickaxe drag; live shard confirmation remains necessary.

Click-to-walk was confirmed working by the user after the navigation build.
Door approach and exact legacy collision edge cases still need live coverage.

Server sound effects (0x54) now decode from the original SOUNDIDX/SOUND MUL
files as mono 16-bit PCM at 22050 Hz. macOS playback uses AVAudioPlayer, distance
attenuation and isometric stereo positioning, with 12 active voices and a 4 MiB
LRU decoded cache. The application menu's Sound Effects toggle persists; focus
loss and disconnect stop playback. Music, ambient looping semantics, sound.def
remapping, and client-generated footsteps remain pending. Local validation read
all 654 available effects and decoded 12 with AVFoundation without playing them;
audible live-server playback still needs verification.

Requested future automation: opt-in auto-mining and auto-herding. These are
roadmap items, not implemented controls. Build them on explicit tool/skill use,
server targeting and responses; show active state and a stop control. Stop on
manual input, disconnect, target failure, depletion, or weight limits rather than
blindly looping packets. Herding additionally needs animal selection, destination
selection, and success/failure handling verified before repetition is enabled.

Click-to-walk now displays a mint dotted route and destination ring, projected
using each planned tile’s elevation. The trail shortens as steps are taken and
clears on arrival, cancellation, manual movement, disconnect, or a rejected step.
It is a navigation overlay (visible over scenery), not a guarantee the server
will accept every step.

Automation UI requirement: show the selected mining/herding work-zone boundary
in the world, highlight the active target, and provide visible running/paused
state and a stop control. Zone selection and automation remain pending; the
route overlay does not start repeated actions.

Shift-click pickup and war-mode double-click attack now approach the target
before sending the action. Arrival waits for pending movement acknowledgements,
then rechecks the target's current position; missing or moved-away targets stop
with a message. Manual movement, Escape, chat/focus loss and disconnect cancel
queued actions. This is a one-shot approach, not continuous pursuit of mobiles.

Rejected route steps now wait for authoritative position synchronization and
replan against fresh nearby geometry, excluding rejected destination tiles for
that route. Up to three detours are attempted; denied turns, exhausted retries,
or no available path stop movement. Tests distinguish the denied sequence from
later predicted steps. Live obstacle/pickup/attack verification remains pending.

Gump loading now applies file-12 VERDATA overrides, including records absent from
the base index. The 1.26 creation frame/body art is present in those patches;
UO1998 has different patches. Original asset files remain unmodified. The full
classic creation layout and optional use of the 1.26 appearance artwork remain
pending; this loader change alone does not replace the creation screen.

Connection fix: complete 0x6E packets accept their full wire action/frame fields
and nonzero boolean flags. Missing local animation groups are handled by the
renderer instead of closing the game connection. Three recent telemetry sessions
showed disconnects caused by the previous over-strict animation decoder; live
confirmation that these forced re-logins are gone is still pending.

Movement now strips the run bit at 0–1 reported stamina, preserving facing and
run preference. Open-ground A* ties prefer tiles closest to the direct line,
removing needless zigzags without changing shortest-path cost or collision checks.

Server music packet 0x6D selects the classic 57-entry catalog. Playback prefers
existing MP3s, falls back to MIDI, respects track looping, and handles the stop
sentinel. Music has a separate saved menu toggle and pauses/resumes with focus;
disconnect stops it. All 57 track indices resolve to locally decoded MP3s in the
UO1998 pack. MIDI fallback remains unverified with this pack. Audible playback
and region changes need live verification.

The appearance preview now uses the original gold arch and creation body/hair
sprites, preferring active assets and otherwise using this workspace's optional
data/uo-1.26.0 pack for creation artwork only. Original assets are unmodified.
Hair/beard controls sit left, color controls right. Native controls and the outer
creation frame are still temporary. The 1.25.32 creation packet does not include
shirt/pants color fields; those controls remain pending protocol support.

Music live verification: the user confirmed music plays on town entry. Removed
the generic opening-track fallback after it played inappropriate music in town.
Music now follows server 0x6D commands only, including stop commands; silence
before the first command is intentional. Playback success is logged separately
from loading.
Map view: M toggles the original rounded radar gump (0x1393), with map pixels
clipped to its RGB555 0x0421 interior mask. Local view is isometric, follows the
player, and includes static scenery. Double-click switches Local/World views;
right-click or M closes; drag moves it. Transparent corners pass clicks through.
White marks the player and cyan marks nearby server-known mobiles, not a global
monster tracker. Named locations, monster/spawn categories and zoom remain pending.

Shift-click inside the map starts travel. Local map clicks invert the isometric
projection; World clicks choose full-map coordinates. Travel plans 32-tile sections
against fresh 48-tile collision snapshots, waiting for acknowledgements before
continuing. The dotted trail shows the current section. Server rejection triggers
bounded detours; Escape/manual input cancels. This is not global optimal routing:
large obstacles requiring travel away from the destination can stop it, and world
view resolution can select an inaccessible tile. No teleport or server movement
bypass is used. Journey tests cover a 100-tile route across four snapshots; local
map-click coordinates and original-frame clipping were verified. Live long-trip
verification remains pending.

Music query research: OUO HandlePacket_CLIENTQUERY has a 0x34 subtype-2 request
for a supplied region resource ID, replying with resource/music-list data rather
than playing the current track. UO1998 support and region IDs are unverified, so
no speculative query is sent. Server-side world-entry 0x6D is the direct way to
initialize location music.

Classic magery spellbooks: S uses a book in equipment or the top-level backpack,
requesting backpack contents if needed. Server open-container 0x24/0xFFFF opens
the original 0x8AC book with its 0x8B1–0x8B8 circle tabs. Only spells reported as
child-item amounts 1–64 are enabled. Double-click sends legacy macro 0x12 subtype
0x27 with spell ID and book serial, matching OUO's book-specific cast handler;
server targeting flows through the existing target cursor. Blank paper drags;
the original minus or right-click closes. Disconnect clears book panels.

Local verification covers book-scoped content IDs, duplicate/invalid contents,
exact cast bytes, fragmented framing, original-art rendering and known/unknown
spell click behavior. Live casting remains unverified. Detailed spell pages,
reagent/mana descriptions, draggable spell shortcuts, spell effects, other-era
books and modern spellbook bitmask packets remain pending. No spell is cast
automatically during testing.

Classic server menus: 0x7C icon/text choices now render and return 0x7D replies.
Icon menus use original gump 0x0910, hued art, horizontal scrolling and hover
labels; text menus use the original gray frame with scrollable options. Click
selects the exact server option index (even if earlier art is unavailable);
right-click sends choice zero to cancel. A new menu replaces the previous one,
and disconnect clears it. Telemetry includes menu IDs, option counts and choice
indices, never server-provided text. Tests verify packet bounds, fragmented
framing, exact icon/text/cancel responses and UI option mapping. Live crafting
menus remain unverified; general 0xB0 layout gumps, hue pickers, prompts and secure
trade are still separate parity gaps.

Legacy death/resurrection prompt: server 0x2C flag zero offers explicit Remain a
Ghost / Request Resurrection choices. The response is sent only after a click;
resurrection stays pending until server flag one confirms it. Death cancels
queued travel, movement predictions, targeting and the local combat target, and
selects the classic death track. Disconnect resets the prompt. The dialog uses
the existing original stone frame; exact historical death-screen artwork/layout,
grayscale world presentation, corpse/death animations and healer resurrection
through general server gumps remain pending. Local tests cover both responses,
duplicate suppression, server confirmation, malformed packets and UI waiting
state. No live death/resurrection was triggered; UO1998 behavior is unverified.

General server dialogs: `ServerGump` now decodes legacy 0xB0 headers, brace-delimited
layout commands and UTF-16 text, and encodes 0xB1 button/switch/text-entry replies.
Unknown commands are retained as data for explicit renderer handling; layout text
is never executed. Tests cover signed placement, Unicode surrogate pairs, exact
reply bytes, cancellation, truncation, malformed layouts and oversized replies.
This is protocol groundwork only: live dispatch, original-art layout rendering,
page navigation, radio groups, editable fields and reply validation against the
active dialog are still pending. No dialog replies are sent automatically and no
dialog or entered text is recorded in telemetry.
