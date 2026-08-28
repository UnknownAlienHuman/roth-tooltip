# Changelog

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
