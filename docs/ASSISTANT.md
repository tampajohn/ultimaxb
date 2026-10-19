# Built-in assistant goal

Automated mining and herding are explicit parts of the UltimaXB goal, alongside
classic-client playability. This document describes required work, not shipped
features. Original Xbox support remains a later target.

## Reference behavior

[UOAssist's macro documentation](https://www.tugsoft.com/uoassist/help/macropage)
describes recording/replaying skill use, spells, speech, item use and targeting,
editable pauses, and replacing a specific item with an item-type action.
Use that interaction model as a reference for a native assistant. UOAssist's
documented macro feature does not itself provide continuous repetition; zone-based
mining and herding are additional requested UltimaXB workflows.

## Required capabilities

- Travel options, independently saved per server/character: loot eligible nearby
  chests without lockpicking/stealing; drop newly gathered non-gold goods when
  overloaded; visit a town bank and unload gathered goods. Bank points must be
  editable through the world map. Opening a chest does not establish permission
  to take its contents. Preserve pre-existing belongings when stacks merge.
- Named, editable action sequences and hotkeys, with record/play support for
  supported game actions. Capture game actions, never raw keyboard input,
  passwords or unrelated UI activity.
- Reusable actions for using an item or item type, using a skill, casting a spell,
  selecting a target, waiting for a target/server result, pausing, and routing.
- Visible start, pause, resume and stop controls; immediate manual interruption.
  Show the current action and why a sequence is waiting or stopped.
- User-selected zones with overlays, selected targets and dotted planned routes.
  Automation must remain within its selected zone.
- Mining: select tool and work area, reach usable mining positions, perform the
  tool/target sequence, and advance after resource depletion or invalid targets.
  Handle broken/missing tools, weight, stamina, movement refusal and interrupted
  actions without repeatedly issuing failed commands.
- Herding: select eligible animals and a destination/zone, use the shepherd's
  crook and its target sequence, and handle moving, missing or unreachable animals.
- Ore hauling to a selected forge while overloaded: intentionally drop selected
  mined ore, walk a short reachable segment while keeping it within pickup range,
  pick it up, and repeat toward the forge. Confirm each inventory/world change
  before the next step; stop on refusal, changed ownership/serial, disappearance,
  blocked movement or disconnect. Show the ore location and recovery action.
  This requested workflow permits temporary ground placement of selected ore;
  it does not authorize discarding other belongings or automatic selling.
- Explicit handling for inventory destinations and full containers.
- Save workflow and zone configuration with character/server scope. Clear pending
  targets and stop execution on disconnect; reconnect must not silently resume.
- Bounded retries, server-response waits and timeouts. Use the same authoritative
  movement, targeting and inventory paths as manual play.
- Metadata-only telemetry for workflow state, action type, target IDs, counts,
  timings and stop reasons. No speech text, credentials or private packet payloads.

## Verification and current test boundaries

Test state transitions with deterministic packet fixtures: normal completion,
depletion, stale/replaced targets, failed movement, overweight, tool disappearance,
pause/stop, disconnect and timeouts. Then verify controlled live workflows.

The user currently permits character automation within Minoc or the nearby mining
mountains. That permission does not expand a selected workflow zone or authorize
wandering elsewhere. Keep one client running and avoid interrupting active manual
play for routine tests.

## Implementation order

1. Shared action runner with cancellation and server-driven waits.
2. Single-location mining workflow and visible controls.
3. Zone selection, route display and bounded mining traversal.
4. Herding workflow using the same runner.
5. Macro editing/recording, reusable profiles and additional skills.

### Banking implementation evidence (2026-10-19)

`GatheredBanking` implements the deposit state machine, now wired to Travel
and the game packet adapter. It requires an equipment entry owned by the player on layer
29, a matching open-container event and a full contents response before choosing
goods. Each transfer waits for both source reduction and destination increase;
moving, losing bank identity, refusal and timeout stop execution. It never sends
the next deposit from the same confirmation call. Thirteen focused gathering,
overload and banking tests pass. An additional offline adapter fixture verifies
arrival, bank identity/contents, deposit serialization and inventory confirmation.
Travel settings persist bank points independently of town coordinates, with map
editing and a separate default-off banking switch. Live opening/deposit behavior
and landmark approach tiles remain unverified.

The local OUO reference `build/ouo/mobile.c`, `CMobile_OpenBankGump`, sends the
bank entity, open-gump packet and contents in that order. `build/ouo/packet_handler.c`
checks `bankOpenLoc` on deposits and revokes access if the player's location
changed. Preserve that exact-position constraint in the client adapter.

Official town pages provide initial bank landmarks, not verified reachable
standing tiles for this older asset/server combination:

- [Minoc bank](https://uo.com/wiki/ultima-online-wiki/world/cities-and-towns/cities-and-towns-minoc/): 2503, 554.
- [Britain west bank](https://uo.com/wiki/ultima-online-wiki/world/cities-and-towns/cities-and-towns-britain/): 1427, 1685; east bank: 1653, 1605.
- [Vesper mint](https://uo.com/wiki/ultima-online-wiki/world/cities-and-towns/cities-and-towns-vesper/): 2880, 683.
- [Jhelom bank](https://uo.com/wiki/ultima-online-wiki/world/cities-and-towns/cities-and-towns-jhelom/): 1319, 3775.
- [Skara Brae bank](https://uo.com/wiki/ultima-online-wiki/world/cities-and-towns/cities-and-towns-skara-brae/): 591, 2142.

Validate approach tiles against installed collision data and banker reach. Do not
substitute town inn coordinates for bank arrival or infer bank identity from art.

`tools/check_bank_routes.swift` now verifies full collision-valid static routes
from all five seeded town inns to reachable bank-adjacent tiles in the installed
1.25.32 map. Jhelom and Skara Brae's exact published landmarks are blocked, so
bank travel uses adjacent-goal planning and carries the chosen endpoint through
local replanning. Normal map travel still requires its exact destination. This
does not verify live banker range, access, dynamic doors or island crossings.

### Chest eligibility findings (2026-10-19)

The local OUO reference prevents reliable theft-free inference from ordinary
container packets. `CContainer_HasAccessibleContents_VT` in `container.c` checks
the private `isLocked` tag. Independently, `HandlePacket_REQ_GETOBJ` in
`packet_handler.c` classifies pickup as stealing when either the item or parent
is at home, when the top container belongs to another mobile, or when the private
`overloadStealing` tag overrides the decision. `CEntity_IsAtHome` in `item.c`
depends on private home-location and city/justice-region data. Packet builders
for 0x25/0x3C send item art, quantity, coordinates, container serial and hue; they
do not expose those theft rules. An unlocked/opened/movable chest is therefore
insufficient evidence. Automatic chest looting remains unimplemented pending a
reliable ownership/loot-permission source; do not probe by attempting a theft.

The first tool-action state machine is implemented and locally tested. It emits one
use-item command, waits for one or two target requests, validates target compatibility,
then waits for an explicitly correlated result. Refusal, depletion, manual stop,
disconnect, missing tool, overweight and timeout stop the attempt. Late target
requests for a stopped attempt produce cancellation, never a target selection.
Tests cover object-then-location targeting even when the server reuses its cursor ID.

No live workflow is connected yet. The adapter must correlate result events and
route only the owned target stream to this action; it must also handle target
handoff after cancellation so unrelated manual actions are not consumed. Exact
duplicate target requests stop the action; same-type cursor reuse across multiple
phases needs additional protocol evidence. Repetition, pause/resume, zones, tool
selection and visible controls are still required. Current manual tools are
foundations, not evidence of automation parity.

Ore hauling now has a locally tested single-stack state machine: confirmed drop at
the current tile, one acknowledged route step, confirmed pickup, then repeat.
Both transfer acknowledgement and exact destination state are required. Changed
amount/art/hue/container, displaced ore, timeout, refusal or manual interruption
stop the sequence. Recovery location continues to update if a late drop arrives
after cancellation. Route steps remain within one tile and 16 Z of the prior
position, preserving pickup reach.

Live integration is still required: ore selection, forge selection and route
planning, exclusive transfer ownership/acknowledgement routing, visible controls,
recovery display, handling other heavy stacks, and interaction with smelting.
The runner does not discover forges or execute packets itself. No live ore was
dropped by these tests.

## Travel and opportunistic gathering

The requested travel journal and nearby-item gathering are now initial runnable
workflows. Select a town or edit its coordinates (Pick on map), then Go/resume;
Stop or manual movement ends travel. Destinations are scoped to server/character.
Source city positions and limitations are recorded in STATUS.md. No travel resumes
on reconnect, and tests have not moved the user's character outside Minoc.

Gather is a session-only sidebar toggle: reagents, or all portable ground items (asset weight below the immovable sentinel). It does not loot corpses or open containers, detour,
sell, or drop belongings. Transfer confirmation and bounded timeout prevent overlapping moves. Server refusals skip the current item without disabling gathering; weight guards pause or skip oversized stacks. Timeout and disconnect still stop gathering. Full zone mining/herding and the broader macro runner remain
separate unfinished requirements. The UI overhaul remains active for other dialogs.
