# Status

The goal is full chosen-era playability on macOS, then evaluation of an original
Xbox port. The scope also includes a built-in UOAssist-style assistant, with
automated mining, lumberjacking, herding, hauling, smelting and crafting as explicit deliverables. The present client is
experimental and is not at parity yet.

### 2026-10-19 — Britain departure route-search budget
- Reproduced long-distance search failure from the live Britain position (1451,1654,10). Road penalties consumed the global search near barriers; stale priority-queue entries also consumed budget without exploring new tiles.
- Search budgets now count actual tile expansions. Global travel reserves 100,000 expansions for road preference, then up to 300,000 for a uniform-cost, destination-directed fallback. Both passes retain the same collision, bridge, diagonal and elevation rules; this weighted search does not promise a shortest route.
- Added per-pass strategy/outcome/expanded/popped telemetry and distinct messages for disconnected terrain, budget exhaustion and map-loading failure.
- The local-asset intercity regression revalidates every returned step from the actual Britain position to Minoc, Vesper, Yew and Trinsic inns plus Minoc/Vesper bank approaches; all six pass in roughly 0.7–1.9 seconds each. Core regression: 277 tests, five skips, zero failures. All sixteen offline UI fixtures passed. Live travel still depends on server movement, dynamic obstacles and door responses.

### 2026-10-19 — Confirmed banking totals and live travel evidence
- The active session recorded two completed banking workflows with seven deposit requests each, and subsequent automatic pickup confirmations during travel. This is live evidence for those runs, not a guarantee for every banker, door or route.
- Banking now counts units and transfers only when both source reduction and destination increase are confirmed. Completion reports those totals; an empty run explicitly says there were no gathered goods to deposit. Per-transfer confirmation, completion and stop telemetry include totals without item names or private payloads.
- Eight banking core tests pass, including partial updates, repeat updates and resetting totals. All sixteen offline UI fixtures pass in both runner passes; the banking packet-adapter fixture covers a confirmed two-item deposit followed by an empty bank arrival. The current running session is preserved; the new reporting takes effect on the next launch.

### 2026-10-19 — Automatic pickup pacing after live busy refusals
- Live metadata showed four busy lift refusals (0x27/255), each about 0.6 seconds after the preceding pickup confirmation. Automatic gathering previously allowed another request after 0.5 seconds; its post-confirmation pause is now one second.
- Refusal cooldowns start at receipt time, rather than the original request time. A slow refusal therefore cannot permit an immediate follow-up request. Refused serials remain skipped while observed; unrelated late refusals do not extend the wait. Gather mode stays enabled.
- Eight pickup core tests pass, including delayed replies, cooldown boundaries, no duplicate credit and eligibility of other items after refusal. All sixteen offline UI fixtures pass in both runner passes. Live effectiveness of the longer pause still needs validation after the next launch; the current running journey is preserved.

### 2026-10-19 — Serialize item use with automatic inventory transfers
- Double-click/use now shares the transfer guard with drag, equip and unequip. While an automatic pickup, overload recovery or banking transfer is active, these actions report a waiting message instead of overlapping server requests; equip/unequip no longer fail silently at that guard.
- Accepted use starts the existing two-second manual-interaction grace period before gathering can resume. The equipped-tool shortcut reports a use only when the guard accepts it. No blocked action is queued or replayed later.
- The offline banking fixture now exercises use/equip/unequip during a pending pickup, use during banking, and use after completion. All sixteen offline UI fixtures pass in both runner passes. The active client is unchanged; this fix takes effect next launch. This does not yet serialize all manual-to-manual transfers or guarantee every server response can be correlated; that remains inventory reliability work.

### 2026-10-19 — Explicit classic door state during travel
- The post-relaunch Vesper-to-Minoc retry completed, including four door changes and arrival at the Minoc bank approach. The prior blocked-open-leaf failure did not recur, so its exact dynamic collision snapshot remains unavailable.
- Corrected a state ambiguity: any geometry change used to be remembered as an opened door, even if use had closed it. Known classic door art pairs now distinguish open from closed, including doors already open when first observed. Closed doors no longer inherit the remembered open-leaf exclusion. Custom art retains the geometry-change fallback rather than guessed parity.
- Door-change telemetry records old/new graphic, coordinates and known/unknown open state. The reference for paired art is local OUO item tile lookup (base graphic plus the open-state offset); supported families are explicitly bounded.
- Added core art-family boundary checks and offline packet-adapter coverage for initially open doors, retained open state and subsequent closure. Eight door core tests and all sixteen offline UI fixtures pass. The correction takes effect on the next client launch. This addresses a concrete state bug, but does not claim the earlier obstruction is conclusively reproduced or all door routes are fixed.

### 2026-10-19 — Keep open-door collision in click-to-walk planning
- Shared navigation's door-relaxed planning now removes only closed/unknown door surfaces. Known open leaves retain their actual tiledata flags, so solid leaves remain obstacles and passable art remains passable. Ghost exceptions are unchanged.
- Click-to-walk door approach no longer selects known-open or previously confirmed changed doors as opening candidates. Long-distance and local planning now agree on known open art rather than relying only on the long-distance leaf exclusion.
- Twenty focused navigation/door tests and all sixteen offline UI fixtures pass. The installed-terrain fixture checks actual 0x675/0x676 art mapping as well as ghost collision. Live original-obstruction reproduction remains pending; the running client is preserved until the next requested restart.

### 2026-10-19 — Clear superseded target cursors before new actions
- Starting an accepted skill, spell or item-use action now cancels the previous target request before issuing the new action. This prevents clicks during server latency from answering an obsolete tool/skill cursor. A blocked item use or invalid skill/spell selection leaves the existing cursor intact.
- Offline packet-adapter coverage includes old tool-route cancellation, server cursor replacement/cancellation, item use, valid/absent spellbook entries, accepting the subsequent cursor and disconnect cleanup. These checks exercise local packet handling without connecting or sending actions to the live character.
- The active client remains running; new target behavior takes effect on its next launch. This does not claim correlation of arbitrarily delayed server cursors to a specific skill/tool, which the classic protocol does not identify explicitly.

### 2026-10-19 — Serialize manual inventory transfers
- Manual moves, equip and unequip now share an outstanding-transfer guard. Further item use/transfers and automatic gather/bank/overload transfers wait for authoritative placement or refusal. Removal alone does not release the guard. Splits and merges observe destination changes, including drops onto existing stack serials.
- An unconfirmed transfer expires after five seconds with an explicit message; it is never replayed automatically. Ownership remains entirely server-driven. Disconnect clears the guard. Classic packets do not carry transaction IDs, so unrelated identical stack changes and very late replies cannot be conclusively correlated.
- Eight core tests cover placement/removal, same-bag splits, merges, rearrangement, equip/unequip, ground coordinates, refusal and timeout. All sixteen offline UI fixtures pass, including rapid manual actions, placement/refusal release and reconnect cleanup. No live inventory actions were sent; this change is pending the next client launch.

### 2026-10-19 — Preserve door waits through removal/replacement
- Current live-session telemetry showed two click-to-walk door requests followed about 40 ms later by `arrival_route_invalidated`, with 0x1D removal and 0x1A item updates nearby. The local OUO reference's door-open handler explicitly hides then repositions the door. Our arrival invalidation cancelled the pending local door wait on the intermediate removal.
- A pending door-open wait now owns that removal: no movement resumes until replacement geometry changes; a permanently absent door reaches the existing bounded timeout. Doors removed while still approaching and unrelated target/tool invalidations retain their previous cancellation behavior. Door waits are only created when local item-use validation accepts the request.
- Offline adapter checks cover separate removal/replacement reads with a tick between, one local destination continuation, permanent disappearance timeout, approach-time cancellation and long-distance wait preservation. Nine door core tests and all sixteen UI fixtures pass. Live confirmation remains pending next launch; the active client is preserved.

### 2026-10-19 — Harvest work-zone scheduler groundwork
- Added `HarvestWorkflow` over the existing tool-action runner. It validates bounded work zones and supplied sites/routes, waits for authoritative arrival and correlated tool results, enforces inter-attempt cooldown, advances on depletion, counts successful actions and stops on refusal, missing tool, overweight, timeout or leaving the zone. Unreachable sites cannot loop indefinitely; no reachable remaining site reports an explicit stop.
- Pause drains the current route/action; Stop immediately stops the state machine and cancels late target requests. A future adapter must cancel its movement on Stop. Eight scheduler tests plus five existing tool-action tests pass. These are deterministic core tests, not live harvesting evidence.
- This is not enabled in the client yet. Work-zone UI/overlays, resource discovery, tool selection/equip, enemy checks, result correlation, persistence and telemetry integration remain required; see [assistant scope](ASSISTANT.md). The running client was left intact.

### 2026-10-19 — Reference-derived harvesting outcomes and empty-attempt retries
- Added `HarvestOutcome`, using local era mining/bladed script messages and OUO system-speech framing. A successful attempt requires expected system text plus matching resource growth in the backpack or at the player tile. It supports either update order, expires after ten seconds, retains no speech text and reports only one result.
- Empty skill checks are now distinct from permanent refusal. The scheduler retries after cooldown, stops after a configurable consecutive-empty limit (default five), and does not increase successful-action counts for failed checks.
- Nineteen focused tests pass, covering core scheduling, outcome ordering, unrelated chat/resources/containers, ground positions, depletion/refusal, stale inventory and timeout, plus bounded empty-attempt retries. No live actions were sent. Profiles still require UO1998 verification and UI/adapter integration; they cannot provide transaction-ID correlation absent from the protocol.

### 2026-10-19 — Installed-map harvest-site discovery
- Added era-specific mining-land, mining-static and tree-art classification from the local itemmanip reference. Bounded flood planning uses normal collision, stays within the selected zone, excludes dynamic resource lookalikes, deduplicates identical targets and finds reachable neighboring standing tiles while preserving the target's true Z.
- Five focused tests pass. The installed-map verifier found 92 reachable mining sites around (2584,482) and 23 woodland sites around (2603,309), with no search truncation; every standing point was independently reachable through a zone-constrained A* check. These are candidate work sites, not confirmed un-depleted resources.
- Harvest UI/zone overlays, tool selection/equip, enemy checks and live adapters remain unfinished. No live actions or restart were performed.

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
- Long-distance travel opens blocking doors and waits for authoritative geometry
  changes before crossing; locked/unresponsive doors stop travel. Explicit system
  action-throttle responses allow two delayed door retries. Confirmed opened
  geometry is remembered across route restarts so an open leaf is routed around
  rather than immediately toggled closed. Local sections try earlier forward
  waypoints when their preferred endpoint is blocked. Banking and
  overload options survive door handling. With Gather enabled, travel considers
  new visible eligible ground items within six tiles, takes collision-checked
  detours of at most six steps, and resumes its destination. Enemy distance must
  exceed item distance and a conservative closing-time margin for every detour
  step and pickup pause; shrinking clearance cancels the detour. Pickup reach is
  two tiles, subject to server LOS. Travel drains pending movement before pickup
  planning and tries up to eight nearby candidates, so one unreachable object
  cannot starve other loot. Scan metadata records eligibility/path exclusions. These additions have offline packet coverage;
  the live Minoc bank entrance/deposit still needs retesting.
- Automatic travel preserves a stamina reserve (about 25%, capped at ten).
  It conserves by walking, spends the reserve for one enemy within four tiles
  or at least two within eight, and holds escape pace for three seconds after
  the threat clears. Recovery hysteresis avoids pace flicker. Exhaustion still
  forces walking; manual Shift/Caps controls are unchanged.
- Spellbook, legacy choice menus, original-art hue picker and death/resurrection prompt.
- General 0xB0 dialogs: original gump images/resizable backgrounds, labels,
  buttons, pages, checkboxes, radio groups and editable fields; 0xB1 replies.
  Item pictures with hues, tiled backgrounds, text hues and scrollable classic
  formatted text (bold/italic/underline, centering, colors and entities) are supported.
- Persistent settings, optional Keychain password, metadata-only telemetry.

## Remaining parity work

- Remaining Travel journal options: nearby chest looting without lockpicking/stealing.
  Track server-confirmed gathered quantities separately from existing inventory,
  including merged stacks. Preserve gold on overload. Do not infer ownership or
  permission to loot merely because a container opens. Bank destinations must be
  editable on the map; transfers must await server confirmation and stop on refusal.
  The gathered-inventory ledger is now implemented: confirmed auto-pickups credit
  only observed added quantities, including merges; reductions, disappearance,
  ownership changes and manual interaction relinquish credit. Gold is excluded
  from overload candidates. Travel journal now saves a default-off "Drop gathered
  excess" option per server/character. Go/resume applies it to that route, waits
  for movement/pickup completion, then drops only credited non-gold quantities at
  the player tile. Source reduction and ground increase must both be confirmed,
  followed by refreshed weight. Refusal/timeout stops the route; manual inventory
  operations wait for the outstanding transfer. Dropped stacks are skipped by
  gathering while still observed. Existing items are never candidates. Reconnect
  clears credits and pending recovery. Nine focused tests and offline UI fixtures
  pass; live overload recovery remains unverified.
  "Bank gathered goods" is now a separate saved option. Its X/Y and map picker
  edit bank destinations independently of town coordinates. Five sourced bank
  landmarks are seeded; other destinations require a user-saved bank point.
  Confirmed route completion requests the bank, verifies player-owned layer 29
  plus a full contents response, and transfers gathered quantities one at a time.
  Unrelated containers, movement, manual Stop, permanent refusal and timeout stop deposits.
  A busy lift refusal (0x27/255) receives at most three delayed retries (2/3/4s),
  only with unchanged source/destination counts. Bank opening and successful
  transfers have a one-second settling pause. Auto-gather requires the movable
  override for non-resource items, avoiding unmarked furniture; classic packets
  do not reliably reveal lockdown/ownership.
  An offline packet-adapter fixture covers arrival, unrelated container rejection,
  a single outstanding deposit and authoritative completion. Live banker reach,
  bank capacity/refusal and old-era banker placement remain unverified. Bank
  planning now accepts reachable adjacent tiles and carries the actual endpoint
  into local replanning. The five seeded inn-to-bank routes pass full static
  collision verification; Jhelom and Skara Brae's exact landmarks are blocked.
  Ordinary map travel retains exact goals. Chest eligibility remains pending:
  local OUO inspection shows theft/lock rules rely on private server tags that
  classic container packets do not expose; opening is not proof of free loot.
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
- Finish the built-in assistant: mining/forge loops and zone controls are implemented,
  but full herding, ore hauling, crafting, output banking and whole-circuit pause
  remain incomplete; see [assistant scope](ASSISTANT.md).
- Xbox rendering/networking/runtime integration and memory/performance validation.

## Local verification snapshot

2026-10-19 typography follow-up: field centering now uses the glyph ink's
baseline-relative bounds rather than height alone. Secure fields center the
password mask glyph. Pixel-based AppKit fixtures verify ordinary and secure
fields at 21/30/44-point heights, with identical glyph bounds before/during
editing and centers within one rendered pixel. All 15 offline UI/packet
fixtures pass in both harness runs. This addresses the low field alignment;
it does not establish full original-menu layout parity.

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

### 2026-10-19 — Separate world-entry deadline
- Sending character creation/play starts a separate 15-second world-entry deadline. Receiving partial game data no longer suffices to dismiss this wait. The final 0x55 entry event or a returned character-selection screen clears it; disconnect also cancels it and invalidates stale generations.
- A stalled entry returns a connection failure explaining that the player should reconnect/select the character again. It does not automatically recreate a character or replay login actions.
- Full core regression: 242 tests, five skips, no failures. New async tests cover one-shot expiry, confirmation/disconnect cancellation and replacement waits. Release build passed. Live slow-server entry still requires validation; existing client remains running.

### 2026-10-19 — Bounded movement position recovery
- Missing position-sync replies now trigger at most two retries, two seconds apart (three requests total). Denied movement registers its immediate sync request with the same recovery state. After the final unanswered wait, travel stops and one message explains that the client is waiting for a server position, with reconnect as a fallback.
- Recovery never fabricates acknowledgement, unlocks prediction on timeout, or disconnects automatically. A late authoritative 0x20 position clears the wait and permits movement; ordinary movement acknowledgements alone do not release it. Timeout produces metadata-only telemetry once per recovery episode.
- Full regression: 245 tests, five skips, no failures. New tests cover missing replies, bounded retries, denied movement, no speculative recovery, late acknowledgement, and late authoritative recovery. Live latency behavior remains unverified and the active session was left running.

### 2026-10-19 — Generated login gems
- Added a generated blank sapphire button resource, bundled with the executable, with runtime bitmap labels and pressed/disabled states.
- Login and shard selection use the gem for Continue/Connect and Back; removed the old login shield backdrop with baked-in button lettering.
- Offline shard transition fixture verifies the asset loads and captures `build/gem-shard-selection.png`; all twelve offline UI fixtures passed. Live server login remains user-testable after relaunch.
- Pending container drag/split now cancels when its source item changes, preserving interactions through unrelated updates; offline regression passed.

### 2026-10-19 — Temporary mobile route obstructions
- Movement denials at a visible mobile's position now use a separate bounded retry budget, a short pause, and two-second obstacle expiry. They no longer exhaust the three static-obstruction retries.
- If no detour exists while a mobile tile is blocked, retain the destination and wait until that temporary block expires before resolving again. No route steps are sent while recovery is pending.
- Four route-recovery tests passed, covering temporary expiry, budget renewal, permanent obstruction limits and authoritative progress. Live animal encounters still require gameplay validation.

### 2026-10-19 — Mobile obstruction integration regression
- Added an offline AppKit fixture that feeds world entry, animal appearance, movement denial, authoritative position correction and animal removal through LoginOverlay's actual packet adapter.
- Verifies immediate prediction, correction, retry pause, retention of the destination when no detour exists, no repeated planning during the wait, and resumed movement after the temporary obstacle expires.
- All thirteen offline UI fixtures passed in both runner passes. This is packet-level local evidence, not proof of every live server obstruction scenario. No client restart was needed for this test-only change.

### 2026-10-19 — Project-wide game-font policy and native editing bridge
- Root AGENTS.md now requires installed game fonts throughout player-facing UI, preserving the approved debug-bar exception and OS-owned chrome.
- Added an in-memory native font built from font 9's original bitmap contours and advances. Native labels, buttons, dropdowns and field editors are themed on window updates; secure fields retain their native secure-entry behavior. No extracted font file is saved or redistributed.
- Removed hard-coded Georgia, Times and system-font declarations from login, character selection/paperdoll, travel fields, quantity and server dialogs. Trade annotations, missing-art markers, journal fallback and formatted gump text now use the shared asset-backed font.
- Added a source-policy gate to the UI runner. The classic UI fixture verifies every Latin-1 advance against fonts.mul, account/password font selection, active account editing and Tab order. Login preview inspected locally; thirteen offline fixtures passed.
- Limitations: the installed font has Latin-1 coverage only. OS fallback can remain for unsupported Unicode, including secure-entry mask glyphs; missing font assets also retain a centralized usability fallback. This pass establishes asset typography across controls, not exact original layout parity for every screen.

### 2026-10-19 — Centered entries and classic saved-server panel
- Shared regular/secure entry cells center the visible glyph line and use consistent field-editor geometry. Fields retain full-height backgrounds, with parchment defaults instead of native rounded bezels.
- Saved-server settings now use an opaque classic stone panel, parchment entries and generated gem actions. Opening settings raises it above the shard selector and constrains its Tab loop; closing restores the underlying flow.
- Converted text-only paperdoll detail, selection, quantity, prompt and server-choice buttons to ClassicButton; original image buttons remain original sprites. Login dropdowns use ClassicChoice. Original container artwork remains intact.
- Added the project-wide controls/panels style rule. Login and saved-settings previews inspected; all thirteen offline UI fixtures passed, including the layering/close-flow assertion, active font editing and inventory interaction checks.
- Exact original layout parity and custom scrollbars/sliders remain follow-up work; this does not claim the entire UI is an exact original-client clone.

### 2026-10-19 — Classic slider and scrollbar rendering
- Shared NSScrollView styling now uses classic sprite thumbs with opaque brown/gold tracks, preserving AppKit scrolling/tracking and reserving content space rather than overlaying native translucent scrollers.
- Quantity sliders draw the original 0x845/0x846 jewel thumb. Native slider tracking and keyboard behavior are retained.
- Sprite IDs checked against the local CrossUO GumpDrag, GumpBaseScroll and GUIHTMLGump references. The installed era lacks later 0xFE/0x100 scrollbar graphics; the available journal thumb 0x1F is used vertically and 0xD8 horizontally.
- Removed native entry bezels restored by convenience initialization. Thirteen offline UI fixtures passed, including original sprite presence, custom cell/scroller classes, scroll offsets, editing and split interaction tests. Quantity/scrollbar previews inspected; exact original scrollbar geometry remains different because native tracking bounds are retained.

### 2026-10-19 — Moving pickups and harvest preview
- Reachable opportunistic pickups no longer use detour enemy-clearance rules or pause ordinary travel waiting for inventory confirmation. Require reach from the current position and every outstanding movement origin/destination; position resynchronization still blocks pickup.
- Detours keep conservative enemy checks. Manual inventory exclusion, weight limits, refusal handling and one outstanding lift remain intact.
- Added packet-adapter regression for an adjacent enemy, pending movement, an actual pickup transaction and continued walking. Four focused core tests and all seventeen offline UI fixtures passed.
- Harvest planning panel previews bounded mining/lumberjacking zones, reachable sites and map-picked centers, scoped to server/character. Original game fonts; screenshot inspected. Preview only: automatic harvesting is not enabled yet.

### 2026-10-19 — Bank deposits prefer existing stacks
- Stackable gathered goods target matching graphic/hue stacks in the player's bank, preferring direct stacks and then known nested containers. Unknown ancestry, cycles, hue mismatches and full stacks are excluded; unmatched goods retain main-bank placement.
- Confirmation watches the selected destination container and source. Busy retries retain their original target and stop if its stack or bank ancestry disappears. Unopened nested contents are not automatically discovered.
- Eleven banking tests and all seventeen offline UI fixtures passed. Live server merge behavior still needs validation.
- Route diagnostic: replaying Minoc (2502,547) to Britain bank (1427,1685) found 1,611 independently collision-validated steps in 0.84s. Skara Brae (591,2142) exceeded both existing search budgets; an experimental 1.5-million-node fallback also failed and was removed. That destination remains unresolved; no slow fallback was shipped.

### 2026-10-19 — Disconnected destinations and failed-click preservation
- After forward route budgets are exhausted, a bounded destination-side search enumerates incoming edges at all static standing elevations. Every edge uses forward collision validation; one-way drops are not treated as climbable. Exhausting this component reports no connected walking route, while hitting its budget remains inconclusive.
- Installed-map regression: Minoc–Britain bank succeeds with 1,611 independently forward-validated steps; Skara inn–bank succeeds with 123. Minoc–Skara bank and inn both exhaust the same 26,866-position destination component, proving these static walking routes are disconnected. Checks took roughly 1.1s, 0.04s and 2.3s respectively.
- Official UO documentation describes the Skara ferry and the “cross” command: https://uo.com/wiki/ultima-online-wiki/beginning-the-adventure/communicating-with-npcs-and-other-commands/ . Ferry interaction/transport automation is not yet implemented; live UO1998 behavior remains unverified.
- Live metadata traced a bank journey cancellation to an unreachable local click at (2486,574). Local approach planning now retains the existing journey until either a direct replacement or a door approach is viable. Invalid/out-of-range/failed roof clicks preserve the previous trip and its bank options. Successful replacements still cancel the previous journey explicitly.
- Reverse-search tests cover directed drops, multiple goal elevations, bounded search, cycles and cancellation. Release build passed. No live character movement was performed for these checks.

### 2026-10-19 — Live bounded zone harvesting
- Harvest planning now has Center on me (current coordinates, chosen radius), Start and Stop. It can drive the existing mining/lumberjacking workflow through collision-checked in-zone routes and server target/result packets, up to 100 successful attempts. Mining accepts a held or directly carried pickaxe/shovel; lumberjacking requires a held axe. Automatic equipping, smelting, crafting and hauling are still pending.
- Requires a known backpack contents baseline; otherwise opens the backpack and asks for Start again. Success requires matching system feedback plus increased resource inventory. Depletion advances to the next discovered site; twenty consecutive skill failures stop the run. Weight headroom, lost tools, nearby enemies, manual actions and disconnect stop automation.
- Stop cancels late target requests; restarting a cancelled working attempt waits ten seconds to avoid consuming its stale cursor as a new request. No automatic restart on reconnect. Zone edits/closing the panel stop the session.
- Eighteen offline UI fixtures passed in both passes, including packet-level harvest confirmation, depletion, stop, manual interruption and danger. Screenshot inspected for game fonts/layout. This enables live testing; UO1998 resource messages and timing still require user validation.
- Follow-up requested: verify classic region/terrain music selection for spawn/reconnect, with server music taking precedence. Not implemented in this change.

### 2026-10-19 — Harvest movement and skipped-site recovery
- Live telemetry confirmed four successful mining gains, then an unreachable stop when changing standing positions. The live route adapter requested radius 66 from an asset reader capped at 64, silently rejecting every movement plan.
- Moved route construction into HarvestSitePlanner.route using radius 64. Installed-map regression now exercises that exact adapter for each distinct standing point as well as independent path validation: 92 mining sites and 23 lumberjacking sites passed.
- Explicit inaccessible-target responses, exhausted local approach retries and approach timeouts advance to another site. Depleted sites continue as before; ownership/tool, weight, danger and general refusal remain whole-session stops. No automatic retry of unknown timed-out tool outcomes.
- Twenty focused core tests and all eighteen offline UI fixtures passed. Region-music work remains pending; local reference evidence identifies optional original regions.txt music assignments, but no music changes are included here.

### 2026-10-19 — Harvest target ownership
- Starting an already-active workflow is rejected before replacing its outstanding tool request. Unexpected target cursors while walking, paused or cooling down cancel the cursor and stop the workflow, rather than silently swallowing it.
- Terminal cursor handling clears the approach route immediately and retains a ten-second late-request window before another run can start.
- Twelve workflow tests and all eighteen offline UI fixtures passed, including unexpected cursors during travel and cooldown and repeated Start while awaiting a tool response. Live movement between sites remains unverified in the newly launched client.

### 2026-10-19 — Original region music lookup
- Added an optional regions.txt reader for the classic 0xFACE/0xFACF formats. Uses inclusive 8×8 block assignment, weatherless regions first and smaller weather-bearing regions overriding larger regions. Zero/unknown tracks produce no playable fallback. Equal-area assignments retain input order; original resource iteration order may differ for tied overlapping regions.
- Local reference: build/ouo/region.c format and weather-data predicate; blockmanager.c region assignment; player.c boundary-driven music sends. This is reference behavior, not evidence that every UO1998 region matches the demo dataset.
- Three focused tests cover town/forest/building precedence, block boundaries, weather-only clearing, old format and invalid records. tools/check_region_music.swift loaded the original installed file and verified Minoc (16), Britain (9) and surrounding forest (27).
- No original region data copied or committed. Playback integration and spawn fallback policy remain pending; this reader alone does not change the running client's music.

### 2026-10-19 — Spawn music playback integration
- The client waits one second after entering the world before applying an optional region track. Any server music event (including silence and death music) suppresses fallback for that connection. Disconnect resets the decision; movement does not repeatedly replace server music.
- Load original region data with `--regions PATH`, or place regions.txt in the installed client directory. The workspace launcher uses the existing local demo regions.txt when available, without copying or committing it. Demo boundaries can differ from UO1998; live server tracks remain authoritative.
- Six region/spawn policy tests passed; release build and launcher syntax check passed. Live audible reconnect validation remains pending. Missing/unknown regional assignments remain silent rather than choosing an arbitrary song.

### 2026-10-19 — Live harvesting recovery verified
- Current-client metadata records depletion at 23:16:41 UTC, travel at 23:16:42 and a successful gain at 23:16:57; further depletion/travel/gain sequences followed. This verifies changing work sites in live UO1998. Several runs now stop at the carrying-weight reserve rather than unreachable routing.
- Fixed the actual panel's repeated Start path: it previously invoked Preview (which cancels the active run) before reaching the adapter's duplicate-start guard. The panel now checks active harvesting before preview or callbacks.
- Weight-reserve, exhausted-route and repeated-failure messages now describe recovery actions. Automatic smelting/hauling remains pending; no server resource-bank dimensions are assumed for skipping neighboring depleted targets.
- All eighteen pre-menu UI fixtures passed, including a repeated Start assertion proving it neither previews nor cancels an active workflow. User's subsequent report was correlated with depletion, advancement to the next target, then cancellation followed immediately by zone preview; the running build predated this panel fix.

### 2026-10-19 — Server menu first-paint layout
- Server icon menus now initialize game fonts and classic scrollbars before first display and composite as a clipped layer. Previously fonts/scrollers could change during a later window update. Icon buttons preserve native proportions instead of stretching to their entire cells; the footer fits its frame and uses a tooltip for cancellation instructions.
- Scrollbars are created only when the options exceed the visible area. Added an offline fixture comparing initial and moved renders byte-for-byte and verifying game fonts and option selection. Screenshot inspected.
- All nineteen offline UI fixtures passed in both passes, including server-menu initial/moved rendering and harvesting controls. Live menu redraw behavior remains for user verification.

### 2026-10-19 — Confirmed harvesting tool equip
- Start prefers an appropriate held tool, then a tool directly in the known backpack. If that tool has an era equipment layer, it sends the normal lift/equip transaction and waits for the matching server equipment update before starting the work zone. Mining retains carried-tool support when no equipment layer exists.
- Refused/unconfirmed equipment changes do not start harvesting. Stop, manual inventory use, disconnect or danger cancels the queued start; a late equipment confirmation may update the paperdoll but cannot restart the run. Unexpected targeting during equip is cancelled.
- Nested unopened bags are not searched. Automatic harvesting still stops with carrying headroom; smelting/crafting/hauling integration remains pending.
- Release build and all nineteen offline UI fixtures passed in both passes, including equip confirmation, refusal and Stop racing a late confirmation. Live auto-equipping remains unverified.

### 2026-10-19 — Smelting result confirmation
- Added SmeltOutcome for one classic ore/forge attempt, derived from the installed era ore.m behavior. Success requires exact system feedback plus an ingot increase in the player's backpack; skill-failure loss requires feedback plus a smaller/changed or removed source pile. Ordinary player chat, other containers and elapsed time cannot confirm success.
- Distinguishes insufficient ore, ownership/in-use refusal and unreachable forge responses. Recognizes the era forge graphic range. No automatic retry or resource-loss prediction.
- Four focused tests passed, covering both message/inventory orders, partial loss, removal, wrong sender/container, timeout, forge graphics and insufficient ore. This is core groundwork; automatic forge navigation and smelting UI/packet adapter remain pending. No live character actions were issued.

### 2026-10-19 — Sequential forge work
- SmeltWorkflow snapshots known backpack ore and an explicit visible forge, issues one ore-use/target attempt at a time, and advances only after correlated results and a cooldown. Insufficient piles are skipped once; metal-loss failure stops instead of repeatedly consuming the remainder.
- Each source must still match its original serial/contents, and the selected forge must remain visible at the same location within classic three-tile reach. Changed sources, unreachable forges, unknown timeouts and manual cancellation cannot replay a use. Late cursors after Stop are cancelled.
- Eight smelting workflow/outcome tests passed. This remains core logic: in-game controls, exclusive target ownership and approach routing are not yet connected, and live smelting is unverified.

### 2026-10-19 — Smelting controls and live adapter
- Harvest planning has Smelt backpack ore. It searches server-visible forges within 24 tiles for a collision-valid adjacent approach, walks without running, then starts sequential confirmed smelting. Unreachable candidates are skipped. Does not search unloaded regions or open a closed-door route to a forge yet.
- Uses the same automation interruption/exclusivity as harvesting: manual action, Stop, disconnect or nearby enemies stop work; automatic pickup is excluded during the approach and smelting. Tool equip pending state cannot overlap. Unknown stopped tool requests retain a bounded late-cursor window before restarting.
- Opens the backpack first if its contents are unknown and asks for Smelt again. Direct backpack ore only. Stops on metal loss, refusal, changed source/forge or unresolved timeout; undersized piles are skipped once.
- Release build and all nineteen offline UI fixtures passed in both passes, including arrival-to-smelt, speech-before-inventory, confirmed completion, cancellation during work and cancelled approach. Updated panel screenshot inspected for game fonts and layout. Live smelting and forge approach remain unverified; automatic mining-to-forge return/crafting loop remains pending.


### 2026-10-19 — Mining circuits and third local login preset
- Mining chooses the shortest reachable remaining site from the current player position and stays at productive sites until depleted. Missing tools trigger backpack spare selection and confirmed equipping while retaining remaining work.
- Harvest planning can remember a visible forge, return near carrying capacity, smelt backpack ore, and resume the saved zone after confirmed ingot gains. Optional exhausted-zone relocation searches neighboring areas, excludes previously visited targets, and stops after a bounded search. Stop/manual movement cancels the circuit. This does not yet bank ingots or handle an impassable/locked forge route automatically.
- Added Local SpacetimeDB at 127.0.0.1:2594 with demo local/local defaults, isolated preferences and Keychain namespace. Select it under Server & saved login, then Connect; the prototype must be started separately with python3 server/local-spacetime/run.py. Existing saved and OUO local profiles are preserved.
- Validation: 14 harvest core tests; 19 offline UI fixtures in both vendor modes, including replacement pickaxe confirmation, ore-to-forge-to-zone lifecycle and three-profile isolation. Screenshots inspected for new controls. The full live mining circuit and new local preset still need live-session verification.

### 2026-10-19 — Mining planner cancellation and zone overlay
- Pending mining searches now track both a request identity and the navigation generation. Stop/manual travel invalidation cancels the detached worker on the movement tick; stale results cannot replace a newer planning task.
- Exhausted-zone relocation redraws the gold boundary using the same terrain elevations as manual preview. Remembered forge coordinates are validated against the installed map before routing.
- Release build and all 19 offline UI fixtures pass in both modes. Added adapter regressions for late forge-arrival and relocation callbacks after cancellation; these prove the callbacks do not restart mining, not end-to-end live route behavior. Running client left untouched; changes apply on its next launch.

### 2026-10-19 — Harvest pause/resume control
- Added an asset-font Pause / resume harvesting button. Pause drains the outstanding tool response or local site approach, retains remaining work, and prevents a completed zone from launching relocation until Resume. Stop still cancels immediately.
- Pause currently applies to harvesting; forge travel, smelting and equipment transactions explicitly direct the player to Stop instead. It is not yet a whole-circuit pause.
- Offline adapter checks cover pausing before a tool request, draining final-site depletion without relocation, resuming relocation and rejecting a second Start while paused. Release build and all 19 offline UI fixtures pass; live pause timing remains unverified.

### 2026-10-19 — Smelting loss recovery and ore consolidation
- Live session 80719 showed confirmed mining gains followed by smelting lost-metal outcomes ending the circuit with noProgress. Missing tool cursors also caused two earlier mining timeouts; those ambiguous requests are not automatically replayed.
- Smelting now retries a confirmed smaller ore remainder after two seconds, with three consecutive failures per pile before advancing. Completely consumed piles advance directly. A completed run with confirmed metal losses can return to the saved mining zone; a one-second action cooldown precedes the return/resume.
- Before smelting, matching backpack ore stacks (same graphic and hue) use the classic ore-use/ore-target interaction. Both a removed source and a survivor increased by the combined quantity must be observed, in either packet order. Different hues and different pile shapes stay separate; cross-shape resource conversion remains unimplemented.
- Added loss retry/limit, merge packet-order, metal mismatch and missing-confirmation regressions. Eleven smelting tests and 19 offline UI fixtures pass. Live merge behavior and successful automatic return remain to be verified; metadata records merge targets, counts and loss counts.

### 2026-10-19 — Mixed ore shapes and approaching work areas
- Session 87883 confirmed an insufficient pile skip, a lost-metal retry, and then a timeout after targeting; no combination was attempted because the two piles had different shapes. That timeout's exact cause remains unproven.
- Ore consolidation now uses the classic mining script's shape units (small 1, medium 2, large 4) and matches hues across shapes. Confirmation requires conserved metal units plus removal of one source; raw item counts are not interchangeable across shapes. New regressions verify both packet orders.
- Start harvesting outside the selected zone now plans a cancellable global approach and starts only after authoritative arrival. Smelt retains nearby visible-forge routing and falls back to the remembered forge when outside the local scan. Starting while a planning/arrival operation is pending is blocked.
- A completed smelt with only undersized leftovers returns to mining when carrying room exists; insufficient carrying room produces an explicit banking message. Timeout telemetry records result-message flags, before/observed ingot totals and source presence, never message text or payloads.
- Installed-map verification finds a 16-step forge-to-Minoc-zone route and checks every step against collision. Twelve smelting core tests and nineteen offline UI fixtures pass, including undersized-leftover return. Mixed-shape combining and automatic zone entry still need live confirmation.

### 2026-10-19 — Live ore circuit confirmed; manual combat interruption
- Session 97647 confirmed two ore merges at 02:14:27–28 UTC, successful smelting at 02:14:29, return travel at 02:14:30, resumed harvesting with 23 remaining sites at 02:14:36, and another confirmed mining gain at 02:14:48. A subsequent forge trip began at 02:16:03. This verifies that sequence on live UO1998, not every ore shape/metal/route.
- Manual war-mode toggles and valid attacks now cancel harvesting/travel immediately rather than waiting for a server combat-target response. Late tool cursors still receive cancellation.
- Release build and all 19 offline UI fixtures pass, including both new manual-combat interruption cases. Active client was left running; combat interruption changes take effect on its next launch.

### Smelting approach and silent inventory confirmation (2026-10-19)
- Start Smelting now prefers the remembered work-area forge and uses the shared world-travel planner, including its door and route recovery, instead of a separate short-range approach. Visible forges remain a fallback when none is remembered. Approach start, arrival and failure are recorded in telemetry.
- Live telemetry showed 14 small ore consumed and ingots increasing from 29 to 36, followed by a timeout with no recognized success message. Smelting now accepts exact same-hue ingot output plus consumption of the selected ore, in either packet order. Moved sources, wrong hues and incorrect output amounts do not confirm success.
- Verification: 14 smelting unit tests and all offline UI fixtures passed. The adapter regression confirms silent conversion returns to the mining zone and resumes tool use. Live verification of the updated approach remains pending.

### Live smelting circuit verification and first-use inventory wait (2026-10-19)
- Session 7290 completed a forge trip with three confirmed ore combinations, three failed smelts, then returned to mining at 02:37:56Z. A later trip at 02:42:24Z confirmed silent conversion (ingots 52→54, source removed, no success message), then routed back at 02:42:25Z. This verifies the prior silent-success fix against live UO1998.
- Start Smelting now opens an unknown backpack and waits up to ten seconds for contents, then continues automatically. A second Start cannot duplicate the request; Stop, timeout and manual interruption prevent late contents from reviving it.
- All offline UI fixtures passed, including packet-driven ready/cancelled/timed-out inventory cases. This inventory-wait change is built but not relaunched yet, to preserve the ongoing live circuit. Assistant documentation now distinguishes shipped mining behavior from remaining herding, hauling, crafting and output-banking work.

### Pause during ore processing (2026-10-19)
- Pause now also applies to ore combining/smelting. An in-flight request continues through its confirmed outcome or timeout; no subsequent ore action or circuit return starts until Resume. Pausing before the first ore use sends no tool request. A failure releases the pause so normal stop handling still runs.
- Offline adapter regressions cover ready-state pause, pausing a live smelt through inventory confirmation, holding return travel until Resume, and timeout while paused. All offline UI fixtures pass. Whole-circuit pause during forge travel and equipment/inventory preparation remains outstanding.
- Live session 7290 continued through multiple forge cycles and reached 66 ingots. A later mining run stopped on missingTool at 02:55:59Z, rather than a smelting timeout.

### Spare tools in carried bags (2026-10-19)
- Session 7290 lost its equipped pickaxe immediately after a successful harvest at 02:55:59Z; the visible root backpack inventory showed no spare mining tool. Breakage is consistent with this sequence, but telemetry does not retain system-message text.
- Tool discovery and carried-tool ownership now follow known nested inventory ancestry to the player's backpack. Direct backpack tools remain preferred; known nested spares can be equipped using the existing confirmed inventory transaction. Unknown ancestors, cycles, removed bags and bank/other roots do not qualify. Unopened bag contents are not guessed or automatically discovered.
- Two ancestry tests and all offline UI fixtures pass. The packet adapter now verifies replacement from a nested carried bag after the equipped tool disappears. Changes are built and queued for the next launch; the user's current session remains running.

### Server dialog texture and typography fidelity (2026-10-19)
- Server `resizepic` edges and center now repeat original texture tiles instead of stretching them. The local CrossUO resizepic implementation confirms repetition semantics; remaining corner-size and transparency behavior still need broader parity work.
- Server text-entry fields explicitly use the asset-derived game font. Bold/italic formatted text now applies stroke/obliqueness to that same font rather than requesting unavailable OS family variants.
- Added the previously standalone server-gump fixture to the regular UI runner. All 20 fixtures pass in both runner modes, including pixel-period checks for center tiling, page switching, choice controls, Unicode replies and formatting attributes. Rendered `build/server-gump.png` was visually inspected. No proprietary assets or generated screenshots were staged; changes await the next client launch.

### Preserve tool cooldown across mining zones (2026-10-19)
- Live session 7290 issued two tool uses only 448 ms apart across depleted-zone relocation at 03:20:13Z. The first received a cursor and depletion result; the second received system speech but no cursor and timed out. The omitted speech text means throttling is an inference, but bypassing the normal one-second action pause is confirmed.
- Circuit resumes now wait one second after arriving in a fresh zone or returning from the forge before starting a new harvest workflow. This retains the normal request pacing even when relocation takes only one tile. Stop/disconnect discards the pending resume; stale callbacks cannot revive it.
- All 20 UI fixtures pass, including cooldown boundaries, cancellation during the delay, forge return and silent-smelt return. Live effectiveness of this pacing change remains to be verified after relaunch.

### Explicit tool-use throttle recovery (2026-10-19)
- The exact system-only action-throttle response now reaches harvesting and smelting as well as door handling. While waiting for the first cursor, it permits at most three retries after 2/3/4-second waits; a fourth refusal stops the action. Ordinary speech, duplicate feedback during cooldown, post-target responses and expired requests cannot trigger a retry. Silence still times out without replay.
- Ore combining revalidates both source snapshots when retrying, and normal smelting revalidates its selected source. Late cursors during the cooldown stop rather than being attributed to a future use. Metadata records workflow and retry count, not message text.
- 26 focused harvesting/smelting tests and all 20 UI fixtures pass. Packet fixtures cover exact system-message classification, pre-target recovery and ignoring post-target throttling. Active session 34150 remains untouched; throttle recovery awaits the next launch.
- Live session 34150 verifies the preceding cross-zone cooldown change: resume waits at 03:47:16Z and 03:48:36Z were followed by mining starts a second later, with continued operation rather than the prior immediate missing-cursor timeout.
