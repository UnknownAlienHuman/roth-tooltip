# Validation

Run from the repository root:

```sh
lua5.1 tests/integration.lua
find . -type f -name '*.lua' -not -path './.git/*' -print0 | xargs -0 -n 1 luac5.1 -p
python3 tools/check_repo.py
git diff --check
```

## Recorded validation run — 2026-11-04

**134 tests PASS on Lua 5.1.5.** `tests/integration.lua` includes 68 runtime checks, then executes all Lua files in TOC/XML-include order with explicit API/frame/Settings mocks. It covers cold bootstrap with late SavedVariables, four locales, all twelve modules, deterministic/reentrant lifecycle behavior, pending-subscriber isolation, canonical Settings domains/defaults, exact-path profile migration, table-access order, sparse-layout rejection, fresh and denied contexts, source-preserving refresh, semantic rows and right columns, non-invasive spell decoration, model layout/cleanup, owned inspect timeouts and races, live cursor quadrant updates, detached DIY transactions, registry/style ownership, late optional media, profile-to-Settings resynchronization, slash/API module transitions, semantic raid-difficulty selection, cursor-anchor fallback and full-bootstrap module toggling. The runtime suite also runs 1,000 enable/disable cycles.

All runtime and test Lua files pass `luac5.1 -p`. The whole-tree manifest/XML graph, local Markdown links, loaded-file and single-owner checks pass. No unreferenced runtime Lua, obsolete patch-rewriting scripts, empty loader, legacy runtime overlays or temporary source-export workflow remain.

The complete **Lua bootstrap** is tested, not a real WoW startup. Native XML templates, Secret Values, taint propagation, protected execution, server responses, rendering and profiler measurements are not emulated. Those client-dependent claims remain **NOT-RUN**.

## Source contract

KB-selected baseline: `Gethe/wow-ui-source@d07eb00237d8891f153215db98a5df880a26cfe5`, Retail `12.1.5.70688`. The direct live successor `297d7aaaa736f346b3e036f38ee088eaf7f8c07f` / `12.1.5.70783` was scoped on 2026-11-04; its changed files do not include the tooltip, Settings, TOC or model slices used here. Consult the [KB tooltip owner](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb/blob/main/KB/nodes/BlizzardUI_Tooltip.md), [ownership guide](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb/blob/main/KB/addon/Tooltip_Addon_Ownership_Audit_12.1.5.md), [persistence guide](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb/blob/main/KB/addon/Addon_SavedVariables.md) and both current overlays before patch-sensitive changes.

Inspected platform slices: `TooltipDataHandler.lua:AddTooltipPreCall/AddTooltipPostCall/InternalProcessInfo`, `TooltipUtil.lua:GetDisplayedItem/GetDisplayedSpell/GetDisplayedUnit`, `TooltipInfoSharedDocumentation.lua:TooltipDataLineType/TooltipDataType`, `SimpleFrameScriptObjectAPIDocumentation.lua` access/forbidden-aspect queries, and `FrameAPICharacterModelBaseDocumentation.lua:CanSetUnit/SetUnit` at the selected source pin.

The selected Interface family is 120105 and the TOC declares 12.1.5 / 120105. Client `GetBuildInfo()` is still NOT-RUN, so this metadata does not certify runtime behavior. Saved profile schema 3.3 is a separate version.

## Client release gate

Keep [issue #1](https://github.com/UnknownAlienHuman/roth-tooltip/issues/1) open. Record client build/Interface, addon commit, enabled addon set and error/taint logs for:

- Cold login/reload with and without media; account/character profiles, bounded JSON import/export round trip, reset and repeated toggles.
- Item/spell/macro/unit/aura/quest/comparison displays; uncached items, rapid owner changes, semantic name/level behavior, both columns and preserved objectives. Confirm spell icons do not hide or corrupt native icon/border regions and removed NPC-title/item-quality unit settings do not reappear.
- Combat, restriction transitions, managed aura layout and post-restriction second use; no repeating forbidden/taint/error loops.
- Modifier and INSPECT_READY refresh, pending timeout, competing inspection, Inspect UI coexistence; no `UnitPlayerControlled` / `GameTooltip_UnitColor` failures from the historical raw-rebuild incident.
- Multiple saved lockouts for the same raid (Mythic/Heroic/Normal/Raid Finder/Story where available); the displayed entry follows client difficulty semantics rather than numeric ID magnitude.
- Independent cursor/model panel at fractional UI scales, unavailable-cursor fallback before `ANCHOR_NONE`, cleanup on hidden/replaced frames, native texture/font rendering, Settings/profile dialogs and DIY drag/drop. Check failed/stale/combat drops leave the active layout byte-for-byte unchanged and successful drops replace it once.
- Real CPU/allocation measurements before claiming measured performance gains; then promote release metadata only for the validated client range.
