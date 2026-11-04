# Roth Tooltip

Roth-style tooltips with configurable unit presentation, item/spell icons, IDs, quest colors, mount sources, health text, cursor anchors and an independent model panel.

**Development source target:** Retail 12.1.5.70688, reviewed 2026-11-03 against the [engineering KB](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb). **Client validation is pending.** Release metadata remains 12.1.0 / Interface 120100 until the named-client gate is completed; this branch is not a certified 12.1.5 release.

## Install and configure

The installed folder must be `Interface/AddOns/RothTooltip`, with `RothTooltip.toc` immediately inside it. The source tree is a development candidate, not a published release package.

Open Settings with `/tt`, `/tip` or `/tinytooltip`. Categories cover appearance, player/NPC elements, health bar, fonts, modules, profiles and the player layout editor. `/rtt errors` shows bounded diagnostics; `/rtt modules` shows module state. `/rtt enable <name>` and `/rtt disable <name>` use the same lifecycle as Settings.

Profiles are account-wide or per-character. Imports accept bounded RothTooltip JSON envelopes and validated legacy raw JSON. Invalid/newer profiles are rejected without replacing active settings. Saved schema 3.3 preserves explicit false values and isolates mutable account/character defaults. Structural profile changes are refused in combat.

## Ownership and safety

There is one private event bus, one processor-registration owner, one managed-frame registry and one style owner. No global LibStub replacement, legacy processor or patch-overlay runtime is loaded. LibSharedMedia is optional.

The processor consumes current, borrowed native data and emits only ordinary primitive fields. Unit identities are resolved and verified again at the point of use; no tooltip context, raw payload, unit token or native data-instance ID is cached for delayed refresh. Unknown access or secrecy answers deny enrichment, not native display.

Automatic refresh only repeats an exact supported standard getter/setter pair. Native bag, inventory, action and comparison paths retain their acquisition context and readiness handling. Some settings take effect on the next native display rather than converting those tooltips into generic item/spell tooltips.

Unit formatting edits semantic name/level rows; quest, owner, threat and unknown rows are not overwritten by positional assumptions. NPC titles remain native. Item IDs have one owner (LinkID), and the obsolete private achievement-scroll hook is removed. Background inspection is throttled, observes competing requests and never calls `ClearInspectPlayer`; disabling both item level and specialization disables its requests. The model has no layout or hierarchy dependency on native tooltips.

## Development

Run `lua5.1 tests/integration.lua` and `python3 tools/check_repo.py`. Parse all Lua with `luac5.1 -p`. The manual static-check workflow runs the same gates; no scheduled polling or source-export workflow is retained.

[Architecture](ARCHITECTURE.md) · [Code index](CODE_INDEX.md) · [Agent guide](AGENT_GUIDE.md) · [Test scope and client gate](tests/README.md).

Licensed under [MIT](LICENSE).
