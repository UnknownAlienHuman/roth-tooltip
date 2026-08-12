# Architecture

The TOC is a strict bootstrap: empty `libs/lib.xml`, Engine safety/policy/module manager/doctor/debug/style, `Core.lua`, money compatibility, `Config.lua`, `General.lua`, feature modules, XML template/locales, and `Options.lua`. `Engine/ModuleManager.lua` creates the `LibEvent.7000` bus, registers modules, tracks callback metrics, and detaches module hooks when disabled.

Runtime flow is `TooltipDataProcessor` post-call -> `Core.lua` context normalization and secret checks -> LibEvent triggers (`tooltip:item`, `tooltip:spell`, `tooltip:unit`, `tooltip:aura`, generic IDs) -> enabled feature modules -> `Engine/Style.lua` style/anchor/data updates. `General.lua` merges `RothTooltipDB` and `RothTooltipCharacterDB`, emits variables-loaded triggers, and applies global style. `Options.lua` writes proxy settings and replays the same trigger path.

The addon's primary persistent state is the account/character DB pair plus `db.modules`; `General` is core and cannot be disabled. LibSharedMedia is optional; the TOC has no external dependency declaration.
