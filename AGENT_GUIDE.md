# RothTooltip agent guide

## Start here

Read [`RothTooltip.toc`](RothTooltip.toc), [`Engine/ModuleManager.lua`](Engine/ModuleManager.lua), [`Core.lua`](Core.lua), [`General.lua`](General.lua), [`Engine/Style.lua`](Engine/Style.lua), and [`Options.lua`](Options.lua). This is a modular event/trigger system, not a flat collection of tooltip hooks.

TOC release metadata is `12.0.20` (`RothTooltip.toc`, `## Version`).

## Load order and execution path

Complete `loadedFiles` inventory (root `docs/addon-architecture.json`, in execution order; XML entries are expanded):

```text
libs/lib.xml
Engine/Safe.lua
Engine/Policy.lua
Engine/ModuleManager.lua
Engine/Doctor.lua
Engine/Debug.lua
Engine/Style.lua
Core.lua
Compat_MoneyFrame.lua
Config.lua
General.lua
Anchor.lua
Target.lua
Unit.lua
Model.lua
Item.lua
Spell.lua
Quest.lua
LinkID.lua
Mount.lua
ExpansionInfo.lua
SkinFrames.lua
libs/Template.xml
locales/locales.xml
locales/enUS.lua
locales/zhTW.lua
locales/zhCN.lua
locales/ruRU.lua
Options.lua
```

The TOC loads empty [`libs/lib.xml`](libs/lib.xml), then `Engine/Safe.lua`, `Policy.lua`, `ModuleManager.lua`, `Doctor.lua`, `Debug.lua`, `Style.lua`, `Core.lua`, `Compat_MoneyFrame.lua`, `Config.lua`, feature modules (`General`, `Anchor`, `Target`, `Unit`, `Model`, `Item`, `Spell`, `Quest`, `LinkID`, `Mount`, `ExpansionInfo`, `SkinFrames`), [`libs/Template.xml`](libs/Template.xml), locale XML, and `Options.lua` last. `ModuleManager.lua` creates the local `LibEvent.7000` bus (with a minimal LibStub fallback), owns module registration, callback attribution, detach-on-disable, and saved module state.

`Core.lua` builds the secret-safe context pipeline: `InitTooltipDataProcessor` dispatches Blizzard `TooltipDataProcessor` types into `tooltip:item`, `tooltip:spell`, `tooltip:unit`, `tooltip:aura`, and generic ID triggers; it caches context on each tooltip and calls `RefreshTooltipSafe`. `Engine/Style.lua` creates per-tooltip `__RTStyle`, hides Blizzard background regions, and hooks `OnShow`, `OnHide`, and `OnTooltipCleared`. Feature modules register with `addon.MM:RegisterModule` and subscribe through `MM:AttachTrigger`/`MM:AttachEvent`.

`General.lua` loads/merges account and optional character SavedVariables, runs migrations, and emits `tooltip:variables:loaded`/`ROTHTOOLTIP_GENERAL_INIT`. `Options.lua` registers Settings categories and proxy settings, triggers variable/style events, and registers slash aliases.

## State and user surfaces

- Account DB: `RothTooltipDB`; character DB: `RothTooltipCharacterDB`; the TOC declares both, and `general.SavedVariablesPerCharacter` selects the active merge store.
- Config roots: `general`, `unit.player`, `unit.npc`, `item`, `spell`, `quest`, `model`, `modules`, `variables`; module state is persisted in `db.modules` and core `General` is forced on.
- Settings: root `Roth Tooltip` category with Player/NPC/StatusBar/Spell/Fonts/Modules/Data subcategories; profile import/export/reset and DIY layout editor live in `Options.lua`/`libs/Template.xml`.
- Slash: `/tinytooltip`, `/tt`, `/tip`; commands include `reset`, `npc`, `npc-elements`, `player`, `player-elements`, `spell`, `statusbar`, `font`, `modules`, `data`.
- Diagnostic surfaces: `Engine/Doctor.lua` captures protected/forbidden and LibEvent callback errors; `Engine/Debug.lua:115-116` registers `/rtt` and exposes `help`, `errors`, `export`, `modules`, `enable <name>`, `disable <name>`, `toggle <name>`, and `clear`. Settings aliases remain `/tinytooltip`, `/tt`, and `/tip` in `Options.lua`.

## Module map and relationships

`General` initializes DB and core styling. `Anchor` controls cursor/static anchoring. `Target` and `Unit` enrich unit tooltips (inspect cache, class/reaction/role/faction/raid/friend data). `Model` adds model display. `Item`, `Spell`, `Quest`, `LinkID`, `Mount`, and `ExpansionInfo` subscribe to item/spell/aura/generic tooltip triggers. `SkinFrames` handles additional Blizzard frame skinning. `Compat_MoneyFrame` wraps `SetTooltipMoney` only for detected secret-value errors. Locales feed Options labels. LibSharedMedia is optional at runtime and is consumed by `Core.lua`/`Engine/Style.lua` for fonts/backgrounds/borders/statusbars; no external addon is required by the TOC.

## Change routing

- Context extraction, TooltipDataProcessor registrations, safe refresh, generic IDs: [`Core.lua`](Core.lua).
- Event/trigger registration, module enable/disable, callback stats and detach: [`Engine/ModuleManager.lua`](Engine/ModuleManager.lua).
- Secret-value guards and policy: [`Engine/Safe.lua`](Engine/Safe.lua), [`Engine/Policy.lua`](Engine/Policy.lua), plus `addon:IsSecret`/`SafeCallBoolean` in `Core.lua`.
- Visual frame construction and style triggers: [`Engine/Style.lua`](Engine/Style.lua).
- DB merge/migrations and general status bar/tooltip behavior: [`General.lua`](General.lua), [`Config.lua`](Config.lua).
- Feature-specific behavior: edit only the matching module file; preserve its `MM:RegisterModule` contract and trigger names.
- Settings/profile/import/reset and slash routing: [`Options.lua`](Options.lua), [`libs/Template.xml`](libs/Template.xml), [`locales/`](locales/).
- Taint/secret money compatibility: [`Compat_MoneyFrame.lua`](Compat_MoneyFrame.lua); keep the error filter narrowly limited to secret-value failures.

## Invariants and risks

- Never boolean-test, concatenate, pattern-match, or arithmetic-operate on a potentially secret WoW value before `addon:IsSecret`/safe wrapper checks. Tooltip and unit data are patch-sensitive.
- `TooltipDataProcessor` post-callbacks and `LibEvent` callbacks may be invoked repeatedly; handlers must be idempotent and use `FindLine`/per-tooltip markers to avoid duplicate lines.
- `ModuleManager` core `General` is forced enabled. Disabling a module must detach all tracked trigger/event links; bypassing MM leaks hooks and defeats diagnostics.
- `Engine/Style.lua` hides Blizzard background textures and writes protected-looking tooltip frame properties. Verify `ADDON_ACTION_BLOCKED`, forbidden frames, and combat behavior after style changes.
- Unit inspect requests are asynchronous (`INSPECT_READY`) and cached for 300 seconds; invalidate/refresh only through the existing path.
- Settings proxy writes can affect account or character DB based on `SavedVariablesPerCharacter`; profile import must preserve schema/version and never import untrusted secret values.
- Falsification notes: there is no `COMBAT_LOG_EVENT_UNFILTERED` registration, no Masque or CDM integration, and no addon-wide updater loop. There are narrowly scoped `OnUpdate` scripts for the model display (`Model.lua:73`) and layout editor (`Options.lua:1090`); do not mistake those for the tooltip event pipeline.

## Verification

1. Verify TOC/XML load order and that every XML `<Script>`/template reference exists.
2. Parse Lua and run Markdown/link checks.
3. In-game `/reload`; open each Settings category and test `/tt`, `/tinytooltip`, `/tip` subcommands.
4. Exercise item, spell, unit, aura, quest, mount, link-ID, model and frame tooltips; test cursor/static anchoring and modifier changes.
5. Test account/character profile switching, import/export/reset, module toggles and reapply behavior.
6. Test inspect completion (`INSPECT_READY`), on-demand Blizzard tooltip loading (`ADDON_LOADED`), money-frame compatibility, combat/forbidden frames, and Doctor error/taint output.

## Uncertain or version-sensitive claims

`Enum.TooltipDataType`, Blizzard tooltip frame names, `TooltipDataProcessor`, secret-value behavior, and Settings proxy APIs are client-build sensitive. The empty `libs/lib.xml` means no bundled external library files are declared there; LibEvent is implemented by `ModuleManager`, while LibSharedMedia is optional. Confirm any API or frame name against the current Blizzard UI source before changing a hook.
