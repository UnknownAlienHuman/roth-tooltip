# Code index

| Area | Files | Responsibility |
| --- | --- | --- |
| Bootstrap | `Core.lua`, `General.lua` | initialization, SavedVariables merge/migration, general tooltip behaviour |
| Engine | `Engine/` | module event manager, safety/policy, diagnosis, debug UI, style |
| Tooltip features | `Anchor.lua`, `Target.lua`, `Unit.lua`, `Item.lua`, `Spell.lua`, `Quest.lua`, `Mount.lua`, `Model.lua`, `LinkID.lua`, `ExpansionInfo.lua`, `SkinFrames.lua` | specialised tooltip extensions |
| Configuration | `Config.lua`, `Options.lua` | defaults and Settings UI/slash commands |
| Compatibility and localisation | `Compat_MoneyFrame.lua`, `locales/`, `libs/` | compatibility path, translations, bundled libraries |

Primary anchors: `RefreshTooltipSafe`, `TryInitializeOptions`, `SlashCmdList.RothTooltip`, and the ModuleManager event attachment path.
