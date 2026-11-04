# Validation

Run from the repository root:

```sh
lua5.1 tests/integration.lua
find . -type f -name '*.lua' -not -path './.git/*' -print0 | xargs -0 -n 1 luac5.1 -p
python3 tools/check_repo.py
git diff --check
```

## Recorded local run — 2026-11-03

**97 tests PASS on Lua 5.1.5.** `tests/integration.lua` includes the original 59 runtime checks, then executes all Lua files in TOC/XML-include order with explicit API/frame/Settings mocks. It covers cold bootstrap with late SavedVariables, four locales, all twelve modules, profile migration/import/isolation/limits, fresh and denied contexts, source-preserving refresh, semantic rows and right columns, model layout/cleanup, inspect ownership/races, cursor/mount cancellation and full-bootstrap module toggling. The original suite also runs 1,000 enable/disable cycles.

All runtime and test Lua files pass `luac5.1 -p`. The whole-tree manifest/XML graph, local Markdown links, loaded-file and single-owner checks pass. No unreferenced runtime Lua, obsolete patch-rewriting scripts, empty loader, legacy runtime overlays or temporary source-export workflow remain.

The complete **Lua bootstrap** is tested, not a real WoW startup. Native XML templates, Secret Values, taint propagation, protected execution, server responses, rendering and profiler measurements are not emulated. Those client-dependent claims remain **NOT-RUN**.

## Source contract

Selected source: `Gethe/wow-ui-source@d07eb00237d8891f153215db98a5df880a26cfe5`, Retail `12.1.5.70688`; live version rechecked 2026-11-03. Consult the [KB tooltip owner](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb/blob/main/KB/nodes/BlizzardUI_Tooltip.md), [ownership guide](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb/blob/main/KB/addon/Tooltip_Addon_Ownership_Audit_12.1.5.md), [persistence guide](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb/blob/main/KB/addon/Addon_SavedVariables.md) and both current overlays before patch-sensitive changes.

Inspected platform slices: `TooltipDataHandler.lua:AddTooltipPreCall/AddTooltipPostCall/InternalProcessInfo`, `TooltipUtil.lua:GetDisplayedItem/GetDisplayedSpell/GetDisplayedUnit`, `TooltipInfoSharedDocumentation.lua:TooltipDataLineType/TooltipDataType`, `SimpleFrameScriptObjectAPIDocumentation.lua` access/forbidden-aspect queries, and `FrameAPICharacterModelBaseDocumentation.lua:CanSetUnit/SetUnit` at the selected source pin.

The expected Interface family is 120105, but client `GetBuildInfo()` is NOT-RUN. TOC release metadata stays 120100 / 12.1.0 until the named-client release gate; saved profile schema 3.3 is a separate version.

## Client release gate

Keep [issue #1](https://github.com/UnknownAlienHuman/roth-tooltip/issues/1) open. Record client build/Interface, addon commit, enabled addon set and error/taint logs for:

- Cold login/reload with and without media; account/character profiles, bounded JSON import/export round trip, reset and repeated toggles.
- Item/spell/macro/unit/aura/quest/comparison displays; uncached items, rapid owner changes, semantic name/level/NPC-title behavior, both columns and preserved objectives. Check settings which intentionally wait for the next native display.
- Combat, restriction transitions, managed aura layout and post-restriction second use; no repeating forbidden/taint/error loops.
- Modifier and INSPECT_READY refresh, pending timeout, competing inspection, Inspect UI coexistence; no `UnitPlayerControlled` / `GameTooltip_UnitColor` failures from the historical raw-rebuild incident.
- Independent cursor/model panel at fractional UI scales, cleanup on hidden/replaced frames, native texture/font rendering, Settings/profile dialogs and DIY drag/drop.
- Real CPU/allocation measurements before claiming measured performance gains; then promote release metadata only for the validated client range.
