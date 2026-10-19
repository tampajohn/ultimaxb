# Status

The goal is full chosen-era playability on macOS, then evaluation of an original
Xbox port. The scope also includes a built-in UOAssist-style assistant, with
automated mining and herding as explicit deliverables. The present client is
experimental and is not at parity yet.

## Implemented, with live shard testing still ongoing

- Login, shard/character selection, reconnect, creation stats/skills/appearance.
- Terrain/statics, mobiles/equipment/hair, hues, multicomponent houses/boats,
  roof cutaways, interpolated movement and server reconciliation.
- Inventory, stack splitting, equip/unequip, ground pickup/drop and paperdoll.
  Container sprites highlight on hover; Shift-click transfers a whole stack or
  single non-stackable item to the backpack (items already there stay put).
- Chat, bounded session journal (J/paperdoll), bank requests, vendor buy/sell,
  targeting, skill requests and war mode.
- Skills/status sidebar, equipped tool use, action animations, sound and music.
- Original radar frame, local/world view, Shift-click travel in local sections.
- Spellbook, legacy choice menus, original-art hue picker and death/resurrection prompt.
- General 0xB0 dialogs: original gump images/resizable backgrounds, labels,
  buttons, pages, checkboxes, radio groups and editable fields; 0xB1 replies.
  Item pictures with hues, tiled backgrounds, text hues and scrollable classic
  formatted text (bold/italic/underline, centering, colors and entities) are supported.
- Persistent settings, optional Keychain password, metadata-only telemetry.

## Remaining parity work

- Validate every interaction against live UO1998, particularly long travel,
  spellcasting, death/resurrection and general server dialogs.
- Full original menu layouts, fonts and hue fidelity; more general gump commands
  (localized content, complete HTML semantics, transparency and tooltips).
- Character-creation clothing colors require resolving the chosen protocol's
  version-specific packet support; current appearance UI is not an exact clone.
- More reliable global path planning, dynamic obstacles and elevation/occlusion
  edge cases. Large barriers can stop segmented routes.
- Full equipment coverage, mounts, broader death-animation coverage and spell effects.
- Live verification of ghost routes through doors and passable objects.
- Complete combat, spell, skill, crafting, healer and housing workflows.
- Live two-party secure-trade validation, live text-prompt validation and remaining
  server packet handlers.
- Startup music selection when the server sends no music packet; no guessed
  region query or opening-theme fallback is currently used.
- Built-in assistant, automated mining/herding, zone overlays and workflow controls
  are required goal work, not implemented yet; see [assistant scope](ASSISTANT.md).
- Xbox rendering/networking/runtime integration and memory/performance validation.

## Local verification snapshot

2026-10-18: 189 Swift tests executed, 2 opt-in integration tests skipped, no
failures. The server-dialog harness additionally verifies page changes without
replies, selection state and Unicode text across pages, plus formatted text, item art
and overflowing scroll content. This does not establish
live dialog compatibility or completion of the full parity goal.

Live integration check (2026-10-18): saved-Keychain login, shard selection and
existing-character world entry succeeded in Minoc. Status/skills requests and
backpack open/contents completed without packet errors, inventory rejection or
disconnect during the check. No items or character position were changed. Ambient
0xFFFF sound requests are ignored rather than reported as missing samples; this
does not stop other sounds. General server dialogs remain locally tested only.

Journal: original 0x0820 scroll artwork with 512-line / 256 KiB in-memory limits,
no disk storage, reset on disconnect, and preserved scroll position while reading
older messages. Original bitmap text is implemented; journal filters remain pending. Skill
locks are not exposed for the 1.25.32 connection: its skill packets have no lock
fields; OUO's newer extended format and feature flag require separate support.

Hue picker: legacy 0x95 request/reply with the OUO request type ID preserved,
original 0x0906 frame, 0x0907 confirmation and 0x0845 slider artwork, dye-tub
preview, and the classic 1,000-color palette across five shade settings. Only
explicit confirmation sends a reply. Local UI/wire tests pass; live dyeing has
not been exercised. Modern clients differ in handling the unused/type word;
this implementation targets the chosen OUO-era packet layout.

Secure trade groundwork: legacy OUO 0x6F open/update/close packets and 17-byte
accept/cancel replies are modeled with server-confirmed acceptance. Offer changes
(including known nested contents) invalidate the UI revision and withdraw pending
or confirmed local acceptance. Tests cover exact replies, malformed packets, stale
acceptance, cancellation and unrelated trade IDs. Dispatch, original-art window and drag/drop are now connected as described below;
live two-party validation remains outstanding. No live trades were initiated or accepted.

Secure-trade UI integration: the original 0x0866 window now displays both offers
and server-confirmed acceptance. Drag inventory into the left offer; drag your
offered item back into a bag, or double-click a non-container item to request return
to the backpack. Double-click bags on either side to request their contents; single
clicks request item labels. The partner’s items cannot be dragged or equipped.
Right-click requests cancellation and waits for the server. Pending transfers and
acceptance replies disable acceptance, and known nested items on the other side
cannot be moved. Trade status, revision and item metadata are logged, never the
partner name. Local fixtures cover the window and drop regions; live two-party
trades have not been tested. Dragging an offered stack opens the original quantity
picker for partial withdrawal; a changed offer cancels the picker and prevents a
stale request. Local UI tests cover selection, cancellation and revision changes.
Nested bag opening uses the regular server container response and still needs
live two-party verification. Equipping from your offered bag revokes acceptance
and locks further acceptance until the matching equipment update and acknowledgement
arrive. Trade-item drag previews remain incomplete.
Release tests: 187 total, 2 skipped; trade UI interaction harness passes.

Trade transfer ordering: acceptance now waits for both DROPOBJ_OK and an item
update at the requested destination (or the merged destination stack). Removal
from the old container alone cannot unlock acceptance. Pickup rejection releases
the guard, while a failed drop waits for a subsequent authoritative return of the
item to a container or the ground; bounce paths need not send an acknowledgement.
Unrelated ground updates cannot confirm a container destination. Reordered
acknowledgement/update, bounce and merge fixtures pass. Drop rejection telemetry
records its coordinates, rather than mislabelling the X byte as a reason code. If a shard
omits the expected acknowledgement or destination update, acceptance remains
disabled and cancellation is still available; that compatibility requires live
two-party testing. The local OUO process is currently stopped, and an earlier
runtime log records buffer-overflow failures, so it has not yet provided a reliable
end-to-end trade test.

Text prompts: legacy ASCII 0x9A and dialog 0xAB requests now open an original-art
entry panel, with explicit submit/cancel replies preserving prompt identifiers.
Dialog text-length and numeric limits are validated before sending; ASCII prompts
use a client-side 239-byte cap. Local wire tests and an AppKit fixture verify invalid
input, confirmation and cancellation. Live server prompts remain untested; ASCII
entry currently uses a popup rather than the original console interaction.

Spellbook details: single-click a known spell to inspect its facing detail pages;
double-click a known name or detail icon to request casting. Original book icons,
page-turn artwork and circle tabs are used, with incantations and reagent lists
from ClassicUO metadata. Local UI checks cover navigation, casting callbacks,
unknown-spell rejection and inventory refresh during selection. Live casting,
original bitmap/rune fonts and persistent spell shortcut layouts remain unverified or pending.

Spell shortcuts: drag a known spell name or detail icon out of its book to create
a movable original-art icon. Double-click casts through the active book validation;
right-click removes it. Repeated drags reuse the same book/spell shortcut, with a
64-icon session limit and cleanup on disconnect. UI fixtures verify the drag
threshold, absence of casting during drag, screen clamping, casting callback and
removal. Layout persistence and live casting remain pending.

Targeting: while a server target cursor is active, T selects the player. Clicking
the paperdoll body, equipment or backpack selects that object before any use or
drag action. Existing Escape cancellation remains available. Local paperdoll
fixtures verify target identities and absence of use/drop side effects, alongside
normal equipment dragging. Live spell/tool outcomes still require validation.

Ambient lighting: legacy global 0x4F and player-specific 0x4E packets now drive
world brightness using the ClassicUO level calculation. Menus, chat and interaction
feedback retain their brightness. Unrelated personal-light updates are ignored,
levels clamp to 30, and disconnect resets lighting. Wire/state tests cover these
cases. Local world-tile and carried lights are implemented as described below; spell
lights remain incomplete.

Local lighting: LIGHTIDX.MUL/LIGHT.MUL masks decode bounded dimensions and signed
5-bit samples. Visible static and ground-item light sources use tiledata light IDs;
additive masks modulate the world pixels with the ambient level. A frame caps light
sources at 100 and reuses decoded masks within that frame. A dark Minoc fixture
verifies ambient dimming plus brighter lamp-lit pixels and produces the published
night screenshot. Dynamic light-ID overrides, colored lights,
light blocking by walls, verdata light patches and spell effects remain pending.

Carried lights: equipped light sources illuminate around their visible owner using
the same interpolated position as the mobile renderer. The render fixture verifies
brighter surrounding ground, movement starting at the prior displayed tile, and
removal of illumination after unequip or owner removal. Current placement is centered
on the mobile; exact facing/hand offsets and live equipped-lantern testing remain
pending. No live inventory changes were made for this fixture.

Overhead speech: independent speaker messages replace the previous single shared
label. Up to three messages per speaker stack above the object, with wrapping,
4–12 second expiry, a 64-message cap and a 512-character per-message cap. Mobile
labels use interpolated positions. System messages stay in the journal/chat;
object-label responses replace prior text for that object. Disconnect clears the
in-memory buffer. Tests cover independent speakers, expiry and bounds. Original
bitmap fonts and collision avoidance between speakers remain pending.

Speech color: ASCII speech parsing now preserves hue and font IDs. Overhead
entries retain the server hue and use the original palette, falling back to white
when no usable palette is available. Font IDs are preserved but original bitmap
font rendering is still pending; journal/chat text styling remains unchanged.
Packet-to-overhead tests verify hue preservation.

Outgoing speech modes: classic prefix-plus-space input selects whisper (;), yell
(!), or emote (:), with a visible mode label while typing. Emotes are wrapped in
asterisks; ordinary punctuation without a following space remains literal speech.
Packet tests cover mode bytes, text, packet length, empty prefixes and the encoded
200-byte limit. Metadata logs the mode byte and length only. Live delivery/range
checks and per-mode configurable colors remain pending.

Assistant groundwork: a deterministic tool-action runner now waits for target
requests and an explicitly correlated result. Local tests cover one-target mining
and two-target herding-shaped sequences, reused cursor IDs across target types,
incompatible/duplicate targets, cancellation, timeout, refusal and depletion.
It is not connected to live automation or UI yet; see [assistant scope](ASSISTANT.md).

Equipped-tool targeting: selecting an out-of-reach world target after using a hand
item now defers the target response while routing to an adjacent walkable tile.
The clicked cliff elevation is not treated as a standing surface. Arrival waits
for movement acknowledgements and rechecks held tool, current cursor and object
position. New cursors, other actions and manual route cancellation prevent stale
arrival actions. Targets within reach and inventory targets still respond directly.
Local navigation regression tests pass; live approach remains to be exercised.
The existing 24-tile local routing limit applies. Ore hauling to a forge is now
explicitly required in the assistant scope but automatic drops are not implemented.

Ore-haul groundwork: local tests now cover confirmed drop/walk/pickup cycles,
reordered acknowledgements, no movement on acknowledgement alone, no repeated
drop before pickup, changed stacks, invalid routes, timeout, stop and late-drop
recovery tracking. This core is not wired to live inventory or UI; ore and forge
selection, transfer coordination and visible controls remain required. The running
client was left untouched for this change.

### Door-aware click travel and chat history

When a nearby clicked destination has no ordinary route, the client can plan
through door cells to discover an approach to a server-supplied door. It walks
using normal collision, uses the door once, waits up to four seconds for that
same door's graphic or position to change, then rebuilds the route to the original
destination. Walls and blocked terrain stay impassable. Manual movement, route
cancellation and disconnect cancel the pending continuation. At most four door
attempts are allowed per click. Missing/locked doors stop with feedback.
This is local routing within 24 tiles; live locked/unlocked house verification
is still required, and it does not guarantee access through every multi-door layout.

Recent chat now exposes the original journal artwork as a history control.
Scrolling over recent messages opens/browses the parchment journal; J still
toggles it. Local UI checks verify wheel scrolling, preserved reading position,
tail following, clearing and the artwork-backed history button.

Validation: release build and 172 core tests (2 asset-dependent skips, no failures).

### Running pace transitions

Movement interpolation now starts a fresh cadence estimate when switching between
walking and running, while keeping position and animation phase continuous. The
old estimate could render the first running step over 300 ms after walking instead
of its 200 ms base duration. A regression covers an intervening facing-only update
and both pace changes. Release suite: 173 tests, 2 skipped, no failures.

The local OUO reference (`CPlayer_HandleMovement`) tracks movement timing across
five requests and increases stamina drain for rapid requests. This is reference
behavior, not proof of the deployed UO1998 server configuration. Movement packets
carry direction and sequence, not a requested multi-tile destination; client
pipelining remains bounded at five outstanding single-step requests. Batched
movement speed behavior on the live shard has not been verified.

### Roof clicks target covered floors

Click-to-walk resolves roof art to a collision-valid floor below the same world
cell. For eaves over an impassable wall, it considers covered cells within two
tiles in the connected roof footprint. It does not project the screen pixel onto
unrelated terrain behind the house or jump a roof gap into a neighbor. The
resolved floor feeds ordinary routing and the door-opening continuation. Walking
hit tests now also include server-provided house components and ground tiles.
This does not select arbitrary upstairs floors; live roof/door combinations still
need verification. Local coverage checks same-cell floors, eaves, invalid floor
heights, bounded search and disconnected buildings. Full suite: 176 tests, 2 skips,
no failures; the connected-footprint follow-up passed all three focused tests.

Door routing follow-up: session metadata records two automatic use requests
followed by server door changes; this verifies those transitions, not every house
or complete route. The approach action now retains the originally selected door
state. If that door changes before arrival, it replans without sending another
use/toggle (which could close an already-open door). Missing doors stop with
feedback. Release suite: 177 tests, 2 skipped, no failures. This follow-up was
built without interrupting the currently running manual-test session.

### Classic journal text

The journal now renders Latin-1 letterforms from the installed FONTS.MUL (font 9),
with word wrapping and native glyph fallback for unavailable characters or missing
font assets. The loader retains offsets into a bounded file, exposes only complete
224-glyph fonts, and tolerates the installed file's partial trailing font data.
The document uses bitmap drawing rather than native selectable text; session text
is still exposed to accessibility, held only in memory, and never logged.
Original glyph offsets follow the ClassicUO font reference (see existing BSD notice
in LICENSES/ClassicUO.txt). Tests cover pixel decoding, transparency, offsets,
font bounds and truncation. The installed file supplies ten complete fonts.
The UI fixture verifies artwork, history scrolling, tail following, preserved
reading position, fallback layout and clearing. Release suite: 179 tests,
2 skipped, no failures. Visual fixture: docs/screenshots/journal.png.

### Static object targets (trees)

Live metadata showed the axe requesting an object cursor, followed by no target
reply: local validation incorrectly required every object target to have a serial.
Map trees have static graphics and coordinates but no serial. Target validation
now accepts a valid static graphic for object cursors and sends the XYZ-form reply,
while bare ground still requires a location cursor. This follows ClassicUO's
TargetManager behavior. A regression checks the exact tree reply, preserved cursor
identity, and rejection of bare terrain/invalid static IDs. Local rejection now
records only target metadata. Release suite: 180 tests, 2 skipped, no failures.
Live resource collection after this correction still needs verification.

### Controller input

Native macOS GameController support detects an extended gamepad and routes left
stick/D-pad movement through the existing prediction and reconciliation path.
RT runs, A uses the facing object, B cancels the current target/route, X opens the
backpack, Y opens the paperdoll, and LB uses the equipped tool. The footer shows
controller hints while connected; keyboard and mouse remain usable. Inputs are
suppressed outside the focused world, during chat, and before world entry. Controls
must return to neutral after disconnect/focus changes before movement resumes.
Metadata records connection changes and button action IDs, not device identifiers.
Right stick moves the original-art world cursor with deadzone and time-based
velocity. A confirms mobile/item/terrain targets using the mouse hit-test path;
overlays block world selection. Mouse movement restores mouse targeting.
Release build and 184 tests passed (2 skips). Hardware aiming remains to verify.
Inventory/menu navigation and remapping are still missing. Radial menus for spells, skills and items are explicitly deferred
at the user's request.

### Server help

Paperdoll HELP now sends the classic 258-byte 0x9B help request instead of showing
local control instructions. Existing server menu/gump handlers display the reply.
The user selects any stuck/recovery option; no staff request is auto-submitted.
Packet layout is tested; live shard menu/recovery behavior remains to verify.

### Animated scenery

ANIMDATA.MUL now drives animated static and server item art, including fires and
forges. Tile metadata controls eligibility; signed frame offsets and the classic
80 ms interval unit select the image. Rendering, alpha hit-testing and hover
outlines share the displayed frame time, while targeting and collision preserve
the original tile identity. The world refreshes while scenery animates even if
mobiles are idle. Missing/truncated/invalid records fall back to base art, and
frames use the existing bounded art cache. Installed-asset checks verify changing
fire/world pixels and stable hit-test identity. Core timing/bounds tests pass.
Spell projectiles/impact effects are still missing; this is scenery animation.

Live metadata check: the new Help request received a 0x7C menu and controller
button actions were recorded. This establishes menu delivery and input activity,
not successful stuck recovery or complete controller usability.

### Local Test Center and corpse visibility

A separate OUO Test Center now runs on loopback port 2593; setup, commands and
restart instructions are in [LOCAL_SERVER.md](LOCAL_SERVER.md). A fresh local
account/character completed login, movement, inventory split/merge, equipment,
skills and chat tests. Test Center stat/skill commands were also confirmed via
server status/skill replies. Full suite with local integration enabled: 190 tests,
1 skipped, no failures. The earlier overflow belongs to the older test runtime;
the new separate world completed this run without that failure.

World corpse markers (0x2006) now retain the body ID and direction and render the
final classic death frame instead of invisible static art. Alpha hit-testing uses
the same frame and retains the corpse serial for normal double-click container
use. Installed assets verified monster/animal/human bodies in all eight directions.
Death transitions, alternate death poses and body remapping remain incomplete. Live kill-to-loot behavior still needs verification.

### Separate local login profile

The login screen has Saved Server and Local Test Center buttons. The local button
loads a separate localhost profile and connects immediately when a saved local
account/password exists; otherwise it presents its account fields. Primary keys
and Keychain service remain unchanged for compatibility. Local preferences use a
separate namespace and Keychain service, so saving or forgetting local credentials
does not modify the primary profile. Switching is disabled during connection/play.
Release build and an isolated-preferences UI harness verify local save/forget,
profile switching, fixed local address and preservation of primary settings.

### Corpse equipment layers

0x89 corpse equipment lists are now decoded with length, layer and duplicate-entry
validation. They join with container item descriptions in either arrival order;
only items still owned by that corpse can appear on it. Clothing uses final death
frames, classic layer order and individual hues. The composite preserves body
anchors and is shared with alpha hit-testing. Looted/deleted items are omitted,
and corpse equipment metadata is pruned with distant scenery. This does not put
corpse contents into the player's equipped-item model. Tests cover reordered
updates, wrong owners, loot removal and malformed packets; installed human assets
verify hued clothing and selection in eight directions. 192 tests passed, 2 skipped.

### Scenery visibility regression guard (2026-10-18)

Normal connected play now renders statics even if the offline preview's T toggle
or --land-only option disabled them. Explicit debug-camera mode retains the toggle;
land-only previews show a SCENERY HIDDEN status. Bounded render_state telemetry
records scenery counts, missing art, and visibility cutoffs every five seconds.
The reported live session had no current ceiling or render errors, but the old
telemetry did not capture the toggle, so the original cause remains unconfirmed.
At its final Minoc position (2493,482,15), the installed-asset regression harness
verifies preview-to-play restoration, no outdoor cutoff, and 349 rendered objects
including its player fixture, with no missing art. Release suite: 192 tests,
two opt-in skips, no failures. Corpse render/hit-test asset harness also passes.

### Corpse loot selection (2026-10-18)

Corpse gump 0x0009 excludes zero-quantity appearance entries from both drawing and
hit testing. Live metadata showed hair/beard entries overlapping actual loot and
receiving rejected pickup requests. These records remain in world state for corpse
body rendering; ordinary containers retain zero-amount non-stackable items.
The installed-asset corpse-container harness verifies selection through overlapping
appearance entries and ordinary zero-amount candle pickup. Existing container
hover/quick-pickup/target-priority interaction checks also pass.

### Classic stationary graphic effects (2026-10-18)

0x70 now decodes its classic 28-byte envelope and records metadata-only kind,
graphic, duration, and supported-kind telemetry. Ground and attached effects use
original static art/ANIMDATA signed offsets at the effect animation cadence;
attached effects follow interpolated mobile positions and sort above their owning
mobile within the world draw order. Effects expire at the server duration, are
capped at 128 concurrent entries, clear on disconnect, and never enter world
collision, hit testing, inventory, or server-entity caches. Missing attached
entities fall back to the packet coordinates.

Validation: 195 tests, two opt-in skips, no failures. New tests cover packet bounds,
signed elevations, lifetime, moving attachments, ground anchoring, and bounded
state. The installed-asset harness checks that 0x376A changes rendered pixels,
advances animation frames, and leaves the exact original frame after expiry.
Live spell appearance remains to be checked. Moving projectiles, lightning,
screen fades, explosion chaining, 0xC0/0xC7 effects, and special blend modes remain
parity gaps; those are not represented as supported by this change.

### Lightning, traveling spells, and impacts (2026-10-18)

Classic 0x70 kinds 0–3 now have render paths. Lightning attaches to its source
entity, uses original gumps 0x4E20 onward at 50 ms intervals, and expires after
400 ms. It accepts the zero graphic/zero duration used by lightning packets.
Traveling effects use elapsed-time movement at the classic five-pixel step rate,
follow updated destination positions/elevations, and rotate original art unless
the packet requests a fixed direction. Requested impacts use 0x36CB for 400 ms
at 50 ms frame intervals. All effects share the world's depth sorting; no visual
effect enters collision or selection. Flights have a ten-second cleanup limit.

Validation: 199 tests, two opt-in skips, no failures. Tests cover lightning
attachment/expiry, missile progress, target tracking, no-impact cleanup, impact
expiry, bounded lifetime and sprite rotation. Installed-asset renders verify
lightning, moving fireball and impact art without missing sprites; lightning and
fireball frames were visually inspected. One client rebuilt/restarted for live
verification. Remaining: live comparison of trajectory/timing, special blend
modes, screen effects, 0xC0/0xC7 extended effects, and broader spell workflows.

### Modernized character art experiment (2026-10-18)

Added local tools to export a four-facing, clothed human reference from installed
ANIM.MUL layers and build a side-by-side/gameplay-scale browser comparison.
A built-in imagegen edit explores the user's requested modernized proportions and
lighting. Reference, generated sheet, prompt and comparison remain private local
artifacts under build/visual-upgrade; original MULs are untouched. This is an art
direction preview, not an installed replacement: the generated poses/anchors drift,
clothing is baked in, and consistent animation/equipment layers still need work.
The comparison normalizes character height and lets users inspect each facing at
1×/2×/4× and against the existing world. Export and HTML generation completed;
comparison JavaScript syntax checked and page opened locally.

Local Test Center recovery: the previous server stopped during a save with a
1 GiB CDataBuffer overflow. Restarted the existing world on loopback port 2593;
no account/world reset. Root cause and save reliability remain unresolved.

### Character animation study (2026-10-18)

The reference exporter now supports --walk, exporting all ten original human walk
frames with the same layered clothing and original anchors. Added a local browser
player comparing that cycle with an eight-frame generated study: play/pause,
frame stepping, scrubbing, playback speed, gameplay/inspection scale, and alignment
guides. The viewer uses fixed scale and camera, without interpolation that would
conceal pose drift. Local generated sheet and prompts are in build/visual-upgrade.

The generation is NOT production-ready: alternating gait/identity consistency is
uneven, and multiple transparency requests retained a painted background. The
viewer labels these defects explicitly. The approved standing style remains the
art-direction reference; client animations and MUL assets are unchanged. Export
completed and preview JavaScript syntax checked; the animation page was opened.
A consistent rig or controlled frame-authoring pass is still required before
animation replacement can preserve movement and independently equipped clothing.

Connection failure handling (2026-10-18): absent loopback servers now fail promptly
instead of waiting for the 15-second handshake deadline; connection refusal on
remote endpoints is also surfaced immediately. Cancelled deadlines cannot fail a
new connection generation. Closed-port retry coverage passes twice on the same
client; the release suite passes 200 tests with 2 opt-in skips.

Local Test Center reliability remains blocked by a backend save defect: two
periodic saves exhausted the per-block buffer at 1 GiB and the server exited.
The original saves are preserved; diagnosis uses an isolated world copy. This is
not a verified repair, and the local server is currently unavailable.

Save-defect reproduction: an isolated copy saves successfully before login, but
shutdown saving loops after `OUOIntegrationTests/testRealOUOWorldEntry` passes
against port 2594. Sampling the stuck process shows repeated player/container
serialization inside `SaveDynamic0_WriteCommit`. The diagnostic process was
stopped to prevent further buffer-overflow logging; original world data was not
modified. The precise linked-list corruption remains under investigation.

Local server save correction: traced the duplicate player insertion to a `void`
versus `int` virtual-method return mismatch in OUO's player trade cancellation.
A tracked source patch now makes logout unlink the player correctly. The isolated
login/inventory → save → reload → same-character test passes, including persisted
strength. The corrected Local Test Center has been restarted on port 2593 with
the original saved world. Periodic-save soak testing is still pending; see
[local server instructions](LOCAL_SERVER.md) for patch and reproduction details.

Deployment check: the corrected port-2593 server passed the disposable account
world-entry, inventory, skills and Test Center integration test. The full Swift
suite remains at 200 tests, 2 opt-in skips, zero failures. One signed macOS client
instance remains running; no client relaunch was needed for this server-only fix.

Stat sidebar refresh (2026-10-18): Test Center stat changes update STR/DEX/INT
on the server but send only resource packets (0xA1/A2/A3). The client now requests
a full status reply when those packets change the player's resource maxima,
coalescing bursts over 100 ms and cancelling pending refreshes on reset. It does
not infer base stats from resource maxima. Damage/regeneration, another mobile's
updates and full status replies do not trigger refresh loops. Unit coverage and
a real local-server run verify all three `.set` commands update base stats without
an unconditional status request in the fixture. Release suite: 201 tests, 2 skips,
zero failures.

Periodic-save check: an isolated build using the same save path at a 64-tick
interval (16 seconds, versus the normal 4096 ticks) remained responsive through
multiple saves and passed same-character reconnect/inventory/stat checks afterward.
The accelerated interval was never installed in the user server. Normal-interval
soak testing remains pending on the running port-2593 process.

Black-frame flash correction (2026-10-18): current-session telemetry recorded 33
`Animation frame overlaps its index` failures around (3647,2653). The renderer
cleared its complete image on each exception. The installed ANIM.MUL has 365
zero frame offsets; these sparse/absent sprites now return nil, while nonzero
offsets overlapping the table remain errors. A failed refresh retains the last
complete image and matching camera/time coordinates, and telemetry records whether
a frame was retained. No original assets were changed.

Validation: 202 release tests, 2 opt-in skips, zero failures. The installed-asset
harness `tools/check_sparse_animations.swift` exercises body 201/action 4/direction
3 frames 0–2, including two absent frames, and verifies terrain/statics remain
rendered. The exact reported live scene still needs observation after deployment;
other sources of flicker have not been ruled out.

Normal-cadence save observation: the original port-2593 server (PID 85184)
remained listening after its index save advanced to 19:36, approximately 17
minutes after startup. This verifies one normal periodic save after the fix,
in addition to the accelerated isolated test; it is not a long-duration soak.

Skill commands: traced nonsensical skill values and unusable skills to OUO's
loader interpreting a leading skills.txt comment banner as the version header.
A tracked source patch skips banners before parsing the header. The isolated
Anatomy-target integration test passes and now asserts all 46 skills equal 1000
tenths after `.set all 1000`, replacing the earlier Mining-only assertion. The
port-2593 server was cleanly saved and restarted with the correction.

Hidden appearance: renderer now applies full classic hidden hue 0x038E to a
mobile and its equipment when the server's 0x80 flag is present, following the
local CrossUO reference. The player remains visible to themselves; a sidebar
label confirms Hidden. Installed-asset harness verifies a distinct visible
appearance and exact original-color restoration when revealed. Release suite:
203 tests, 3 opt-in skips, zero failures.

Spell integration: the initial opt-in test failure was traced to fixture
sequencing, not missing spellbook contents. It opened the book during the
server's post-inventory action cooldown, then tried casting with a weapon still
in hand. The fixture now waits before opening the book and confirms both hands
are empty before casting. See the verification below for the covered flow.
The user's indoor-lighting report also remains under investigation: telemetry
shows server ambient level 22 (brightness 0.3125), but that alone does not explain
reported indoor appearance. No speculative brightness override was installed.

Dynamic light-pattern correction (2026-10-18): ground-item packet 0x1A's
direction byte also supplies the light ID for light-source items (as in the
ClassicUO item-update reference). WorldTile previously discarded it, so every
dynamic lamp used TILEData's map-static default. Ground tiles now retain that
ID, including zero, and the renderer uses it only for actual light-source art.
Map statics and multi components retain their asset-defined patterns; existing
forced graphic patterns remain. Invalid IDs do not select arbitrary masks.

Validation: 204 tests, 3 opt-in skips, zero failures; installed-asset harness
`tools/check_light_patterns.swift` checks server-selected versus default masks,
non-light items, invalid IDs and unchanged daylight rendering. This corrects one
lighting mismatch, but the reported indoor appearance still needs live visual
confirmation. Ambient levels remain server-driven. Foreground light occlusion was subsequently added below; colored lights and
broader lighting fidelity remain parity work.

Classic spell integration verification (2026-10-18): isolated Test Center on
loopback port 2594 passes opening the 64-spell starter book, casting Night Sight
and Lightning on the fixture player, and receiving each target cursor, casting
animation, and expected attached/lightning effect. The test confirms weapon
unequip before casting and waits for item-use cooldown. Failure diagnostics
include only this disposable fixture's server messages. Temporary server
instrumentation was removed and the test passed again on the normal patched
server build (20.2 seconds). Release suite: 204 tests, 3 opt-in skips, zero
failures. This verifies two representative spells, not all 64 spell behaviors,
reagent/mana failure cases, or live UO1998 spell compatibility. The user's app
and port-2593 server were left running throughout.

Hidden-state reconciliation (2026-10-18): added an opt-in isolated Test Center
Hiding test (`UO_VERIFY_HIDING=1`, `UO_LOCAL_TEST_CENTER=1`). It uses the actual
Hiding skill, verifies the local mobile remains present with flag 0x80, and
checks a confirmed movement step clears the flag. The initial server test
passed. Inspection also exposed a separate client race: queued movement ACKs
returned an entire old mobile snapshot, overwriting newer server appearance.
The new regression test failed 24 assertions before the fix. ACKs now use the
predicted position/direction with the latest server body, hue and flags, so
hiding/revealing, war and poison state cannot be rolled back by an older step.
Release suite: 206 tests, 4 opt-in skips, zero failures. This does not establish
all skill behaviors or reproduce the exact timing of the user's original report.
The server-backed hiding/reveal test also passes after the reconciliation fix
(12.0 seconds), with the user's port-2593 server untouched.

Foreground light occlusion (2026-10-18): renderer now follows the local CrossUO
GameScreen::AddLight foreground-cell rule: an opaque visible static/item at
(x+1,y+1), at least five Z units above the source, suppresses that light. Applies
to map/dynamic lamps and carried lights. NoDraw, transparent art, terrain and
transient effects do not occlude. The index respects our connected cutaway cells
so removed ceilings do not extinguish interior lights and neighboring buildings
remain opaque. It is a classic sprite visibility rule, not general wall shadows.

Validation: 209 tests, 4 opt-in skips, zero failures. Installed-asset harness
`tools/check_light_occlusion.swift` verifies an unobstructed lamp changes night
pixels, a foreground wall suppresses its light mask exactly, a cutaway restores
its contribution, and daylight remains unchanged. Existing light-pattern
harness still passes. The exact indoor screenshot remains visually unconfirmed;
colored lights, broader light placement and night appearance still need work.

Death/resurrection state correction (2026-10-18): 0x2C action 1 dismisses the
death dialog; it does not prove resurrection succeeded. OUO sends it before
ApplyResurrection, which can refuse the request. The client now retains ghost
state until an authoritative local-player living-body update. Classic ghost
bodies 402/403 also establish ghost state on login; living updates clear it for
healer resurrection without a death-dialog packet. Other mobiles and predicted
movement do not drive this state. Unit tests cover both sexes, pending choice,
ghost movement, denial/dismissal and both packet orders.

An isolated end-to-end death attempt did not kill its disposable character:
self-targeted Lightning produced its effect but no damage even at one HP.
Source inspection confirms spelskil.m Q43E suppresses player spell damage in
guarded regions. The default Ocllo fixture therefore cannot establish death
and resurrection this way. Full integration remains pending a fixture outside
the guarded region or a dedicated controlled death setup; no passing end-to-end
death claim is made. User character/server were not changed by this experiment.
Release validation: 211 tests, 4 opt-in skips, zero failures.

Death/resurrection integration completed locally (2026-10-18): a fixture-only
starting-city patch places a fresh character at (2603,309,15), outside guards.
The test passes (22.0 seconds): spellbook contents, free hands, lethal Lightning,
0x2C death offer, ghost body 402/403, corpse creation, explicit resurrection
response, and living body 400/401. The earlier failure was guarded-region spell
damage suppression; an additional fixture sequencing issue came from Lightning's
delayed damage callback. The death test now omits the earlier nonlethal Lightning
cast. Backpack waiting also now checks the requested container, since nearby
corpses can send 0x3C contents before the backpack opens.

The fixture source change was removed from the normal OUO checkout and its
normal executable rebuilt. Only the isolated port-2594 process used the special
spawn; it was stopped after verification. The user's client and port-2593 server
were left running. Live UO1998 death, healer resurrection, corpse retrieval and
resurrection denial still require broader workflow verification.
Release suite after the fixture additions: 212 tests, 5 opt-in skips, zero failures.

Death-time interaction cleanup (2026-10-18): death offers and authoritative
living-to-ghost transitions now cancel routes, predicted movement, pending tool
target context, spellbook-open intent, combat selection, trade transfer state
and vendor offers. A shared UI callback cancels held keyboard/mouse/controller
movement, ground/equipment drag previews, container placement monitors and stack
quantity dialogs. Removed quantity dialogs lose their callbacks. Keyboard repeat
and a continuing right-mouse drag cannot re-arm the cancelled movement; fresh
input remains available for ghost movement. A stale ground mouse-up is discarded.

Validation: 212 tests, 5 opt-in skips, zero failures; AppKit installed-asset
container harness verifies cancelling an open quantity dialog, cancelling after
quantity confirmation, no drop on stale mouse-up, and a successful new split
interaction afterward. Full live death during each mouse/controller interaction
has not been exercised; this validation does not establish that broader coverage.

Empty corpse snapshot ownership (2026-10-18): the recovery integration trace
showed that nearby empty corpses send 0x89 followed by an empty 0x3C. The client
previously attributed every empty snapshot to the last-opened UI container,
erasing the open spellbook's 64 entries during death/resurrection. WorldState now
uses a one-snapshot owner context from 0x24 (open container) or 0x89 (corpse
appearance), including repeated unchanged corpse equipment. Nonempty snapshots
use their explicit parents. Ownerless empty snapshots cannot erase an arbitrary
container, and malformed packets do not consume the pending owner context.
Unit regressions cover this sequence and genuine empty-backpack responses.

Corpse recovery remains unverified: the new opt-in `UO_VERIFY_CORPSE_LOOT=1`
extension identifies the newly created corpse at the death coordinates, but the
local server sends zero contents when opened. This is distinct from the client
snapshot bug. The fixture records bounded content-count/parent metadata and will
assert item serial, graphic, backpack and placement on successful recovery.
Validation: 213 tests, 5 opt-in skips, zero failures; isolated death/resurrection
plus retained-spellbook assertion passes in 22.2 seconds.

Ordinary corpse loot recovery (2026-10-18): the isolated recovery extension now
passes in 25.6 seconds. Server registration marks the starting inventory as
protected, explaining the earlier empty corpses. The fixture-only patch now adds
an ordinary gemstone after registration, leaving normal death/drop rules intact.
The integration follows that exact serial through death, the newly created
corpse, resurrection and recovery into the backpack, verifying graphic and
placement. Retained spellbook contents remain intact throughout.

Release suite: 213 tests, 5 opt-in skips, zero failures. The isolated port-2594
server was stopped after verification and its executable restored to the normal
build. The user's running client and port-2593 server were left uninterrupted.
Live UO1998 corpse recovery, healer resurrection and denial workflows remain
unverified; this result covers the local fixture only.

Declined resurrection and ghost movement (2026-10-18): added the opt-in
`UO_VERIFY_GHOST=1` variant of the isolated wilderness death test. After declining
resurrection it requires a movement acknowledgement, no denial, and an explicit
server position refresh one tile away with body 402/403 and ghost state intact.
Verified in 22.2 seconds. OUO sends no death-dialog reply when resurrection is
declined; source and the integration agree, so movement/position confirmation
provides the evidence instead. Connection failure diagnostics now identify
failure before world entry rather than reporting only a missing entry object.
This does not verify ghost door traversal, healer interactions or ghost reconnect.

Ghost route collision (2026-10-18): NavigationMap now uses the authoritative
player body's ghost state for local routes, map travel and replanning. Doors,
classic special graphics (0692/06F5/06F6/0846/0873), and lightweight dynamic
items cease obstructing ghosts. Static/multi components do not inherit the
dynamic-item weight exception. Supporting surfaces remain available; walls,
blocked land and diagonal clearance still apply. Resurrection cancels any route
planned with ghost permissions, and new routes use living collision rules.
References inspected locally: CrossUO Walker/PathFinder.cpp and OUO
CItem_GetSurfaceFlags_VT. The dynamic weight threshold follows CrossUO; the
server remains authoritative for item-specific movability overrides.

Validation includes cell collision regressions, world-item metadata propagation,
and tools/check_ghost_navigation.swift using installed terrain/tiledata and a
closed door. The harness checks a blocked living step, accepted ghost step,
unchanged terrain Z and a direct ghost route. Actual server traversal through a
closed door remains unverified; prior integration verified open-ground ghost
movement only.

Server-confirmed ghost door passage (2026-10-18): the isolated fixture now places
a closed door beside spawn. With `UO_VERIFY_GHOST_DOOR=1`, integration first
requires a living movement denial at the doorway, then verifies the planner's
living/ghost results, declines resurrection and walks the ghost into that same
cell. The server confirms the position and ghost body while the door retains
its closed graphic. The test explicitly turns after death because the server
can change facing. Passed in 23.3 seconds against local OUO. This extends the
prior open-ground check; live UO1998, locked-door variants and other passable
objects remain unverified. No production server rules were changed.

Death animation and combat lifecycle (2026-10-18): classic 0xAF is now decoded
and validated. It clears a matching combat target, cancels an attack route to
that mobile, and removes the mobile and worn equipment from authoritative world
state. A separate visual snapshot plays the fall with its equipment and last
interpolated position. Snapshots are capped at 128, expire after one animation,
and reset on disconnect. They never enter hit-testing or server state. The
matching corpse is withheld during the fall to avoid drawing both poses, then
normal corpse rendering resumes. Missing death assets leave the corpse visible.
The packet's alternate-death flag and corpse direction's high bit now select
matching classic death groups (monster 2/3, animal 8/12, human 21/22).

Validation: fragmented 0xAF parsing, atomic malformed-packet rejection, target
and equipment removal, animation frame progression, duplicate-event handling,
expiry, ghost visibility and group selection. Installed human assets verify
both variants advance and their final frames match corpse art; the final render
was visually inspected. Monster/equipment combinations and live combat timing
still need broader verification. Reference packet/group behavior was checked
against local OUO packet_manager.c and CrossUO DisplayDeath/animation groups.

### Enemy and inventory feedback (2026-10-18)

- Preserve mobile notoriety from 0x77/0x78, across position-only 0x20 updates and predicted movement. Enemy/murderer notoriety (5/6) and the active combat target receive a red silhouette outline in scene draw order, replacing the target circle. Neutral/criminal mobiles are not automatically classified as enemies.
- Radar dots distinguish enemies/target, innocent, ally, neutral, and invulnerable mobiles. Local map labels come from nearby static and received dynamic shop signs, with bank/blacksmith priority, overlap suppression, and a six-label cap. This is nearby sign discovery, not a global POI database.
- Containers show hover names and quantities, plus visible counts for stackable items only; equipment metadata is not interpreted as a stack count.
- Validation: 219 tests passed (five opt-in integration tests skipped); release app build passed. `tools/check_enemy_outline.swift` rendered installed assets and verified 233 red edge pixels; image inspected. Map label and container UI behavior still require in-app visual testing. Mobile hover names remain pending.
- Dye investigation: active HUES.MUL hue 1 is RGB (0,0,8); hue 0 disables palette replacement. Local OUO dye script clamps both to 2. No live dye packets sent or items changed.

### Classic UI, travel journal, and gathering (2026-10-19)

- Added original FONTS.MUL labels to map POIs, stack counts, sidebar status/commands, skills, and travel controls. Removed the black stack-count plates and modern sidebar blur/rounded buttons. The bottom debug bar remains unchanged. Native editable fields remain for accessible text/password entry; remaining dialogs, paperdoll detail panes, vendor rows, and creation labels still need the shared bitmap styling pass.
- Logged-out UI uses the installed 1998 wooden chest and original login/main-menu controls (0x3E8, 0x3F2, 0x410). The later castle login IDs are absent in this pack. Input, remember gem, and menu button placements were matched exactly against their parent images. Server/local profiles and Keychain handling remain available under Server & saved login. No credentials are present in test screenshots.
- Character and map-marker hover names use the existing server inspection protocol. Automatic inspections are throttled; map names are memory-only, pruned with nearby mobiles, and cleared on disconnect. Explicit clicks are not throttled.
- Travel journal saves up to 16 editable destinations per server/character, supports picking a replacement point on the world map, and provides Go/resume and Stop. Manual movement/focus loss stops the existing route. Seed inn positions come from [RunUO AccountHandler](https://github.com/runuo/runuo/blob/master/Scripts/Accounting/AccountHandler.cs), excluding later New Haven. These are destinations, not teleport commands.
- Weighted local A* prefers terrain named cobblestones/flagstone in this pack. Known enemies and the combat target add clearance/cost; newly blocked steps trigger replanning or stop. Unknown/out-of-range enemies cannot be anticipated. Segmented travel is not a complete global route graph: major detours, closed doors, islands, boats/moongates, and arbitrary city pairs remain limited. The installed static Minoc-to-Vesper route reaches the destination in 821 steps; no character was moved for that check.
- Gather cycles off/reagents/server-marked movable items. It only attempts received ground items within one tile and 16 Z, excludes corpses/hidden objects, and performs one lift/drop at a time. It waits for acknowledgement plus the resulting backpack item or merged stack count, avoids repeat attempts while a serial remains visible, pauses during targeting/trade/combat/manual inventory, and stops on refusal, timeout, capacity estimate, or disconnect. Tiledata weight estimates can differ from server rules. Gathering starts off each session and does not walk toward items.
- Validation: 225 tests pass, five opt-in integration tests skipped. Pickup eligibility, acknowledgement ordering, merging, timeout/refusal, weighted routing, enemy clearance, hover throttling, and destination bounds have deterministic coverage. AppKit harness checks account-to-password Tab order, remember toggle, main-menu return, and renders login/sidebar/travel without loading credentials or connecting. Live gathering and intercity travel remain unverified.

### 2026-10-19 — Flexible viewport and text rendering
- World viewport fills the space beside the sidebar and above the debug strip. Raster width follows the available aspect ratio; normal layouts retain 720 logical vertical pixels. Terrain/mobile/item picking, paths, controller anchors and overhead labels share the displayed dimensions. Ultra-wide raster dimensions remain bounded to 2048 pixels.
- Recent chat uses FONTS.MUL speech lettering with preserved baked dark outlines. Overhead labels honor server font/hue and wrap without native text rectangles. Compact bitmap Journal control replaces the squeezed title sprite; the scrollable parchment journal remains available.
- Investigated the 10:58 crash: uncaught AppKit/CoreText exception while drawing WorldView text. Debug text now draws directly with a concrete CoreText Menlo font instead of NSString's native typesetting path; target prompts use bitmap text. This addresses the observed drawing path, but does not yet prove the intermittent live crash eliminated.
- Validation: 227 tests, five skipped, zero failures; real-asset 640/1440/2048-width renders preserve central pixels and picking; 30 offline world redraw/resizes passed. Journal interaction checks passed. Client relaunched once.
- Pending reports: close stale bank/container/spellbook windows on authoritative invalidation, and replace short-segment intercity travel with full-route planning capable of finding distant bridges (Minoc to Britain stalls at water).

### 2026-10-19 — Complete map routes, pickup refusals, open-object lifetime
- Intercity travel now plans to the actual destination on a worker using a separate asset reader and bounded collision chunks. Binary-heap weighted A* searches actual terrain/static surfaces; local segments follow that itinerary and still check live obstacles, enemy distance, and server denials. Stop/manual input cancels planning. A changed player position discards a stale result. This is bounded walking planning, not boat/moongate travel or guaranteed shortest paths.
- Real-asset Minoc (2477,411,15) to Britain (1602,1591) reaches its destination in 1,484 steps in ~1 second; every step also passed independent local collision snapshots. This particular route goes around blocked terrain rather than crossing blocked base terrain. A synthetic distant-bridge case verifies that full search can detour away from its destination. Live journey remains unverified.
- Metadata showed repeated pickup refusals. Rejected items are now skipped without disabling the selected gathering mode; capacity pauses picking, oversized stacks are skipped, and unresolved transfer timeouts still stop safely. No automatic reattempt of a still-observed refused serial.
- Open containers/spellbooks now track ancestor removal and proven external access anchors. Server object removal closes matching/nested windows. Known bank roots stay anchored to where opened and close beyond three tiles; carried books/bags stay open. Empty contents alone do not close a valid window. Unknown roots wait for authoritative evidence. This covers removal/range invalidation, not a universal server timeout packet.
- Validation: full 230-test regression (five skips) plus new bridge-search test and repeated three-test window-lifetime checks passed. Release builds passed. The new live behaviors still need user-session observation.
- Follow-up: Gather's second mode is now **all**, selecting nearby portable ground items regardless of the server movable-override bit. Corpses and immovable asset weights remain excluded. Focus loss no longer cancels explicit travel; direct keyboard/mouse/controller input remains focus-gated. The common-mode timer and a route-scoped macOS activity keep requested travel progressing in background; audio behavior is unchanged. Gathering can accompany a background route. Activity ends on completion/cancel/disconnect. Latest regression: 231 tests, five skips, zero failures.

### 2026-10-19 — Container-tree invalidation and bounded enemy detours
- Object removal now invalidates cached descendants, equipment ownership trees, corpse mappings and stale open/contents context. Whole-container snapshots remove missing child subtrees while retaining the valid container itself. Moving a bag into another container preserves its children. Out-of-range ground/mobile roots evict their nested cache without touching carried inventory. Window closure consumes these authoritative invalidations.
- Intercity enemy avoidance is a bounded preference, not a hard five-tile exclusion. Each local section compares a normal collision-checked route to an enemy-penalized route and limits extra walking to six steps or half the baseline route length, whichever is greater. Moving enemies no longer cause per-step replanning. Crowded corridors remain traversable; walls/server refusal remain authoritative. This may walk near or through enemies and is not an attack automation.
- Validation: 236 tests, five skips, zero failures. New coverage exercises nested deletion, empty snapshots, reparenting, cache eviction, malformed parent cycles and a crowded corridor with/without a physical wall. Live enemy-group behavior remains to be observed.

### Login transition follow-up — 2026-10-19

Returning from shard selection to the main menu now disconnects the pending login and resets stale lists before showing the account form again. Keyboard traversal includes only visible, enabled controls and focuses the current selection/creation screen. The shard action explicitly uses text-only drawing (AppKit can substitute a placeholder image when assigned nil).

Validation: release build passed; `tools/check_login_flow.swift` injects offline server-list and failure events with isolated preferences, verifying shard → back → login and failure recovery without a network login. The existing gameplay instance remains running for live crowd-routing validation; these login changes take effect on the next relaunch.

### 2026-10-19 — Travel recovery after forward progress
- Replaced the journey-wide three-refusal budget with local obstruction recovery. Eight tiles of displacement from the first failure, confirmed by server movement acknowledgements, renew the budget. Repeated failures in one area remain limited to three replans. New routes start fresh.
- Movement exposes the exact acknowledged step separately from the latest predicted display position. Queued predictions, duplicate acknowledgements and turns cannot renew retry allowance. Old blocked tiles are distance-pruned during recovery and the retained set is bounded.
- Validation: 239 tests, five skips, no failures; release build passed. Added regression coverage for repeated nearby failures, renewed progress, stale obstacle pruning, and acknowledgement/prediction separation. Existing gameplay process was preserved; this recovery change and the login transition follow-up await the next relaunch/live validation.

### 2026-10-19 — Character creation styling and focus
- Creation and appearance labels/actions use the installed bitmap font. Closed skill/city/appearance selectors share classic panel styling and preserve color swatches; native menus retain keyboard selection and accessibility. Name/allocation fields retain native editing with flat parchment colors. Male/female selection uses a bitmap button.
- Switching stats/appearance rebuilds Tab traversal from visible enabled controls; disabled beard selectors are excluded after switching to female. Existing allocation, appearance and server-city validation remain unchanged.
- Release build and offline creation harness passed. Harness checks submission, appearance values, female beard disabling, and focus loops before/after switching panels. Rendered `build/character-creation.png`, `build/character-appearance.png`, and `build/character-appearance-female.png`; inspected previews. No live character creation or running-client restart. Expanded dropdown menus/editable text remain native; exact original creation-flow/layout parity is still incomplete.

### 2026-10-19 — Vendor parchment and quantity controls
- Vendor stock rows, bill-of-sale quantities, totals, reported gold and status now use bitmap lettering. Dark parchment lettering can omit the extra outline; shared text defaults remain unchanged elsewhere. Original buy/sell parchment and seals remain in use.
- Adjusting quantities preserves list scroll position instead of jumping back to the first item. Bill of sale includes both plus and minus controls; stock limits and pending-trade guards still apply. Reported gold remains the server status value, not an inferred bank balance.
- Release build passed. Offline buy and sell harnesses pass double-click selection, scroll preservation, plus/minus adjustment, stock limits and exact-serial callback checks. Inspected the rendered buy/cart parchment. No purchases/sales were sent to a server, and the live client was left running. Changes await next relaunch; broader vendor refresh/response behavior still needs live verification.

### 2026-10-19 — Vendor submission failures and missing confirmations
- Vendor submission returns local validation/session errors to the panel before it enters the pending state. Invalid selections remain editable instead of becoming permanently disabled without a sent packet.
- After ten seconds without the server closing/replacing the trade panel, status explains that confirmation is missing and asks the player to close/reopen stock. It does not claim success/failure or automatically resend; the accepted selection remains locked to prevent duplicate trades. Closing/removing the panel cancels its timer; right-click remains available. Timeout telemetry includes vendor serial/mode only.
- Release build and offline buy/sell harnesses passed. Coverage includes local rejection retaining enabled controls, pending timeout messaging, duplicate-submit prevention and closing a timed-out panel, in addition to quantity/scroll checks. No live transactions or client restart performed.

### 2026-10-19 — Spellbook text and stable detail pages
- Spellbook index, names, incantations and reagents use dark bitmap lettering on the original book artwork. Wrapped detail text is clipped to its page; title placement avoids the page-turn sprites.
- Inventory updates preserve a previously visible spell when recomputing detail pages, instead of retaining an array offset that could silently jump to unrelated spells after insertions. If neither visible spell remains, the book returns to the index.
- Release build and offline spellbook harness passed, including adding lower-numbered spells while viewing details, casting the retained spell, unknown-spell rejection, page navigation, shortcut dragging/casting/removal. Inspected index/detail renders. Live book update/reconnect behavior still needs session validation; existing client left running.

### 2026-10-19 — Combined UI regression runner
- Added `python3 tools/check_ui.py`: builds release, combines seven existing Swift AppKit fixtures into one offline executable, and runs both vendor buy/sell modes. Includes login transitions/profile isolation, classic login/sidebar/travel UI, creation, vendors, spellbook and journal. Python only orchestrates build/check execution; client functionality remains Swift.
- Combined checks passed on current sources. Full core regression: 239 tests, five skipped, zero failures. UI artifacts remain in ignored build/. These checks exercise local behavior and do not establish server-wide gameplay parity.
- Confirmed the existing PID remained active with recent game/world updates and acknowledged movement, so no relaunch was performed. Recent committed client changes remain pending next relaunch. Live travel/crowds, server transactions, and reconnect still require session validation; automation integration and remaining classic UI/gameplay parity gaps remain open.

### 2026-10-19 — Death cancels gathering; classic resurrection dialog
- Authoritative death/dialog handling now disarms gathering and clears any pending automatic pickup state alongside existing movement/target/combat/trade cancellation. Gathering does not automatically resume after dialog dismissal/resurrection.
- Resurrection dialog uses bitmap labels/buttons on its original stone frame. Generic classic buttons now visibly dim when disabled, matching their noninteractive waiting state; sprite buttons already applied disabled opacity.
- Added death panel to the combined offline UI runner (eight fixtures). Release build and both fixture passes succeeded. Injected 0x2C death/dismissal events verify gathering switches off before ghost-body arrival and remains off; explicit resurrection choice and disabled waiting controls remain covered. Inspected the waiting-state render. No character was killed/resurrected on a server; running client preserved.

### 2026-10-19 — Persistent spell shortcut layouts
- Shortcut positions/removal persist under server/port/player scope, keyed by book serial and spell ID. Positions use normalized window coordinates and existing placement clamping. Preferences contain UI coordinates/IDs only; no credentials, spell contents or ownership assumptions are saved.
- Saved icons restore when that book's server-provided contents arrive, only for currently known spells. Cast requests continue through active book-content validation. Disconnect clears live icons without deleting preferences; right-click explicitly removes a saved shortcut. Saved data is size/count bounded, validated and deduplicated.
- Release build and combined nine-fixture UI pass succeeded. New persistence fixture covers roundtrip, scope isolation, replacement, removal and malformed entries. Live relaunch/book restoration remains unverified. Immediate login-time restoration before opening the book, and persistence for other panel positions, are still incomplete. Running client preserved.

### 2026-10-19 — Invalidate approach routes when objects disappear
- Server object removal and cache eviction now cancel an approach that depends on the missing target/tool, including pending door waits. The client no longer walks all the way to a removed object before reporting failure. A missing equipped tool also cancels its owned active target cursor. Ordinary travel and unrelated removals are unaffected.
- Added an offline adapter fixture that injects framed 0x55/0x1D events without a transport connection and verifies pickup/use/attack/tool approach cancellation plus unrelated/plain-travel cases. Release build and all ten combined UI fixtures passed in both vendor modes. Live behavior remains pending next relaunch; active session was not interrupted.

### 2026-10-19 — Bounded telemetry rotation for long sessions
- Replaced the silent 16 MiB logging cutoff with three per-session chunks, each at most 16 MiB. The base path is newest; `.1.jsonl` and `.2.jsonl` retain earlier complete records. Separate historical sessions are preserved. Oversized single records are discarded without disabling subsequent logging; existing base files are not truncated at startup.
- Metadata fields/privacy boundaries are unchanged. Reused the timestamp formatter rather than allocating one per event.
- Release build and eleven combined offline fixtures passed. The rotation fixture forces repeated small-file rotations and verifies chronological retention, byte bounds, parseable whole records, oversized-record recovery, single-file mode and existing-file protection. The currently running client still has its original writer until relaunch; its telemetry was confirmed fresh and below its limit. No live logs were modified by these tests.
