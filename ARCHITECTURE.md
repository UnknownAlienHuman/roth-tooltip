# Architecture

## Bootstrap and compatibility layers

`RothTooltip.toc` is a strict bootstrap. Safety, policy, the module manager, diagnostics, and style infrastructure load before the legacy core. `Engine/TooltipBootstrap.lua` prevents the legacy 12.0 `TooltipDataProcessor` registration in `Core.lua`. After Core loads, `Engine/Midnight.lua` replaces patch-sensitive access/context/unit/refresh helpers, `Engine/Runtime12_1.lua` applies focused compatibility corrections, and `Engine/TooltipProcessor.lua` installs the only active Retail 12.1 dispatcher.

```text
Engine/Safe.lua
Engine/Policy.lua
Engine/ModuleManager.lua
Engine/Doctor.lua
Engine/Debug.lua
Engine/Style.lua
Engine/TooltipBootstrap.lua
Core.lua
Engine/Midnight.lua
Engine/Runtime12_1.lua
Engine/TooltipProcessor.lua
Config.lua -> General.lua -> feature modules -> XML/locales -> Options.lua
```

## Data boundary

The active runtime flow is:

```text
Blizzard TooltipDataProcessor
  -> Engine/TooltipProcessor.lua
  -> Engine/Midnight.lua sanitizer
  -> weak per-tooltip primitive context
  -> LibEvent.7000 trigger
  -> enabled feature module
  -> safe tooltip/style operation
```

Only ordinary primitive context fields may cross the sanitizer boundary: `type`, `id`, `itemID`, `spellID`, `dataInstanceID`, `hyperlink`, `guid`, and `unitToken`. Raw `TooltipData`, raw `AuraData`, and `TooltipData.args` remain inside the boundary and are never stored or forwarded.

`canaccessvalue`, `canaccessallvalues`, and the relevant `C_Secrets` predicates gate values before branching, comparison, indexing, formatting, storage, logging, or API calls. Restricted enrichment fails closed. `pcall` contains ordinary Lua errors but is not used to probe or declassify data.

## Module system

`Engine/ModuleManager.lua` implements `LibEvent.7000`, module registration, callback attribution, counters, saved enable state, and detach-on-disable behavior. Feature modules subscribe through named events/triggers and are expected to be idempotent.

`General.lua` merges `RothTooltipDB` and optional `RothTooltipCharacterDB`, runs migrations, initializes global styling/status-bar behavior, and emits variables-loaded triggers. `Options.lua` writes Settings proxies and replays the same module/style paths.

## Runtime ownership

Addon bookkeeping is held in addon-owned tables rather than Blizzard frame fields:

- sanitized context: weak table in `Engine/Midnight.lua`;
- anchor ticker state: weak table in `Anchor.lua`;
- achievement hook state: weak table in `LinkID.lua`;
- mount tooltip state: weak table in `Mount.lua`;
- 3D model: module-owned frame parented to `UIParent`.

`Engine/Style.lua` intentionally attaches the visual `__RTStyle` hierarchy to managed tooltips. It is the rendering layer, not a general state cache.

## Refresh model

Modifier, item-cache, and inspect refreshes reopen a visible managed tooltip only from an accessible ordinary unit token, hyperlink, or spell ID. The addon does not cache/replay restricted raw payload and does not use `RebuildFromTooltipInfo` as a fallback.

## External dependencies

The TOC declares no required external addon. `Engine/ModuleManager.lua` provides the local event bus and minimal LibStub fallback. LibSharedMedia is optional and is consumed when available.
