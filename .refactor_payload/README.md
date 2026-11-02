# Roth Tooltip

Modular tooltip customization for **World of Warcraft: Midnight Retail 12.1**.
Roth Tooltip styles Blizzard tooltips and adds configurable unit, item, spell,
quest, mount, ID, model, status-bar, and anchoring features.

**Version:** 12.1.0  
**Interface:** 120100  
**Author:** Neomorph  
**SavedVariables:** `RothTooltipDB`, `RothTooltipCharacterDB`

## Retail 12.1 safety model

Retail 12.1 can expose inaccessible values and restricted frame aspects in
tooltip, aura, unit, spell, model, and status-bar paths. Roth Tooltip therefore:

- gates values with `canaccessvalue` / `canaccessallvalues` before use;
- applies the relevant `C_Secrets` predicate before unit, aura, health, stats,
  cooldown, or unit-comparison work;
- normalizes raw `TooltipData` into an addon-owned primitive context;
- never forwards raw `AuraData` or tooltip argument vectors to feature modules;
- checks object access and forbidden script-binding aspects before frame hooks;
- fails closed when enrichment is restricted while leaving Blizzard's tooltip
  pipeline authoritative;
- refreshes only from an accessible unit token, item hyperlink, or direct spell
  tooltip ID and never replays cached raw payload.

The engineering source of truth is
[UnknownAlienHuman/wow-addon-engineering-kb](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb).
Patch-sensitive behavior must also be checked against current Blizzard generated
API documentation and live FrameXML.

## Install

Copy the `RothTooltip` directory to:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

Enable the addon and reload the UI.

## Configuration

Open Settings with `/tinytooltip`, `/tt`, or `/tip`.

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

## Runtime architecture

```text
Blizzard TooltipDataProcessor
  -> Engine/TooltipProcessor.lua
  -> Engine/Midnight.lua sanitizer and restriction gates
  -> weak per-tooltip primitive context
  -> LibEvent.7000
  -> enabled feature modules
  -> Engine/Style.lua visual output
```

`Engine/TooltipRegistry.lua` establishes the managed tooltip set before the
processor is registered and invalidates visible tooltip state when combat or
addon restriction policy changes. `Core.lua` contains only patch-stable
formatting, configuration, color/filter, and trigger glue. There is no legacy
parallel tooltip processor.

See [ARCHITECTURE.md](ARCHITECTURE.md), [CODE_INDEX.md](CODE_INDEX.md), and
[AGENT_GUIDE.md](AGENT_GUIDE.md).

## Verification status

CI parses every Lua file as Lua 5.1 and validates the TOC/XML graph, Markdown
links, runtime load order, release metadata, single-processor invariant, raw
payload boundary, and removal of obsolete compatibility paths.

Live client validation must still cover `/reload`, item/spell/unit/aura
surfaces, combat and restriction transitions, inspect completion, modifier
refresh, model display, status-bar behavior, Settings/profile operations, and
Doctor/taint output. The live matrix is tracked in
[issue #1](https://github.com/UnknownAlienHuman/roth-tooltip/issues/1).

## License

Licensed under the [MIT License](LICENSE). Bundled third-party components remain
under their own notices.
