# Code index

| Area | Files | Exact anchors |
| --- | --- | --- |
| Context/bootstrap | [`Core.lua`](Core.lua), [`General.lua`](General.lua) | `InitTooltipDataProcessor`, `GetPrimaryTooltipContext`, `RefreshTooltipSafe`, `InitOnce`, `MergeVariable` |
| Engine | [`Engine/ModuleManager.lua`](Engine/ModuleManager.lua), [`Engine/Safe.lua`](Engine/Safe.lua), [`Engine/Policy.lua`](Engine/Policy.lua), [`Engine/Style.lua`](Engine/Style.lua), [`Engine/Doctor.lua`](Engine/Doctor.lua), [`Engine/Debug.lua`](Engine/Debug.lua) | `RegisterModule`, `AttachTrigger`, `AttachEvent`, `ApplySaved`, `tooltip.style.*`, `InitDoctor` |
| Feature modules | [`Anchor.lua`](Anchor.lua), [`Target.lua`](Target.lua), [`Unit.lua`](Unit.lua), [`Model.lua`](Model.lua), [`Item.lua`](Item.lua), [`Spell.lua`](Spell.lua), [`Quest.lua`](Quest.lua), [`LinkID.lua`](LinkID.lua), [`Mount.lua`](Mount.lua), [`ExpansionInfo.lua`](ExpansionInfo.lua), [`SkinFrames.lua`](SkinFrames.lua) | each `M:Init`/`M:Enable` and `MM:RegisterModule` |
| Configuration | [`Config.lua`](Config.lua), [`Options.lua`](Options.lua) | `addon.db`, `TryInitializeOptions`, `SlashCmdList.RothTooltip`, proxy setting writers |
| Compatibility/locales | [`Compat_MoneyFrame.lua`](Compat_MoneyFrame.lua), [`locales/`](locales/), [`libs/Template.xml`](libs/Template.xml) | narrow money wrapper, locale and import/export template |

No feature module should bypass `ModuleManager` or write tooltip styles directly without a named trigger.
