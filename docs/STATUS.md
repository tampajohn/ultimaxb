# Status

The goal is full chosen-era playability on macOS, then evaluation of an original
Xbox port. The present client is experimental and is not at parity yet.

## Implemented, with live shard testing still ongoing

- Login, shard/character selection, reconnect, creation stats/skills/appearance.
- Terrain/statics, mobiles/equipment/hair, hues, multicomponent houses/boats,
  roof cutaways, interpolated movement and server reconciliation.
- Inventory, stack splitting, equip/unequip, ground pickup/drop and paperdoll.
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
- Automation zones/mining/herding are future work, not advertised as implemented.
- Xbox rendering/networking/runtime integration and memory/performance validation.

## Local verification snapshot

2026-10-18: 155 Swift tests executed, 2 opt-in integration tests skipped, no
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
trades have not been tested. Trade-item drag previews, partial-stack removal and
opening offered nested bags remain incomplete.

Trade transfer ordering: acceptance now waits for both DROPOBJ_OK and an item
update at the requested destination (or the merged destination stack). Removal
from the old container alone cannot unlock acceptance. Pickup rejection releases
the guard, while a failed drop waits for the returned item's authoritative ground
location. Reordered acknowledgement/update and merge fixtures pass. If a shard
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
