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
- Explicit handling for inventory destinations and full containers. Do not silently
  discard resources or sell belongings as a workaround for weight limits.
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

No assistant workflow is implemented yet. Current manual tool shortcuts, targeting,
routing and inventory operations are foundations, not evidence of automation parity.
