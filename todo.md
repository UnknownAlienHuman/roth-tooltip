# RothTooltip TODO

Current incident as of 2026-03-13: the unit-tooltip refresh path entered Blizzard's `RebuildFromTooltipInfo()` with a secret unit payload and failed in `GameTooltip_UnitColor -> UnitPlayerControlled`.

## Root cause

- `RothTooltip/Core.lua` called `tip.RebuildFromTooltipInfo()` before attempting to restore the tooltip safely through `SetUnit()` / `SetHyperlink()`.
- This is unsafe for unit tooltips in Midnight: Blizzard line rules read `lineData.unitToken` again, and when the token is secret, `GameTooltip_UnitColor(unit)` fails at `UnitPlayerControlled(unit)`.
- The error was reproduced from `Unit.lua` on `MODIFIER_STATE_CHANGED`, but the same refresh path was also used elsewhere (`INSPECT_READY`, options apply, profile reapply).

## Tasks

- [x] Compare the stack trace with `TooltipDataRules.lua`, `GameTooltip.lua`, and `lookup_api("UnitPlayerControlled")`.
- [x] Change `RefreshTooltipSafe()` to prioritize safe restoration through `SetUnit()` / `SetHyperlink()`.
- [x] Block the fallback to `RebuildFromTooltipInfo()` for unit tooltips when safe refresh fails.
- [x] Run Lua static verification and inspect the diff limited to `RothTooltip`.

## Post-fix verification

- [ ] `/reload` without `UnitPlayerControlled` / `GameTooltip_UnitColor` errors.
- [ ] `MODIFIER_STATE_CHANGED` does not break an open unit tooltip.
- [ ] `INSPECT_READY` does not break an open unit tooltip.
- [ ] Applying settings or reapplying a profile does not break an open unit tooltip.

## Confirmed locally

- `RefreshTooltipSafe()` now first attempts to reopen the tooltip safely through `SetUnit()` / `SetHyperlink()`.
- For `Enum.TooltipDataType.Unit`, the code no longer falls back to `RebuildFromTooltipInfo()` after safe refresh fails.
- `lookup_api("UnitPlayerControlled")` confirms that the API expects a `UnitToken`, not a secret value in tainted execution.
- `npx -y luaparse _Addons/RothTooltip/Core.lua` completed successfully.
- `git diff --check -- _Addons/RothTooltip` completed without errors.
