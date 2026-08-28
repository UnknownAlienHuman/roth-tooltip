# Changelog

## 12.1.0 — 2026-08-28

### Retail target

- Updated TOC metadata to `Interface: 120100` and version `12.1.0`.
- Revalidated patch-sensitive behavior against Retail 12.1 generated API
  documentation, live FrameXML, and the project engineering knowledge base.

### Secret-value and restriction hardening

- Replaced comparison-based secret probes with `canaccessvalue` /
  `canaccessallvalues` capability gates.
- Added fail-closed `C_Secrets` predicates for aura, spell-specific aura,
  cooldown, unit identity, unit stats, unit health, and unit-token comparison
  paths.
- Added object forbidden-aspect checks before script bindings.
- Normalized raw tooltip records into an addon-owned primitive context.
- Stopped forwarding raw aura records and tooltip argument vectors to feature
  modules.
- Removed unit-token candidate scans, mouseover identity recovery, and raw
  payload replay.

### Single Retail 12.1 runtime

- Physically removed the disabled legacy 12.0 tooltip engine from `Core.lua`.
- Removed the temporary bootstrap/override layers; `Core.lua` now contains only
  patch-stable shared helpers.
- Added an early managed-tooltip registry and one isolated
  `TooltipDataProcessor` dispatcher.
- Removed the nonexistent `Enum.TooltipDataType.Action` assumption.
- Resolved pet-action, flyout, and macro spell context only from explicit fields
  or documented tooltip accessors.
- Limited spell-ID refresh to direct spell tooltips so aura and action-like
  tooltips are not converted into a different tooltip type.

### Modules and performance

- Hardened unit, target, model, status-bar, item, spell, quest, mount, expansion,
  ID, anchor, style, and extra-frame paths.
- Bounded and throttled inspect caching; inspect completion refreshes only the
  matching visible tooltip.
- Added a bounded 60-second Mythic+ summary cache to avoid duplicate API work on
  repeated unit hovers.
- Removed repeated mount-journal rescans on search-filter updates.
- Made item stack text idempotent across repeated processor callbacks.
- Moved context, style, faction-icon, anchor, mount, achievement, model, and
  status-text bookkeeping away from arbitrary Blizzard frame fields.
- Isolated the 3D model under `UIParent`; model operations stop in combat or
  restricted contexts.
- Corrected `PlayerModel:CanSetUnit()` handling: it has no documented return,
  while `SetUnit()` provides the authoritative success boolean.
- Fixed multi-line allocation, movement-speed return handling, raid/party zone
  tuple handling, inherited static anchor points, and inspect-cache accounting.
- Removed the nonfunctional `Targeted By` setting because implementing it would
  require broad compound-unit scans that conflict with the Retail 12.1 safety
  and performance model.

### Compatibility cleanup

- Removed `Compat_MoneyFrame.lua` and its global Blizzard function wrappers. The
  upstream MoneyFrame regressions tracked as WoWUIBugs #801 and #838 were closed
  as fixed on 2026-07-23.
- Removed obsolete local task files and one-time source-normalization artifacts.

### Documentation and verification

- Rewrote README, architecture, code index/graph, and agent guidance for the
  single active runtime.
- Added GitHub Actions checks for Lua 5.1 parsing, TOC/XML references, Markdown
  links, release metadata, load order, and data-boundary invariants.
- Live in-game verification remains tracked in issue #1.
