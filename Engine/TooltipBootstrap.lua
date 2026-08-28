-- Retail 12.1 bootstrap
--
-- Core.lua still contains the legacy 12.0 TooltipDataProcessor bridge. Set its
-- idempotency flags before Core loads so that only Engine/TooltipProcessor.lua
-- registers post-calls. No Blizzard API or global function is replaced.

local _, addon = ...

addon.__RT_DeferTooltipProcessor = true
addon.__RT_TDPInitialized = true
addon.__RT_UseTDP = false
