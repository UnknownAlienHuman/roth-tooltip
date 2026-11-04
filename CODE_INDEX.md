# Code index

[Architecture and ownership](ARCHITECTURE.md) is the canonical map. [RothTooltip.toc](RothTooltip.toc) is the canonical load order.

| Change | Entry point |
| --- | --- |
| access, policy, result tuples | [Safe](Engine/Safe.lua), [Policy](Engine/Policy.lua) |
| subscriptions and module transitions | [ModuleManager](Engine/ModuleManager.lua) |
| tooltip normalization, registration and dispatch | [Midnight](Engine/Midnight.lua), [Registry](Engine/TooltipRegistry.lua), [Processor](Engine/TooltipProcessor.lua) |
| formatting, filters and rendering | [Core](Core.lua), [Style](Engine/Style.lua) |
| profiles, defaults and status bar | [General](General.lua), [Config](Config.lua), [schema](Engine/Profile.lua) |
| unit/target/model/anchor behavior | [Unit](Unit.lua), [metadata](Engine/UnitInfo.lua), [enrichment](Engine/UnitStats.lua), [Target](Target.lua), [Model](Model.lua), [Anchor](Anchor.lua) |
| item/spell/quest/mount/expansion enrichment | [Item](Item.lua), [Spell](Spell.lua), [Quest](Quest.lua), [Mount](Mount.lua), [ExpansionInfo](ExpansionInfo.lua) |
| IDs and optional frames | [LinkID](LinkID.lua), [SkinFrames](SkinFrames.lua) |
| Settings, profiles and DIY controls | [Options](Options.lua), [mutations](Options/Core.lua), [profiles](Options/Profile.lua), [DIY](Options/DIY.lua) |
| errors and slash diagnostics | [Doctor](Engine/Doctor.lua), [Debug](Engine/Debug.lua) |
| executable regressions and client gates | [tests](tests/README.md) |
