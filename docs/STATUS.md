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
- Full equipment coverage, mounts, corpse/death animations and spell effects.
- Complete combat, spell, skill, crafting, healer and housing workflows.
- Live two-party secure-trade validation, live text-prompt validation and remaining
  server packet handlers.
- Startup music selection when the server sends no music packet; no guessed
  region query or opening-theme fallback is currently used.
- Built-in assistant, automated mining/herding, zone overlays and workflow controls
  are required goal work, not implemented yet; see [assistant scope](ASSISTANT.md).
- Xbox rendering/networking/runtime integration and memory/performance validation.

## Local verification snapshot

2026-10-18: 169 Swift tests executed, 2 opt-in integration tests skipped, no
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
older messages. Original bitmap text and journal filters remain pending. Skill
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
offered item back into a bag, or double-click it to request return to the backpack.
Right-click requests cancellation and waits for the server. Pending transfers and
acceptance replies disable acceptance, and known nested items on the other side
cannot be moved. Trade status, revision and item metadata are logged, never the
partner name. Local fixtures cover the window and drop regions; live two-party
trades have not been tested. Dragging an offered stack opens the original quantity
picker for partial withdrawal; a changed offer cancels the picker and prevents a
stale request. Local UI tests cover selection, cancellation and revision changes.
Trade-item drag previews and opening offered nested bags remain incomplete.

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
