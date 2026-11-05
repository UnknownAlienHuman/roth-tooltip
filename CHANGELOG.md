# Changelog

## Second-pass hardening — 2026-11-03

- Target Retail 12.1.5 / Interface 120105 while retaining the named-client gate.
- Make optional-module activation deterministic in TOC registration order.
- Cache party roster zones outside the tooltip hot path and invalidate on roster/world transitions.
- Remove the mutable global addon namespace, dead global lookup table and unused defaults.
- Accept expansion ID 0 and run static checks automatically for pull requests.

## Third-pass hardening — 2026-11-04

- Give inspect requests an owned cancellable timeout; completion, replacement, restrictions and disable converge on one cleanup path without touching the global inspect target.
- Isolate subscriptions created during nested event-bus dispatch until the outermost transaction ends; snapshot detach targets and bound retained error text.
- Register Settings with canonical schema defaults rather than the active profile, and route live wildcard edits through the same bounded validator as imports.
- Gate decoded profile documents before field access, preserve exact legacy-key exceptions only, and keep profile/diagnostic UI frames single-owned across temporary access denial.
- Recompute cursor scale and automatic quadrant from current UIParent coordinates; bound DIY layout rows and reject combat/profile-stale drag commits.
- Preserve style/status/registry ownership during temporary access denial, and make SkinFrames release only frames it actually added.
- Resolve optional LibSharedMedia lazily, including libraries loaded after RothTooltip, and remove unused helpers/icons.
- Route taint diagnostics through the private native event owner and cap diagnostic fields before retention/export.
- Add 21 focused regressions; the complete Lua 5.1 suite now contains 121 tests.

## Fourth-pass hardening — 2026-11-04

- Remove dead `npcTitle` and unit `itemQuality` presentation modes while migrating existing profiles to supported state; expose the previously missing same-guild filter and complete anchor domains.
- Gate profile tables before metatable/key inspection, reject sparse/noncanonical layout identities, and bound native tooltip, Mythic+ and saved-instance enumeration.
- Keep disabled unit elements disabled under modifier bypass; module toggles now refresh visible exact-source tooltips after the lifecycle commit.
- Stop mutating native spell icon/border regions; spell presentation is an idempotent owned text prefix. Remove the obsolete foreign `forceHideText` status-bar probe.
- Preserve one style owner across temporary access denial and keep pending nested subscriptions invisible to subscriber queries until the outer dispatch completes.
- Make DIY drag/drop a detached clone-validate-generation-check-commit transaction; failed, combat or stale drops leave the live layout untouched.
- Resolve the story tooltip through the public helper, remove an absent extra-frame target, and retain only frames actually added by `SkinFrames`.
- Scope-check live source `12.1.5.70783` against the KB-selected `12.1.5.70688`; its changed files do not alter the contracts used by RothTooltip.
- Add nine focused regressions; the complete suite now contains 130 tests before the final Lua 5.1 CI run.

## Fifth-pass hardening — 2026-11-04

- Notify every registered proxy setting after an external profile/scope replacement so an open Settings panel cannot retain values from the previous backing table.
- Give public module transitions one side-effect owner: lifecycle commit, exact-source visible-tooltip refresh and external Settings notification. Settings-originated writes suppress the duplicate notification.
- Rank saved raid lockouts with the public `GetDifficultyInfo` semantics instead of treating numeric difficulty IDs as an ordered scale.
- Resolve cursor geometry before claiming `ANCHOR_NONE`; unavailable cursor coordinates now fall back to the configured static anchor instead of leaving a tooltip ownerless.
- Add four focused integration regressions and strengthen repository invariants; the complete suite now contains 134 tests before the final Lua 5.1 CI run.

## Development audit — 2026-11-03

- Fresh, gated tooltip contexts; exact-source refresh and one modifier owner. Native item readiness and bag/action/comparison acquisition remain native.
- Semantic unit rows preserve unrelated content; private achievement-frame scraping and duplicate item-ID rendering removed.
- Independent model panel; generation-safe cursor/mount timers; bounded inspect with competing-owner observation, no global inspect clear and no retained unit token.
- Detached profile schema 3.3 validation, bounded legacy/enveloped JSON import, recovery of malformed saved leaves and preservation of newer schemas.
- Split unit metadata/enrichment and profile validation from large mixed-responsibility files. Remove empty lifecycle methods, obsolete rewrite scripts, empty XML loader and source-export workflow.
- Full TOC Lua bootstrap/integration tests now run on Lua 5.1. Native client/taint/render/performance gate remains open; release metadata is unchanged.

## 12.1.0 — 2026-08-27

### Retail target

- Updated TOC metadata to `Interface: 120100` and version `12.1.0`.
- Revalidated the tooltip runtime against Retail 12.1 generated API documentation and the project engineering knowledge base.

### Secret-value and restriction hardening

- Replaced comparison-based secret probes with `canaccessvalue` / `canaccessallvalues` capability gates.
- Added fail-closed `C_Secrets` predicates for aura, cooldown, unit identity, unit stats, unit health, and unit-token comparison paths.
- Added a sanitized primitive tooltip context stored outside Blizzard tooltip fields.
- Stopped forwarding raw `AuraData` and `TooltipData.args` to feature modules.
- Removed unit-token candidate scans and the `mouseover` recovery path.
- Removed raw-tooltip rebuild fallback; refresh now uses only accessible unit tokens, hyperlinks, or spell IDs.

### Tooltip processing

- Disabled the legacy 12.0 processor in `Core.lua` through an explicit bootstrap layer.
- Added a single isolated Retail 12.1 `TooltipDataProcessor` bridge.
- Removed spell-texture probing as an action-tooltip classifier.
- Corrected action/macro spell-ID normalization.

### Modules

- Reworked unit, target, model, status-bar, item, spell, quest, mount, expansion, ID, anchor, and extra-frame paths to gate data before use.
- Bounded and throttled inspect caching and moved inspect events into the module lifecycle.
- Moved cursor, mount, achievement-hook, context, and model state away from arbitrary Blizzard frame fields.
- Isolated the 3D model under `UIParent`; model operations stop in combat/restricted contexts.
- Corrected `PlayerModel:CanSetUnit()` handling: the method has no documented return value, while `SetUnit()` supplies the authoritative success boolean.
- Fixed multi-line tooltip allocation, movement-speed return handling, and raid/party zone tuple handling.

### Compatibility cleanup

- Removed `Compat_MoneyFrame.lua` and its global Blizzard function wrappers. The upstream MoneyFrame regressions tracked as WoWUIBugs #801 and #838 were closed as fixed on 2026-07-23.

### Documentation and verification

- Rewrote README, architecture, code index/graph, and agent guidance for the active 12.1 pipeline.
- Added GitHub Actions checks for Lua 5.1 parsing, TOC/XML references, Markdown links, runtime markers, and release metadata.
- Live in-game verification remains tracked in issue #1.
