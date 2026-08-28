# Code index

| Area | Files | Responsibility |
| --- | --- | --- |
| Manifest and load order | [`RothTooltip.toc`](RothTooltip.toc) | Retail 12.1 metadata and single-runtime load order |
| Value/object safety | [`Engine/Safe.lua`](Engine/Safe.lua), [`Engine/Policy.lua`](Engine/Policy.lua) | capability gates, forbidden aspects, safe calls, combat/restriction policy |
| Module/event runtime | [`Engine/ModuleManager.lua`](Engine/ModuleManager.lua) | `LibEvent.7000`, module lifecycle, detach/state/metrics |
| Shared helpers | [`Core.lua`](Core.lua) | DB merge, formatting, colors, filters, media, named style/anchor/status-bar triggers |
| Retail data boundary | [`Engine/Midnight.lua`](Engine/Midnight.lua) | `C_Secrets`, primitive context, unit/owner helpers, safe refresh and line access |
| Managed tooltip registry | [`Engine/TooltipRegistry.lua`](Engine/TooltipRegistry.lua) | early frame registration and restriction-transition invalidation |
| Tooltip dispatch | [`Engine/TooltipProcessor.lua`](Engine/TooltipProcessor.lua) | the only active `TooltipDataProcessor` post-call bridge |
| Visual engine | [`Engine/Style.lua`](Engine/Style.lua) | addon-owned regions, known Blizzard visual suppression, `tooltip.style.*` triggers |
| DB and global behavior | [`Config.lua`](Config.lua), [`General.lua`](General.lua) | defaults/schema, migrations, status-bar and variables-loaded behavior |
| Unit surfaces | [`Anchor.lua`](Anchor.lua), [`Target.lua`](Target.lua), [`Unit.lua`](Unit.lua), [`Model.lua`](Model.lua) | anchoring, target line, unit/inspect/M+/raid enrichment, isolated model |
| Item/spell surfaces | [`Item.lua`](Item.lua), [`Spell.lua`](Spell.lua), [`Quest.lua`](Quest.lua), [`Mount.lua`](Mount.lua), [`ExpansionInfo.lua`](ExpansionInfo.lua) | item/spell/quest/mount/expansion enrichment |
| IDs and extra frames | [`LinkID.lua`](LinkID.lua), [`SkinFrames.lua`](SkinFrames.lua) | sanitized IDs and additional tooltip registration |
| Settings and locales | [`Options.lua`](Options.lua), [`libs/Template.xml`](libs/Template.xml), [`locales/`](locales/) | Settings categories, profile operations, DIY editor, slash routing, labels |
| Diagnostics | [`Engine/Doctor.lua`](Engine/Doctor.lua), [`Engine/Debug.lua`](Engine/Debug.lua) | callback attribution, blocked/forbidden actions, `/rtt` output |
| Static verification | [`.github/workflows/static-checks.yml`](.github/workflows/static-checks.yml), [`tools/check_repo.py`](tools/check_repo.py) | Lua 5.1 parse, file graph, links, and runtime invariants |

## Boundary rules

- `Engine/TooltipProcessor.lua` is the sole tooltip processor implementation.
- Raw tooltip/aura records and raw argument vectors do not cross into modules.
- Values pass access and relevant `C_Secrets` gates before use.
- Script hooks skip objects with forbidden `ScriptBindings` aspects.
- Feature modules subscribe through `ModuleManager`; no parallel dispatcher is
  permitted.
- Addon bookkeeping belongs in addon-owned tables, not arbitrary Blizzard frame
  fields.
- Obsolete MoneyFrame wrappers, legacy bootstrap layers, raw rebuild paths, and
  unit-token candidate scans are not part of the runtime.
