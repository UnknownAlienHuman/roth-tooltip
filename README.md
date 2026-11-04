# Roth Tooltip

Roth-style tooltips with configurable unit presentation, item/spell icons, IDs, quest colors, mount sources, health text, cursor anchors and an independent model panel.

**Development target:** Retail 12.1.5 / Interface 120105, reviewed against the [engineering KB](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb). The KB-selected source baseline is `12.1.5.70688`; the later live source `12.1.5.70783` was scoped and does not change the inspected tooltip, Settings, TOC or model contracts used here. **Named-client validation is still pending; metadata and source review are not runtime certification.**

## Install and configure

The installed folder must be `Interface/AddOns/RothTooltip`, with `RothTooltip.toc` immediately inside it. The source tree is a development candidate, not a published release package.

Open Settings with `/tt`, `/tip` or `/tinytooltip`. Categories cover appearance, player/NPC elements, health bar, fonts, modules, profiles and the player layout editor. `/rtt errors` shows bounded diagnostics; `/rtt modules` shows module state. `/rtt enable <name>` and `/rtt disable <name>` use the same lifecycle as Settings.

Profiles are account-wide or per-character. Imports accept bounded RothTooltip JSON envelopes and validated legacy raw JSON. Decoded documents are access-gated and validated before commit; invalid/newer profiles are rejected without replacing active settings. Saved schema 3.3 preserves explicit false values and isolates mutable account/character defaults. Settings defaults come from the canonical schema, and structural profile/layout changes are refused in combat.

## Ownership and safety

There is one private event bus, one deterministic module activation order, one processor-registration owner, one managed-frame registry and one style owner. The mutable addon namespace remains file-local; no global LibStub replacement, legacy processor or patch-overlay runtime is loaded. LibSharedMedia is optional.

The processor consumes current, borrowed native data and emits only ordinary primitive fields. Unit identities are resolved and verified again at the point of use; no tooltip context, raw payload, unit token or native data-instance ID is cached for delayed refresh. Unknown access or secrecy answers deny enrichment, not native display.

Automatic refresh only repeats an exact supported standard getter/setter pair. Native bag, inventory, action and comparison paths retain their acquisition context and readiness handling. Some settings take effect on the next native display rather than converting those tooltips into generic item/spell tooltips.

Unit formatting edits semantic name/level rows; quest, owner, threat and unknown rows are not overwritten by positional assumptions. Party-zone lookups reuse a short-lived roster snapshot instead of scanning the roster for every hover. NPC titles remain native rather than exposing a dead duplicate setting. Item IDs have one owner (LinkID), and spell icons are added through owned text markup without hiding or repurposing native icon regions. Background inspection is throttled, owns and cancels its timeout, observes competing requests and never calls `ClearInspectPlayer`; disabling both item level and specialization disables its requests. The model has no layout or hierarchy dependency on native tooltips. Cursor anchoring re-evaluates current scale/quadrant, and DIY layout edits clone, validate and atomically replace at most sixteen rows. Disabled elements remain disabled even when modifier keys bypass filters.

## Development

Run `lua5.1 tests/integration.lua` and `python3 tools/check_repo.py`. Parse all Lua with `luac5.1 -p`. Pull requests and the manual static-check workflow run the same gates; no scheduled polling or source-export workflow is retained.

[Architecture](ARCHITECTURE.md) · [Code index](CODE_INDEX.md) · [Agent guide](AGENT_GUIDE.md) · [Test scope and client gate](tests/README.md).

Licensed under [MIT](LICENSE).
