# Architecture

## Load-time layers

`RothTooltip.toc` defines one Retail 12.1 runtime. The order is intentional:

```text
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
feature modules
XML/locales
Options.lua
```

- [`Engine/Safe.lua`](Engine/Safe.lua) supplies value gates, object access,
  forbidden-aspect checks, and protected-call containment.
- [`Core.lua`](Core.lua) supplies patch-stable formatting, DB merge, media,
  color/filter, and named visual triggers. It contains no tooltip processor.
- [`Engine/Midnight.lua`](Engine/Midnight.lua) owns restriction predicates,
  sanitized context, managed-tooltip helpers, safe refresh, unit helpers, and
  line access.
- [`Engine/Style.lua`](Engine/Style.lua) owns visual regions and style state.
- [`Engine/TooltipRegistry.lua`](Engine/TooltipRegistry.lua) registers known
  tooltip frames before processor callbacks can fire and invalidates contexts
  on policy transitions.
- [`Engine/TooltipProcessor.lua`](Engine/TooltipProcessor.lua) is the only
  `TooltipDataProcessor` dispatcher.

## Data boundary

```text
Blizzard TooltipDataProcessor post-call
  -> TooltipProcessor prepares the managed tooltip
  -> Midnight reads and sanitizes TooltipData
  -> weak primitive context cache
  -> LibEvent.7000 trigger
  -> enabled feature module
  -> safe frame/style operation
```

Only ordinary primitive context fields may cross the sanitizer boundary:

```text
type, id, itemID, spellID, dataInstanceID,
hyperlink, guid, unitToken
```

Raw tooltip records, raw aura records, and argument vectors are not stored or
forwarded. Aura enrichment receives only an ordinary spell ID, and is suppressed
when global or spell-specific aura secrecy applies.

## Restriction model

The required integration order is:

1. `canaccessvalue` / `canaccessallvalues`;
2. the relevant `C_Secrets` predicate;
3. expected ordinary Lua type;
4. only then branch, compare, index, format, store, log, or call another API.

`pcall` contains ordinary Lua errors; it is not a secret-value probe or a
declassification mechanism. Object hooks also check the `ScriptBindings`
forbidden aspect when the API is available.

## Module system

[`Engine/ModuleManager.lua`](Engine/ModuleManager.lua) owns `LibEvent.7000`,
module registration, saved enable state, callback attribution, counters, and
detach-on-disable links. `General` is a core module and remains enabled.

[`General.lua`](General.lua) merges account/character SavedVariables, performs
schema migrations, initializes the status bar, and emits variables-loaded
triggers. [`Options.lua`](Options.lua) writes Settings proxies and reuses the
same module/style paths.

## Runtime ownership

Addon bookkeeping is stored outside arbitrary Blizzard frame fields:

- sanitized tooltip context: weak table in `Engine/Midnight.lua`;
- managed tooltip set: weak table in `Engine/TooltipRegistry.lua`;
- style, faction-icon, and hook state: weak tables in `Engine/Style.lua`;
- cursor anchor/ticker state: weak table in `Anchor.lua`;
- achievement hook state: weak table in `LinkID.lua`;
- mount tooltip state: weak table in `Mount.lua`;
- status-bar text: weak table in `General.lua`;
- 3D model: addon-owned `PlayerModel` parented to `UIParent`.

The visual frame and regions created by `Engine/Style.lua` are addon-owned
children used only for rendering; they are not a second tooltip-data store.

## Refresh model

A visible tooltip may be reopened only from:

- an ordinary accessible unit token;
- an ordinary item hyperlink;
- a direct `Enum.TooltipDataType.Spell` spell ID.

Aura, macro, flyout, pet-action, and generic-ID contexts are not converted into
spell tooltips merely to force a refresh. Restriction transitions clear context
and hide visible managed tooltips instead of replaying prior data.

## External dependencies

The TOC declares no required external addon. The repository provides its local
event bus and minimal LibStub fallback. LibSharedMedia is optional.
