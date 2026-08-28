# Roth Tooltip agent guide

## Start here

Roth Tooltip is a modular Retail tooltip addon. It is not a flat set of `GameTooltip` hooks. Before changing behavior, read:

1. [`RothTooltip.toc`](RothTooltip.toc)
2. [`Engine/TooltipBootstrap.lua`](Engine/TooltipBootstrap.lua)
3. [`Core.lua`](Core.lua)
4. [`Engine/Midnight.lua`](Engine/Midnight.lua)
5. [`Engine/Runtime12_1.lua`](Engine/Runtime12_1.lua)
6. [`Engine/TooltipProcessor.lua`](Engine/TooltipProcessor.lua)
7. [`Engine/ModuleManager.lua`](Engine/ModuleManager.lua)
8. the affected feature module

Release metadata is **12.1.0 / Interface 120100**.

The external engineering source of truth is [UnknownAlienHuman/wow-addon-engineering-kb](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb). Validate patch-sensitive claims against current Blizzard generated API documentation and live FrameXML before editing a boundary.

## Load order

Execution order from [`RothTooltip.toc`](RothTooltip.toc):

```text
libs/lib.xml
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

- `Engine/TooltipBootstrap.lua` sets the defer/idempotency flags that prevent the legacy 12.0 processor embedded in `Core.lua` from registering.
- `Core.lua` supplies legacy formatting, configuration helpers, style triggers, color/filter functions, and compatibility surfaces.
- `Engine/Midnight.lua` replaces patch-sensitive public access, context, unit, refresh, owner-chain, and line helpers with the Retail 12.1 contract.
- `Engine/Runtime12_1.lua` applies focused corrections that must run after both Core and Midnight.
- `Engine/TooltipProcessor.lua` is the only active `TooltipDataProcessor` dispatcher.
- Feature modules load after the sanitized boundary exists.

Do not move these files casually. A different order can reactivate the legacy dispatcher or expose old Core helpers to feature modules.

## Runtime pipeline

```text
Blizzard TooltipDataProcessor post-call
  -> Engine/TooltipProcessor.lua
  -> addon:GetPrimaryTooltipContext(...)
  -> Engine/Midnight.lua access gates and primitive copy
  -> weak per-tooltip context cache
  -> LibEvent.7000 trigger
  -> ModuleManager enabled subscriber
  -> feature module
  -> named Engine/Style.lua trigger / safe tooltip method
```

The sanitized context may contain only ordinary primitive fields:

```text
type, id, itemID, spellID, dataInstanceID,
hyperlink, guid, unitToken
```

Raw `TooltipData`, raw `AuraData`, and `TooltipData.args` must not cross the dispatcher boundary. Aura subscribers receive the sanitized context and an ordinary spell ID only. Do not restore the former raw aura payload.

## Secret-value and restriction contract

Retail 12.1 inaccessible values are capabilities, not delayed normal values.

Required order:

1. gate with `addon:CanAccessValue` / `addon:CanAccessAllValues`;
2. check the relevant `C_Secrets` predicate;
3. verify the expected ordinary Lua type;
4. only then branch, compare, index, format, concatenate, store, log, or call an API.

`pcall` is error containment. It is not an access probe, untaint operation, declassification mechanism, or retry strategy.

Forbidden patterns include:

- `if value then` before the access gate;
- `value == value`, `tostring(value)`, concatenation, pattern matching, arithmetic, or table indexing to discover accessibility;
- storing inaccessible values for later retry;
- scanning candidate unit tokens to reconstruct a restricted identity;
- forwarding raw aura or tooltip payloads to another module;
- calling `RebuildFromTooltipInfo` with cached raw data;
- global replacements of Blizzard functions as a secret-value workaround.

Restriction helpers live in [`Engine/Midnight.lua`](Engine/Midnight.lua):

- `HasSecretRestrictions`
- `AreAurasRestricted`
- `AreCooldownsRestricted`
- `AreUnitStatsRestricted`
- `IsUnitIdentityRestricted`
- `IsUnitHealthRestricted`
- `CanCompareUnitTokens`

The policy layer in [`Engine/Policy.lua`](Engine/Policy.lua) must fail closed. `AGGRESSIVE` may relax addon policy for ordinary data, but it may never override Blizzard predicates or object access restrictions.

## Module and event contract

[`Engine/ModuleManager.lua`](Engine/ModuleManager.lua) owns `LibEvent.7000`, module state, callback attribution, counters, and detach-on-disable links.

Every feature module must:

- expose `M:Init`, `M:Enable`, `M:Disable`, `M:OnTooltip`, and `M:OnStyleChanged`;
- call `addon.MM:RegisterModule("Name", M)`;
- subscribe through `MM:AttachTrigger` / `MM:AttachEvent` when available;
- keep callbacks idempotent;
- avoid unbounded work in tooltip hot paths.

LibEvent calls callbacks as `pcall(func, func, ...)`. The first callback argument is the callback function itself, not a module object. Preserve existing callback signatures.

`General` is a core module and cannot be disabled. Module state is stored in `db.modules`.

## State and ownership

Persistent state:

- account: `RothTooltipDB`;
- character: `RothTooltipCharacterDB`;
- selector: `general.SavedVariablesPerCharacter`;
- module state: `db.modules`.

Runtime state that does not belong to Blizzard frames should be kept in addon-owned tables, preferably weak-key tables for tooltip/frame keys. Do not add `__RT_Last*`, cache, hook, ticker, or model fields to Blizzard buttons/tooltips merely for addon bookkeeping.

Current ownership examples:

- sanitized tooltip context: weak table in `Engine/Midnight.lua`;
- cursor anchor/ticker state: weak table in `Anchor.lua`;
- link/achievement hook state: weak table in `LinkID.lua`;
- mount tooltip state: weak table in `Mount.lua`;
- player model: module-owned `PlayerModel` parented to `UIParent`, not stored on `GameTooltip`.

`Engine/Style.lua` intentionally creates the visual `__RTStyle` hierarchy on managed tooltips. That is a rendering surface, not a general-purpose state store.

## Feature routing

| Change | Primary files |
| --- | --- |
| access gates, C_Secrets predicates, context, refresh, owner/unit helpers | `Engine/Midnight.lua`, `Engine/Runtime12_1.lua` |
| active tooltip type dispatch | `Engine/TooltipProcessor.lua` |
| legacy formatting/color/filter/style trigger helpers | `Core.lua` |
| module lifecycle and event bus | `Engine/ModuleManager.lua` |
| style frame construction and visual triggers | `Engine/Style.lua` |
| DB merge, migrations, status bar | `General.lua`, `Config.lua` |
| anchoring | `Anchor.lua` |
| target line | `Target.lua` |
| unit formatting, inspect, M+/raid fields | `Unit.lua` |
| 3D model | `Model.lua` |
| item/spell/quest/mount/ID/expansion behavior | matching feature module |
| additional tooltip registration | `SkinFrames.lua` |
| Settings, profiles, slash routing | `Options.lua`, `libs/Template.xml`, `locales/` |
| diagnostics | `Engine/Doctor.lua`, `Engine/Debug.lua` |

The removed `Compat_MoneyFrame.lua` global wrapper must not be restored without a current reproducible Blizzard regression. WoWUIBugs #801 and #838 were closed as fixed on 2026-07-23.

## Performance constraints

Tooltip callbacks are hot paths. Apply this order:

1. module enabled check;
2. object/access/policy gate;
3. sanitized context/type check;
4. cheap cache lookup;
5. only then optional API work or formatting.

Do not add:

- addon-wide polling;
- per-frame candidate scans;
- repeated inspect requests;
- raw aura scans;
- repeated tooltip rebuild loops;
- full group/raid scans on every hover unless the data cannot be obtained otherwise and the result is cached.

Inspect requests are asynchronous, throttled, and cached for 300 seconds. Mount journal data and saved raid progress are collected outside repeated tooltip work and cached.

## Verification

Before merging:

1. verify TOC/XML load order and file existence;
2. parse every Lua file with a Lua 5.1-compatible parser;
3. check repository Markdown links and stale file references;
4. confirm no active code references `Compat_MoneyFrame.lua`;
5. inspect the branch diff for raw aura forwarding, secret probes, unit-token candidate scans, global Blizzard function replacements, and unrestricted rebuild calls;
6. run in-game `/reload` with Lua errors enabled;
7. test item, action, spell, unit, aura, quest, mount, generic-ID, model, status-bar, and extra-frame tooltips;
8. test world, party, raid, arena, combat, modifier refresh, inspect completion, loading screens, profile import/export/reset, module toggles, and Settings reopen;
9. inspect `/rtt errors`, `ADDON_ACTION_BLOCKED`, `ADDON_ACTION_FORBIDDEN`, and taint output.

Static checks cannot establish live secure-context behavior. Keep [issue #1](https://github.com/UnknownAlienHuman/roth-tooltip/issues/1) open until the client matrix is completed.

## Patch-sensitive assumptions

The following must be revalidated for each Retail patch:

- `Enum.TooltipDataType` members and payload fields;
- `TooltipDataProcessor` and `TooltipUtil` behavior;
- `C_Secrets` predicates and declassification rules;
- frame method `SecretArguments` / `RequiresDeclassifiedUnitIdentity` annotations;
- Blizzard tooltip frame names and parent relationships;
- Settings proxy APIs;
- model, health, aura, cooldown, and unit identity restrictions.

Never infer a return contract from a method name. For example, Retail 12.1 generated docs declare no return value for `PlayerModel:CanSetUnit()`, while `PlayerModel:SetUnit()` returns the authoritative success boolean.
