# Code graph

```mermaid
flowchart LR
  TOC[RothTooltip.toc] --> Safe[Engine/Safe.lua]
  Safe --> Policy[Engine/Policy.lua]
  Safe --> MM[Engine/ModuleManager.lua]
  MM --> Bus[LibEvent.7000]

  TOC --> Core[Core.lua patch-stable helpers]
  Core --> Midnight[Engine/Midnight.lua]
  Midnight --> Style[Engine/Style.lua]
  Style --> Registry[Engine/TooltipRegistry.lua]
  Registry --> Processor[Engine/TooltipProcessor.lua]

  Blizzard[Blizzard TooltipDataProcessor] --> Processor
  Processor --> Gates[canaccessvalue + C_Secrets]
  Gates --> Context[Weak sanitized primitive context]
  Context --> Bus

  General[General.lua] --> DB[RothTooltipDB / character DB]
  General --> Bus
  Bus --> Modules[Enabled feature modules]
  Modules --> Style
  Style --> Tooltips[Managed Blizzard tooltips]

  Options[Options.lua] --> DB
  Options --> Bus
  Doctor[Engine/Doctor.lua] --> MM
  Doctor --> Errors[/rtt diagnostics]
```

Raw tooltip records, aura records, and argument vectors stop at the
processor/sanitizer boundary. Feature modules receive ordinary primitive
context only.
