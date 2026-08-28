# Code graph

```mermaid
flowchart LR
  TOC[RothTooltip.toc] --> Safe[Engine/Safe.lua]
  Safe --> MM[Engine/ModuleManager.lua]
  MM --> Bus[LibEvent.7000]

  TOC --> Bootstrap[Engine/TooltipBootstrap.lua]
  Bootstrap --> Core[Core.lua legacy shared helpers]
  Core --> Midnight[Engine/Midnight.lua]
  Midnight --> Runtime[Engine/Runtime12_1.lua]
  Runtime --> Processor[Engine/TooltipProcessor.lua]

  Blizzard[Blizzard TooltipDataProcessor] --> Processor
  Processor --> Gates[canaccessvalue + C_Secrets]
  Gates --> Context[Sanitized primitive context]
  Context --> Bus

  General[General.lua] --> DB[RothTooltipDB / character DB]
  General --> Bus
  Bus --> Modules[Enabled feature modules]
  Modules --> Style[Engine/Style.lua]
  Style --> Tooltips[Managed tooltip frames]

  Options[Options.lua Settings and slash] --> DB
  Options --> Bus
  Doctor[Engine/Doctor.lua] --> MM
  Doctor --> Errors[/rtt diagnostics]
```

Raw `TooltipData`, `AuraData`, and `TooltipData.args` stop at the processor/sanitizer boundary. Feature modules receive only ordinary primitive context fields.
