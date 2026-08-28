# Roth Tooltip

Modular tooltip customization for **World of Warcraft: Midnight Retail 12.1**. Roth Tooltip styles Blizzard tooltips and adds configurable unit, item, spell, quest, mount, ID, model, status-bar, and anchoring features.

**Version:** 12.1.0  
**Interface:** 120100  
**Author:** Neomorph  
**SavedVariables:** `RothTooltipDB`, `RothTooltipCharacterDB`

## Retail 12.1 data-safety model

Retail 12.1 can return inaccessible values from tooltip, aura, unit, spell, model, and status-bar paths. Roth Tooltip treats those values as capabilities rather than ordinary Lua data:

- `canaccessvalue` / `canaccessallvalues` gate data before branching, indexing, formatting, comparison, or storage;
- `C_Secrets` predicates gate aura, unit identity, unit stats, health, cooldown, and unit-token comparison paths;
- raw `TooltipData` is normalized at one boundary into an ordinary primitive context;
- raw `AuraData` and `TooltipData.args` are not forwarded to feature modules;
- restricted enrichment fails closed while the Blizzard-owned tooltip remains usable;
- tooltip refresh uses an accessible unit token, hyperlink, or spell ID and never replays restricted raw payload.

The implementation follows the project engineering knowledge base: [wow-addon-engineering-kb](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb).

## Install

Copy the `RothTooltip` directory to:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

Enable the addon and reload the UI.

## Configuration

Open Settings with `/tinytooltip`, `/tt`, or `/tip`.

The settings command supports `reset`, `npc`, `npc-elements`, `player`, `player-elements`, `spell`, `statusbar`, `font`, `modules`, and `data`.

Diagnostics use `/rtt`:

```text
/rtt help
/rtt errors
/rtt export
/rtt modules
/rtt enable <module>
/rtt disable <module>
/rtt toggle <module>
/rtt clear
```

## Architecture

The active 12.1 pipeline is:

```text
TooltipDataProcessor
  -> Engine/TooltipProcessor.lua
  -> Engine/Midnight.lua sanitized context
  -> LibEvent.7000
  -> enabled feature modules
  -> Engine/Style.lua visual output
```

`Engine/TooltipBootstrap.lua` prevents the legacy 12.0 processor in `Core.lua` from registering. `Engine/Runtime12_1.lua` applies focused compatibility corrections after the legacy core loads. Module registration and detach-on-disable behavior remain centralized in `Engine/ModuleManager.lua`.

See [ARCHITECTURE.md](ARCHITECTURE.md), [CODE_INDEX.md](CODE_INDEX.md), and [AGENT_GUIDE.md](AGENT_GUIDE.md).

## Verification status

Static syntax, manifest, and policy checks are automated in CI. Live client validation must still cover `/reload`, item/spell/unit/aura tooltips, combat restrictions, inspect completion, model display, modifier refresh, Settings/profile operations, and Doctor output. The tracked live checklist is [issue #1](https://github.com/UnknownAlienHuman/roth-tooltip/issues/1).

## License

Licensed under the [MIT License](LICENSE). Bundled third-party components remain under their own notices.
