# Validation

Run from the repository root:

```sh
lua5.1 tests/runtime.lua
find . -type f -name '*.lua' -not -path './.git/*' -print0 | xargs -0 -n 1 luac5.1 -p
python3 tools/check_repo.py
```

## Recorded focused run: 2026-11-03

`texlua tests/runtime.lua`: **59 PASS, Lua 5.3**. `texluac -p` accepted the nine changed runtime files and the test file. Git blob hashes of the published runtime/test files were checked against the locally tested bytes.

The harness loads complete Safe, ModuleManager, Doctor, Policy, Core, Style, Debug, Options/Core and Options files with explicit mocks. It covers tuple arity beyond sixteen results, nil/false preservation, denied access, subscription mutation and rollback, lifecycle failures/retry, error attribution, 1,000 enable/disable cycles, library-free loading, truthful Settings/slash outcomes, ten Settings categories, one shared-font update, stable visual hooks, feature-color preservation and native-region restoration.

The mocks do not implement WoW secret values, taint propagation, protected execution, native rendering or server behavior. This is not a full addon bootstrap test or a performance benchmark. Lua 5.1 execution, full-tree repository checks and the client matrix below were **NOT-RUN** in this environment. The run used a focused checkout of changed files; unchanged feature modules were not executed by this harness.

## Source and release boundary

Engineering reference: [KB tooltip owner](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb/blob/main/KB/nodes/BlizzardUI_Tooltip.md), selected source `Gethe/wow-ui-source@d07eb00237d8891f153215db98a5df880a26cfe5`, build `12.1.5.70688` (KB source check 2026-11-02). Relevant native object metadata is [SimpleFrameScriptObjectAPI](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFrameScriptObjectAPIDocumentation.lua).

The addon TOC remains `120100` / `12.1.0`; this focused refactor does not certify a completed 12.1.5 migration or a client build. Update release metadata only as part of the remaining migration/release validation.

## Required client checks

Record client build/Interface, addon commit, enabled addon set and error/taint logs for:

- Cold login and reload, addon-only and with optional media; account/character profiles, import/reset and repeated module toggles.
- Item, spell, action/macro, unit, aura, quest and comparison tooltips; colors after clear/show, rebuild, profile changes and extra-frame unregister.
- Combat, restriction changes, managed aura layout, second use after restricted display and Settings reopen; no repeating forbidden/taint/error loops.
- Modifier and inspect completion refresh, rapid owner/unit changes and inspect-UI coexistence; model layout/cleanup and cursor-follow teardown.
- Fractional UI scales and actual textures/fonts; measure CPU/allocation behavior before claiming a performance improvement.

Retain [issue #1](https://github.com/UnknownAlienHuman/roth-tooltip/issues/1) until its client matrix is completed. In particular, the historical raw-rebuild incident still requires reload, modifier changes, INSPECT_READY and settings/profile reapply without `UnitPlayerControlled` / `GameTooltip_UnitColor` failures.
