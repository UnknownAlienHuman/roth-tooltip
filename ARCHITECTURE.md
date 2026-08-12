# Architecture

`Core.lua` wires the addon and the Engine layer. `Engine/ModuleManager.lua` attaches module callbacks to events; `Engine/Safe.lua`, `Engine/Policy.lua`, `Engine/Doctor.lua`, `Engine/Debug.lua`, and `Engine/Style.lua` provide safety, policy, diagnosis, and presentation concerns. Feature files implement tooltip-specific behaviours, while `General.lua` owns SavedVariables merge/migration. `Options.lua` registers settings and slash commands; `locales/` supplies localised strings.

TOC order loads libraries and the Engine before the feature modules and options. This permits shared manager/safety services to be available to later modules.
