# Roth Tooltip agent guide

Read [RothTooltip.toc](RothTooltip.toc), [architecture](ARCHITECTURE.md), the affected implementation and [test scope](tests/README.md) before editing.
Use the [engineering KB task index](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb/blob/main/INDEX_MINI.md), its tooltip owner and current overlays for patch-sensitive work. The KB's selected source is evidence, not proof this addon passed on that client.

## Ownership

- `Engine/Safe.lua`: value/table/object access and error containment. Gate before comparison, indexing, formatting, storage or logging. A successful `pcall` does not grant access or declassify a value.
- `Engine/Policy.lua`: user policy after native access checks. No mode overrides forbidden aspects or secret restrictions.
- `Engine/ModuleManager.lua`: private `addon.LibEvent`, native events, subscriptions, module state and callback attribution. Do not install or modify a global LibStub/LibEvent replacement.
- `Engine/Midnight.lua`: patch-sensitive fresh tooltip context, line access and refresh; it stores no context cache. `Engine/UnitInfo.lua` owns ordinary unit formatting and `Engine/UnitStats.lua` owns bounded enrichment. `Engine/TooltipProcessor.lua` is the single session-long native processor registration owner.
- `Engine/TooltipRegistry.lua`: managed-frame membership. `Engine/Style.lua`: addon visuals and native backdrop hooks. Do not reintroduce backdrop hooks in Core or reapply base colors after feature processing.
- `Engine/Profile.lua`: pure schema validation/migration and the shared wildcard validator. `General.lua`: active SavedVariables selection and status bar. `Config.lua`: canonical defaults. Settings must register defaults from that canonical schema; Settings and slash commands use the same module/profile APIs, not a second runtime state.

The old bootstrap/override files are absent from this branch. Do not recreate a shadow implementation suppressed only by load order. Optional LibSharedMedia lookups must tolerate LibStub being absent.

## Lifecycle

Register each module once. Implement only lifecycle methods that do work; `Init`, `Enable` and `Disable` may be omitted. An explicit `false` or an error means failure. Optional initialization waits for the selected saved profile; General starts early to select it.

Use `MM:AttachEvent` / `MM:AttachTrigger` during an enabled lifecycle. The manager owns subscription teardown. Callback arguments preserve the existing convention: the first argument is the callback itself, followed by the event payload. Removed callbacks stop immediately; subscriptions created during nested dispatch remain pending until the outermost dispatch completes.

Feature owners must still cancel their timers, invalidate continuations and hide their visuals on disable. A native `hooksecurefunc`/processor cannot be detached; install it once and gate the persistent callback on current enabled state. Do not let delayed work resubscribe a disabled module.

Keep raw tooltip/aura records borrowed to the current callback. Copy only verified ordinary primitives and revalidate identity, access and ownership before later use. Never use old raw records, geometry, event timing or candidate scans to reconstruct restricted state.

## Validation and publication

Use one manager-owned checkout. Preserve the current branch and base SHA; publish non-forced with an expected-head check and read back the result. Keep runtime evidence separate from source inspection and mocks.

Run the commands and client matrix in [tests/README.md]. Do not mark issue #1 resolved or claim current-client compatibility from metadata or mock tests alone. Keep code and technical documentation in English; localized UI strings belong in `locales/`.
