# Architecture

## Load and data flow

The authoritative file order is [RothTooltip.toc](RothTooltip.toc): Safe, Policy, ModuleManager and diagnostics precede Core; Midnight, Style, TooltipRegistry and TooltipProcessor precede defaults, General, feature modules and Settings.

```text
Blizzard TooltipDataProcessor
  -> TooltipProcessor (one permanent ALL pre-call and post-call)
  -> Midnight (current-data normalization and restrictions)
  -> private addon.LibEvent
  -> enabled feature subscriber
  -> Style / permitted tooltip operation

General -> select and migrate active profile -> variables-loaded
        -> ModuleManager applies saved module states
        -> Settings reads and changes the same active state
```

There is no loaded legacy processor, bootstrap suppression file or second patch-override layer in this branch. The event bus and mutable addon namespace are private to RothTooltip; LibSharedMedia is optional, and no LibStub fallback is installed.

## Mutable-state owners

| Concern | Owner |
| --- | --- |
| value/table/object access and tuple preservation | `Engine/Safe.lua` |
| combat/content policy | `Engine/Policy.lua` |
| events, callback lifetime, module transitions and counters | `Engine/ModuleManager.lua` |
| fresh tooltip context, restrictions, line access and safe refresh | `Engine/Midnight.lua` |
| native data callback registration and type dispatch | `Engine/TooltipProcessor.lua` |
| managed tooltip membership | `Engine/TooltipRegistry.lua` |
| style frames, region restoration and backdrop hooks | `Engine/Style.lua` |
| formatting, media lookup, colors and shared presentation triggers | `Core.lua` |
| defaults, schema validation and active store/status bar | `Config.lua`, `Engine/Profile.lua`, `General.lua` |
| ordinary unit metadata and bounded asynchronous enrichment | `Engine/UnitInfo.lua`, `Engine/UnitStats.lua` |
| feature caches, timers and optional enrichment | corresponding feature module |
| Settings mutations, profile dialog and layout editor | `Options/Core.lua`, `Options/Profile.lua`, `Options/DIY.lua`, `Options.lua` |
| bounded error records and diagnostics UI | `Engine/Doctor.lua`, `Engine/Debug.lua` |

Frame bookkeeping belongs in addon-owned maps. Style uses weak-key maps for visuals and installed hooks; it does not replace Blizzard tooltip methods or store a `__RTStyle` field on them. A non-nil style association remains the sole owner even when the child is temporarily inaccessible; access denial never authorizes creation of a replacement layer.

## Module transitions

General starts before saved-profile selection. Optional modules remain inactive until `tooltip:variables:loaded`, then activate in TOC registration order so shared tooltip triggers are deterministic. Initialization runs once after success; an initialization failure is retryable. An enable failure detaches subscriptions before cleanup and leaves the saved state disabled. Disable marks the module inactive before detaching or running feature cleanup. Reentrant transitions and subscriptions from disabled modules are rejected.

The bus snapshots dispatch length and tombstones removed subscriptions. Removal takes effect immediately. A subscription created during any nested dispatch remains pending until the outermost dispatch transaction completes, so cross-event reentrancy cannot observe half-installed work; subscriber-presence queries ignore the same pending entries. Callback-wide detach snapshots buckets before mutation. The last native listener unregisters its event. A failed multi-event registration rolls back only its own additions. Error attribution is per subscription, not per shared callback function, and retained error text is bounded.

## Presentation ordering

Registration/profile application establishes the base theme. Feature processors then set contextual colors. Show and native backdrop notifications restore the addon surface without replaying base colors over the feature result. Style owns each backdrop hook and each show/hide/clear hook once; a clear resets layout once. Unregister restores the native regions previously captured as shown and makes remaining hooks passive. Spell decoration prefixes the semantic header text idempotently and does not hide, recolor or repurpose Blizzard-owned icon/border regions. Modifier keys may bypass an enabled element's filter, but never its `enable = false` state.

SafeCall keeps complete result arity, including `false` and nil holes. Ordinary tuples avoid a result table; mixed tuples replace inaccessible slots without shifting the others. These helpers do not establish permission for an arbitrary API or extend borrowed-data lifetime.

## Data and profile lifetime

`Midnight` re-queries the primary native data on every request; it does not keep a context cache. Only synchronous ordinary context records cross the dispatcher. `UnitInfo` stops before unit APIs when stats are restricted and reuses a short-lived roster-zone snapshot instead of scanning the group on every hover. `UnitStats` owns TTL/capacity-bounded enrichment, the pending inspect GUID and an exact cancellable timeout generation. It stores no unit token, respects native Inspect UI and observed competing requests, and never clears the global inspect target. Modifier refresh is registered only by TooltipRegistry. Native item readiness has no parallel addon refresh tracker.

The model is parented and anchored to UIParent, follows ordinary cursor coordinates independently, and clears on hide, disable, restrictions and world exit. A custom cursor anchor uses ANCHOR_NONE, never a simultaneous native cursor anchor; stale timer generations cannot move or cancel a replacement.

`Profile` validates a detached schema-guided candidate before publication. General commits one active store and then broadcasts. Wrong-type saved leaves recover defaults; a newer saved schema remains untouched. Imports gate each table before metatable/key inspection, apply exact legacy-key exceptions, enforce depth/node/string/range/domain limits, reject cyclic/shared graphs and sparse or noncanonical layout identities, and preserve account/character isolation. Settings declare defaults from the immutable canonical schema, not the active profile. Schema version is independent of addon release metadata.

The profile dialog, diagnostics window, status text, style attachments and DIY preview are single-owner objects: temporary access denial does not authorize replacement. DIY drag state captures one profile generation, clones the rows, validates a detached candidate, rechecks ownership/combat immediately before commit, and atomically replaces at most sixteen rows. A failed target or stale generation never mutates the active profile.

## Evidence boundary

The KB-selected platform baseline is `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`. Live source `12.1.5.70783` / `297d7aaaa736f346b3e036f38ee088eaf7f8c07f` was reviewed as a direct one-commit delta; it changes Battle.net/Friends/roleset/texture/unit-event surfaces, not the tooltip, Settings, TOC or model slices used by this addon. This scoped continuity is source evidence, not a named-client pass.

[Validation](tests/README.md) records Lua 5.1 unit/integration checks, complete TOC Lua execution with mocks and source-contract scope. Native XML template rendering, engine Secret Values/taint/protected execution and performance still require a named client. Source inspection and passing mocks do not certify a release.
