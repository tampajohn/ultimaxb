# UltimaXB project rules

## Game typography

All player-facing UI must use fonts from the installed Ultima Online assets.
This applies to login/shard/character creation, editable and secure fields,
dropdown menus, status and skills, containers and quantities, paperdolls,
chat/journal, overhead names, vendors/trade, maps and server dialogs.

- Draw game text with `ClassicText`, `ClassicLabel`, `ClassicButton` and
  `ClassicChoice`, preserving the appropriate era font and hue.
- Native editing controls must use `ClassicNativeFont`, generated in memory
  from the installed game glyphs. Retain keyboard selection, tab order,
  secure password behavior and accessibility. Do not introduce Georgia,
  Times, SF or other substitute typefaces for normal game UI.
- System-font fallback is permitted only when the asset font is unavailable
  or a required glyph is outside the installed font repertoire. Track those
  limitations explicitly; never claim a fallback matches the original.
- The bottom developer/debug bar is an explicit user-approved exception.
  OS-owned dialogs and the macOS application menu are also outside game art.
- Verify new/changed screens in both display and editing states, with long
  labels and validation messages; check clipping and text contrast.
- Do not embed replacement labels over lettering baked into an art sprite.
- Preserve original assets. Never commit extracted proprietary font data.
