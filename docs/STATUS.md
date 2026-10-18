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
- Secure trade, additional text prompts and remaining server packet handlers.
- Startup music selection when the server sends no music packet; no guessed
  region query or opening-theme fallback is currently used.
- Automation zones/mining/herding are future work, not advertised as implemented.
- Xbox rendering/networking/runtime integration and memory/performance validation.

## Local verification snapshot

2026-10-18: 141 Swift tests executed, 2 opt-in integration tests skipped, no
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
