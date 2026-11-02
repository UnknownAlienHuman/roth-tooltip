# Roth Tooltip agent guide

## Start here

Roth Tooltip is a modular Retail tooltip addon. It is not a flat set of
`GameTooltip` hooks. Before changing behavior, read:

1. [`RothTooltip.toc`](RothTooltip.toc)
2. [`Engine/Safe.lua`](Engine/Safe.lua)
3. [`Core.lua`](Core.lua)
4. [`Engine/Midnight.lua`](Engine/Midnight.lua)
5. [`Engine/Style.lua`](Engine/Style.lua)
6. [`Engine/TooltipRegistry.lua`](Engine/TooltipRegistry.lua)
7. [`Engine/TooltipProcessor.lua`](Engine/TooltipProcessor.lua)
8. [`Engine/ModuleManager.lua`](Engine/ModuleManager.lua)
9. the affected feature module

Release metadata is **12.1.0 / Interface 120100**.

The external engineering source of truth is
[UnknownAlienHuman/wow-addon-engineering-kb](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb).
Validate patch-sensitive claims against current Blizzard generated API
documentation and live FrameXML before editing an integration boundary.

## Load order

Execution order from [`RothTooltip.toc`](RothTooltip.toc):

```text
libs/lib.xml
Engine/Safe.lua
Engine/Policy.lua
Engine/ModuleManager.lua
Engine/Doctor.lua
Engine/Debug.lua
Core.lua
Engine/Midnight.lua
Engine/Style.lua
Engine/TooltipRegistry.lua
Engine/TooltipProcessor.lua
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

Load order is part of the runtime contract:

- `Engine/Safe.lua` establishes access and object helpers used by every later
  layer.
- `Core.lua` contains only patch-stable formatting, DB merge, media,
  color/filter, and trigger glue.
- `Engine/Midnight.lua` establishes the Retail 12.1 restriction/context
  boundary.
- `Engine/Style.lua` registers visual triggers before tooltips are registered.
- `Engine/TooltipRegistry.lua` registers known tooltips before the processor is
  installed and invalidates state on restriction/combat transitions.
- `Engine/TooltipProcessor.lua` is the sole active processor.
- Feature modules load after the sanitized boundary exists.

Do not add another bootstrap, override, or compatibility processor. Do not move
these files casually.

## Runtime pipeline

```text
Blizzard TooltipDataProcessor post-call
  -> Engine/TooltipProcessor.lua
  -> addon:GetPrimaryTooltipContext(...)
  -> Engine/Midnight.lua capability/restriction gates
  -> weak primitive context cache
  -> LibEvent.7000 trigger
  -> enabled feature module
  -> Engine/Style.lua or a safe tooltip method
```

The sanitized context may contain only ordinary primitive fields:

```text
type, id, itemID, spellID, dataInstanceID,
hyperlink, guid, unitToken
```

Raw tooltip records, raw aura records, and argument vectors must not cross the
dispatcher boundary. Aura subscribers receive the sanitized context and an
ordinary spell ID only.

## Secret-value and restriction contract

Retail 12.1 inaccessible values are capabilities, not delayed normal values.

Required order:

1. gate with `addon:CanAccessValue` / `addon:CanAccessAllValues`;
2. check the relevant `C_Secrets` predicate;
3. verify the expected ordinary Lua type;
4. only then branch, compare, index, format, concatenate, store, log, or call an
   API.

`pcall` is error containment. It is not an access probe, untaint operation,
declassification mechanism, or retry strategy.

Forbidden patterns include:

- `if value then` before an access gate for a patch-sensitive value;
- `value == value`, `tostring(value)`, concatenation, pattern matching,
  arithmetic, or table indexing to discover accessibility;
- storing inaccessible values for later retry;
- scanning candidate unit tokens to reconstruct restricted identity;
- forwarding raw aura/tooltip payload to another module;
- replaying cached raw tooltip data;
- assuming an enum member or API return without generated documentation;
- global replacement of Blizzard functions as a workaround.

Restriction helpers live in [`Engine/Midnight.lua`](Engine/Midnight.lua):

- `HasSecretRestrictions`
- `AreAurasRestricted`
- `AreCooldownsRestricted`
- `IsSpellAuraRestricted`
- `AreUnitStatsRestricted`
- `IsUnitIdentityRestricted`
- `IsUnitHealthRestricted`
- `CanCompareUnitTokens`

The policy layer in [`Engine/Policy.lua`](Engine/Policy.lua) must fail closed.
`AGGRESSIVE` may relax addon policy for ordinary data, but it may never override
Blizzard predicates or object restrictions.

## Object and frame contract

`CanBeAccessedInContext`, `IsForbidden`, and, where available,
`HasAnyForbiddenAspects` must be evaluated before interacting with a frame.
Script hooks also require `addon:CanBindScripts(frame)`.

Do not replace methods on Blizzard tooltip frames. Do not store addon cache,
hook, ticker, model, or status-text fields on arbitrary Blizzard frames.
Use addon-owned weak-key maps. Addon-created visual children may own their own
rendering fields and methods.

`Engine/Style.lua` intentionally hides only documented/known Blizzard visual
members. Do not restore broad `GetRegions()` enumeration: returned regions can
inherit restricted aspects in Retail 12.1.

## Module and event contract

[`Engine/ModuleManager.lua`](Engine/ModuleManager.lua) owns `LibEvent.7000`,
module state, callback attribution, counters, and detach-on-disable links.

Every feature module must:

- expose `M:Init`, `M:Enable`, `M:Disable`, `M:OnTooltip`, and
  `M:OnStyleChanged`;
- call `addon.MM:RegisterModule("Name", M)`;
- subscribe through `MM:AttachTrigger` / `MM:AttachEvent` when available;
- keep callbacks idempotent;
- avoid unbounded work in tooltip hot paths.

LibEvent invokes callbacks as `pcall(func, func, ...)`. The first callback
argument is the callback function itself, not a module object. Preserve existing
callback signatures.

`General` is a core module and cannot be disabled. Module state is stored in
`db.modules`.

## State and ownership

Persistent state:

- account: `RothTooltipDB`;
- character: `RothTooltipCharacterDB`;
- selector: `general.SavedVariablesPerCharacter`;
- module state: `db.modules`.

Runtime ownership examples:

- sanitized context: weak table in `Engine/Midnight.lua`;
- managed tooltips: weak set in `Engine/TooltipRegistry.lua`;
- style and faction icon: weak tables in `Engine/Style.lua`;
- cursor anchor/ticker state: weak table in `Anchor.lua`;
- link/achievement hook state: weak table in `LinkID.lua`;
- mount tooltip state: weak table in `Mount.lua`;
- status text: weak table in `General.lua`;
- player model: addon-owned `PlayerModel` parented to `UIParent`.

## Feature routing

| Change | Primary files |
| --- | --- |
| access gates and forbidden aspects | `Engine/Safe.lua`, `Engine/Policy.lua` |
| restriction predicates, context, refresh, unit/owner helpers | `Engine/Midnight.lua` |
| managed tooltip lifecycle | `Engine/TooltipRegistry.lua` |
| active tooltip type dispatch | `Engine/TooltipProcessor.lua` |
| formatting, colors, filters, media, named trigger glue | `Core.lua` |
| module lifecycle and event bus | `Engine/ModuleManager.lua` |
| rendering and visual triggers | `Engine/Style.lua` |
| DB merge, migrations, status bar | `General.lua`, `Config.lua` |
| anchoring | `Anchor.lua` |
| target line | `Target.lua` |
| unit formatting, inspect, M+/raid fields | `Unit.lua` |
| 3D model | `Model.lua` |
| item/spell/quest/mount/ID/expansion behavior | matching feature module |
| extra tooltip registration | `SkinFrames.lua` |
| Settings, profiles, slash routing | `Options.lua`, `libs/Template.xml`, `locales/` |
| diagnostics | `Engine/Doctor.lua`, `Engine/Debug.lua` |

The removed MoneyFrame wrapper must not be restored without a new current
reproducible Blizzard regression. The former WoWUIBugs reports #801 and #838
were closed as fixed on 2026-07-23.

## Performance constraints

Tooltip callbacks are hot paths. Apply this order:

1. module enabled check;
2. object/access/policy gate;
3. sanitized context/type check;
4. cheap cache lookup;
5. only then optional API work or formatting.

Do not add:

- addon-wide polling;
- per-frame candidate unit scans;
- repeated inspect requests;
- raw aura scans;
- repeated tooltip rebuild loops;
- full mount-journal/group/raid scans on every hover;
- duplicate Mythic+ summary calls in one tooltip pass.

Inspect requests are asynchronous, throttled, and cached. Mythic+ summaries are
bounded and cached briefly. Mount journal data and saved raid progress are
collected outside repeated tooltip work.

## Verification

Before merging:

1. verify TOC/XML load order and file existence;
2. parse every Lua file with a Lua 5.1-compatible parser;
3. run `python3 tools/check_repo.py`;
4. inspect the diff for raw aura/tooltip forwarding, secret probes, candidate
   unit scans, global Blizzard function replacements, unknown enums/events, and
   raw replay;
5. run in-game `/reload` with Lua errors enabled;
6. test item, pet-action, flyout, macro, spell, unit, aura, quest, mount,
   generic-ID, model, status-bar, and extra-frame tooltips;
7. test world, party, raid, arena, combat/restriction transitions, modifiers,
   inspect completion, loading screens, profile import/export/reset, module
   toggles, and Settings reopen;
8. inspect `/rtt errors`, `ADDON_ACTION_BLOCKED`, `ADDON_ACTION_FORBIDDEN`, and
   taint output.

Static checks cannot establish live secure-context behavior. Keep
[issue #1](https://github.com/UnknownAlienHuman/roth-tooltip/issues/1) open until
the client matrix is complete.

## Patch-sensitive assumptions

Revalidate for every Retail patch:

- `Enum.TooltipDataType` members and payload fields;
- `TooltipDataProcessor` and `TooltipUtil` behavior;
- `C_Secrets` predicates and declassification rules;
- frame method secret/identity/forbidden-aspect annotations;
- Blizzard tooltip frame names and parent relationships;
- Settings proxy APIs;
- model, health, aura, cooldown, and unit identity restrictions.

Never infer a return contract from a method name. For example, Retail 12.1
generated docs declare no return value for `PlayerModel:CanSetUnit()`, while
`PlayerModel:SetUnit()` returns the authoritative success boolean.
