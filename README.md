# Roth Tooltip

Modular tooltip customisation addon with configuration, style, anchoring, item/spell/unit/quest/mount data modules, locale files, and a built-in diagnostic surface.

**Version:** 12.0.20
**Interface:** 120001, 120005
**SavedVariables:** `RothTooltipDB`, `RothTooltipCharacterDB`

## Install

Copy `RothTooltip` to `World of Warcraft/_retail_/Interface/AddOns/`, enable it, and reload the UI.

## Use

Open settings with `/tinytooltip`, `/tt`, or `/tip`. The checked-in settings slash handler supports `reset`, `npc`, `npc-elements`, `player`, `player-elements`, `spell`, `statusbar`, `font`, `modules`, and `data`. The diagnostic handler in [`Engine/Debug.lua`](Engine/Debug.lua) registers `/rtt` and supports `help`, `errors`, `export`, `modules`, `enable <name>`, `disable <name>`, `toggle <name>`, and `clear`.

## Current development status

The recorded incident fix changes the unit-tooltip refresh path to prioritise safe `SetUnit()` / `SetHyperlink()` reopening and blocks the unit fallback to `RebuildFromTooltipInfo()` when safe refresh fails. Remaining work is live in-game verification of reload, modifier changes, inspect completion, and applying/reapplying profiles without the cited errors. See [todo.md](todo.md).

## License

Licensed under the [MIT License](LICENSE). Bundled third-party components remain under their own notices.
