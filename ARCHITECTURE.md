# Architecture

## Load and data flow

The authoritative file order is [RothTooltip.toc](RothTooltip.toc): Safe, Policy, ModuleManager and diagnostics precede Core; Midnight, Style, TooltipRegistry and TooltipProcessor precede defaults, General, feature modules and Settings.

```text
Blizzard TooltipDataProcessor
  -> TooltipProcessor (one permanent registration per type)
  -> Midnight (current-data normalization and restrictions)
  -> private addon.LibEvent
  -> enabled feature subscriber
  -> Style / permitted tooltip operation

General -> select and migrate active profile -> variables-loaded
        -> ModuleManager applies saved module states
        -> Settings reads and changes the same active state
```

There is no loaded legacy processor, bootstrap suppression file or second patch-override layer in this branch. The event bus is private to RothTooltip; LibSharedMedia is optional, and no LibStub fallback is installed.

## Mutable-state owners

| Concern | Owner |
| --- | --- |
| value/table/object access and tuple preservation | `Engine/Safe.lua` |
| combat/content policy | `Engine/Policy.lua` |
| events, callback lifetime, module transitions and counters | `Engine/ModuleManager.lua` |
| current tooltip context, unit helpers and safe refresh | `Engine/Midnight.lua` |
| native data callback registration and type dispatch | `Engine/TooltipProcessor.lua` |
| managed tooltip membership | `Engine/TooltipRegistry.lua` |
| style frames, region restoration and backdrop hooks | `Engine/Style.lua` |
| formatting, media lookup, colors and shared presentation triggers | `Core.lua` |
| defaults and active profile/status-bar behavior | `Config.lua`, `General.lua` |
| feature caches, timers and optional enrichment | corresponding feature module |
| Settings mutations, profile dialog and layout editor | `Options/Core.lua`, `Options/Profile.lua`, `Options/DIY.lua`, `Options.lua` |
| bounded error records and diagnostics UI | `Engine/Doctor.lua`, `Engine/Debug.lua` |

Frame bookkeeping belongs in addon-owned maps. Style uses weak-key maps for visuals and installed hooks; it does not replace Blizzard tooltip methods or store a `__RTStyle` field on them.

## Module transitions

General starts before saved-profile selection. Optional modules remain inactive until `tooltip:variables:loaded`. Initialization runs once after success; an initialization failure is retryable. An enable failure detaches subscriptions before cleanup and leaves the saved state disabled. Disable marks the module inactive before detaching or running feature cleanup. Reentrant transitions and subscriptions from disabled modules are rejected.

The bus snapshots dispatch length and tombstones removed subscriptions. Removal takes effect in the current dispatch; additions wait for the next one. The last native listener unregisters its event. A failed multi-event registration rolls back only its own additions. Error attribution is per subscription, not per shared callback function.

## Presentation ordering

Registration/profile application establishes the base theme. Feature processors then set contextual colors. Show and native backdrop notifications restore the addon surface without replaying base colors over the feature result. Style owns each backdrop hook and each show/hide/clear hook once; a clear resets layout once. Unregister restores the native regions previously captured as shown and makes remaining hooks passive.

SafeCall keeps complete result arity, including `false` and nil holes. Ordinary tuples avoid a result table; mixed tuples replace inaccessible slots without shifting the others. These helpers do not establish permission for an arbitrary API or extend borrowed-data lifetime.

## Evidence boundary

[Tests and remaining client gates](tests/README.md) distinguish tested runtime components from untested full-addon integration. A UIParent parent alone does not isolate a widget anchored to restricted tooltip geometry; the existing model and refresh/enrichment paths still require their own review and named-client matrix. Do not infer complete 12.1.5 migration or measured performance from this refactor.
