# Code index

| Area | Files | Exact anchors / responsibility |
| --- | --- | --- |
| Bootstrap | [`RothTooltip.toc`](RothTooltip.toc), [`Engine/TooltipBootstrap.lua`](Engine/TooltipBootstrap.lua) | strict load order; disables the legacy Core processor before Core loads |
| Retail 12.1 data boundary | [`Engine/Midnight.lua`](Engine/Midnight.lua), [`Engine/Runtime12_1.lua`](Engine/Runtime12_1.lua), [`Engine/TooltipProcessor.lua`](Engine/TooltipProcessor.lua) | `CanAccessValue`, `IsObjectAccessible`, `GetPrimaryTooltipContext`, `RefreshTooltipSafe`, `InitTooltipDataProcessor` |
| Safety and policy | [`Engine/Safe.lua`](Engine/Safe.lua), [`Engine/Policy.lua`](Engine/Policy.lua) | `SafeCall`, `SafeGet`, `SafeMethod`, `AllowTrigger`, C_Secrets-aware fail-closed policy |
| Event/module runtime | [`Engine/ModuleManager.lua`](Engine/ModuleManager.lua) | `LibEvent.7000`, `RegisterModule`, `AttachTrigger`, `AttachEvent`, detach/state/metrics |
| Legacy shared helpers | [`Core.lua`](Core.lua) | formatting, colors, filters, style/anchor/status-bar triggers; patch-sensitive public helpers are overridden later |
| Visual engine | [`Engine/Style.lua`](Engine/Style.lua) | managed `__RTStyle` hierarchy, Blizzard-region suppression, `tooltip.style.*` triggers |
| DB and global behavior | [`Config.lua`](Config.lua), [`General.lua`](General.lua) | defaults, `MergeVariable`, migrations, status bar, variables-loaded triggers |
| Unit surfaces | [`Anchor.lua`](Anchor.lua), [`Target.lua`](Target.lua), [`Unit.lua`](Unit.lua), [`Model.lua`](Model.lua) | cursor/static ownership, target line, unit/inspect/M+/raid fields, isolated `PlayerModel` |
| Item/spell data | [`Item.lua`](Item.lua), [`Spell.lua`](Spell.lua), [`Quest.lua`](Quest.lua), [`Mount.lua`](Mount.lua), [`ExpansionInfo.lua`](ExpansionInfo.lua) | item/spell/quest enrichment, cached mount source, expansion metadata |
| IDs and extra frames | [`LinkID.lua`](LinkID.lua), [`SkinFrames.lua`](SkinFrames.lua) | sanitized item/spell/aura/unit/generic IDs; additional managed tooltip registration |
| Settings and locales | [`Options.lua`](Options.lua), [`libs/Template.xml`](libs/Template.xml), [`locales/`](locales/) | Settings categories, profile import/export/reset, DIY layout, slash routing, labels |
| Diagnostics | [`Engine/Doctor.lua`](Engine/Doctor.lua), [`Engine/Debug.lua`](Engine/Debug.lua) | callback error attribution, `/rtt`, error export, module diagnostics |

## Boundary rules

- `Engine/TooltipProcessor.lua` is the only active `TooltipDataProcessor` dispatcher.
- Raw `TooltipData`, raw `AuraData`, and `TooltipData.args` do not cross into feature modules.
- Values must pass access and relevant `C_Secrets` gates before use.
- Feature modules subscribe through `ModuleManager`; they do not install parallel dispatcher pipelines.
- Addon bookkeeping belongs in addon-owned tables, not arbitrary Blizzard frame fields.
- The removed `Compat_MoneyFrame.lua` wrapper is not part of the 12.1 runtime.
