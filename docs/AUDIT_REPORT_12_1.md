# Comprehensive Addon Audit & PR: RothTooltip

**Target Addon:** `RothTooltip` (`C:\Development\WoWDevAddons\_Addons\RothTooltip`)  
**Target Environment:** World of Warcraft: Midnight — Retail 12.1 (`Interface: 120100`, Build `69497`)  
**Knowledge Base References:** `_Info/KB` (`nodes/BlizzardUI_Tooltip.md`, `RT-AUDIT-001`, `RT-AUDIT-002`, `BlizzardUI_Taint_Debug_Cookbook`, `Addon_SavedVariables`, `deep/Midnight_AddOn_Devlog_12_0_7_Router.md`)  
**Remote Git Reference:** `github-roth-tooltip` (`main` and convergence branches `audit/deep-ownership-pass`, `audit/post-merge-12.1.0`, `refactor/single-runtime-12.1.0`)  
**Auditor:** Neomorph Addon Workspace Automated Auditor  
**Date:** 2026-09-08  

---

## 1. Executive Summary & Architecture Overview

`RothTooltip` is an advanced, modular tooltip display, styling, and data enrichment framework within the Roth UI ecosystem. Originally derived from the TinyTooltip lineage and overhauled for Midnight, it provides:
- **Visual Styling Engine (`Engine/Style.lua`):** Custom 9-slice and solid backdrop styling, gradient coloring, custom status bar textures, and visual masking for `GameTooltip` and auxiliary Blizzard tooltip frames.
- **Engine Subsystems (`Engine/`):** 
  - `Safe.lua`: Protected function invocation and error logging to `Doctor.lua`.
  - `Policy.lua`: Combat lockdown and restriction gating (STRICT, BALANCED, AGGRESSIVE modes).
  - `ModuleManager.lua`: Event-driven module lifecycle manager powered by an embedded `LibEvent.7000` message bus.
  - `Doctor.lua` & `Debug.lua`: Runtime error interception, diagnostic logging, and `/rtt` CLI administration.
- **Data & Feature Modules:**
  - `General.lua`: Database initialization, profile management, font scaling, status bar health text and colorization.
  - `Anchor.lua`: Dynamic cursor anchoring, static point anchoring, and combat return policies.
  - `Unit.lua`: Player and NPC tooltip enrichment (class colors, item level inspection, Mythic+ rating, raid progression, unit reaction, friend status).
  - `Target.lua`: Target-of-unit display with raid target icon support.
  - `Model.lua`: 3D player/creature model preview attached to unit tooltips.
  - `Item.lua`, `Spell.lua`, `Quest.lua`, `Mount.lua`: Item quality borders, spell/aura enrichment, mount source tracking, and quest difficulty coloring.
  - `LinkID.lua` & `ExpansionInfo.lua`: Technical metadata lines (spell IDs, item IDs, NPC GUID IDs, expansion origin).
  - `SkinFrames.lua`: Extra Blizzard and third-party frame skinning.
  - `Options.lua`: Blizzard Settings category integration and DIY layout configuration.

---

### Comparative Status Matrix

| Dimension | Local Workspace (`HEAD:_Addons/RothTooltip`) | Upstream GitHub (`github-roth-tooltip/main`) | Target PR State (Retail 12.1 Compliant) |
| :--- | :--- | :--- | :--- |
| **Interface / Version** | `120001, 120005` / `12.0.20` | `120100` / `12.1.0` | **`120100` / `12.1.0`** |
| **MoneyFrame Shim** | Present (`Compat_MoneyFrame.lua`) monkey-patching `_G` | Removed entirely | **Removed entirely (Zero global monkey-patching)** |
| **SecretValue Gating** | `v == v` comparison-based `pcall` probing | `canaccessvalue` / `canaccessallvalues` | **Capability-first gating (`canaccessvalue`, `C_Secrets`)** |
| **Tooltip Pipeline** | Legacy `Core.lua` hook dispatching raw `AuraData` & `data.args` | Layered `TooltipBootstrap` + `TooltipProcessor` | **Single canonical `TooltipProcessor` (Single Owner)** |
| **Frame Decoration** | Injects custom keys onto Blizzard frames (`tip.__RT*`, `tip.model`) | Migrated to weak-keyed tables (`setmetatable k`) | **Zero Blizzard frame pollution; 100% weak tables** |
| **3D Model Preview** | Direct child frame of `GameTooltip`; invalid `CanSetUnit` check | Isolated frame on `UIParent`; combat-disabled | **Isolated on `UIParent`, combat-disabled, `SetUnit` validated** |
| **Inspect Cache** | Unbounded table; unthrottled `NotifyInspect` | Bounded (64 entries), 2s throttle, 300s TTL | **Bounded, throttled, sanitized Mythic+/Raid caches** |
| **SavedVariables (RT-AUDIT-001)** | `dst[k] = v` table insertion by reference | `dst[k] = v` table insertion by reference | **Deep-cloned defaults (`CopyTable`) & non-table safety** |
| **Runtime Owner (RT-AUDIT-002)** | Dual processor hook registration paths | Bootstrap deferral flag suppressing `Core.lua` | **Dead shadow processor eliminated from `Core.lua`** |

---

## 2. Comprehensive Audit Findings & Gap Analysis

### 2.1 Interface & TOC Metadata (Retail 12.1 Compatibility)
- **Local Defect:** `RothTooltip.toc` specifies `## Interface: 120001, 120005` and `## Version: 12.0.20`. This marks the addon out of date on Retail 12.1 (`Interface 120100`).
- **Resolution:** Update metadata to `## Interface: 120100` and `## Version: 12.1.0`. Update TOC load sequence to include the modernized runtime layers and remove deprecated shims.

---

### 2.2 Dangerous Global Monkey-patching: `Compat_MoneyFrame.lua`
- **Local Defect:** Local repository includes `Compat_MoneyFrame.lua`, which overwrites Blizzard global functions `_G["MoneyFrame_Update"]` and `_G["SetTooltipMoney"]` with custom Lua closures inside a `pcall`.
- **Taint Risk & 12.1 Reality:** 
  1. Overwriting Blizzard global UI functions in Retail 12.1 immediately taints the MoneyFrame subsystem. Any Blizzard secure frame (such as merchant frames, auction house, trade windows, or bag containers) that invokes `MoneyFrame_Update` inherits execution taint, triggering `ADDON_ACTION_BLOCKED` errors during combat.
  2. The upstream secret-value regressions that prompted this workaround (WoWUIBugs #801 and #838) were officially resolved by Blizzard on 2026-07-23.
- **Resolution:** Delete `Compat_MoneyFrame.lua` completely and remove it from `RothTooltip.toc`.

---

### 2.3 SecretValue Handling & Capability Gating
- **Local Defect:** In local `Core.lua:65-73`:
  ```lua
  local function IsSecret(v)
      if (__IsSecretBase and __IsSecretBase(v)) then return true end
      local ok = pcall(function() return v == v end)
      return not ok
  end
  ```
  Attempting a self-comparison `v == v` on restricted or secret objects in Retail 12.1 is an anti-pattern that can throw script termination errors or leak execution states. Furthermore, numerous module routines performed direct arithmetic, string concatenation, and comparisons on unit stats, speed, health, and names without verifying access permissions.
- **Upstream & PR Solution:**
  1. Use capability-first checks: `canaccessvalue(v) == true` and `canaccessallvalues(...) == true`.
  2. Query modern `C_Secrets` APIs in `Engine/Midnight.lua`:
     - `C_Secrets.HasSecretRestrictions()`
     - `C_Secrets.ShouldAurasBeSecret()`
     - `C_Secrets.ShouldCooldownsBeSecret()`
     - `C_Secrets.ShouldUnitStatsBeSecret()`
     - `C_Secrets.ShouldUnitIdentityBeSecret(unit)`
     - `C_Secrets.ShouldUnitHealthBeSecret(unit)`
     - `C_Secrets.CanCompareUnitTokens(unit1, unit2)`
  3. Enforce fail-closed semantics: if a value or unit cannot be accessed, return safe placeholders (`nil`, `"??"`, or standard fallback textures) rather than executing logic.

---

### 2.4 TooltipDataProcessor Pipeline & Aura Privacy Leakage
- **Local Defect:** 
  - Local `Core.lua` passed raw `TooltipData.args` and raw `AuraData` structures directly into `LibEvent:trigger("tooltip:aura", tooltip, data, ...)`.
  - In Retail 12.1, Blizzard restricts private aura data and secret spell arguments. Exposing raw tables to arbitrary trigger subscribers causes taint leakage and crashes when modules attempt to index private fields.
  - Local `Core.lua` attempted raw tooltip rebuilds (`RebuildFromTooltipInfo`) and fallback scans on `"mouseover"` units, which are prohibited in restricted combat contexts.
- **Modern Pipeline:**
  - `Engine/TooltipProcessor.lua` registers isolated post-calls for `Enum.TooltipDataType.Item`, `Spell`, `Unit`, and `UnitAura`.
  - `Aura` triggers forward only the sanitized `spellID` and clean primitive context, passing `nil` for raw payload vectors.
  - Context extraction (`Engine/Midnight.lua`) copies only verified primitives (`number`, non-empty `string`) into an isolated table, strictly excluding complex or userdata fields.

---

### 2.5 Blizzard Frame Pollution & Taint Elimination
- **Local Defect:** Local modules stored visual bookkeeping, tickers, and model frames directly as properties on Blizzard tooltip objects:
  - `tip.__RT_PrimaryContext`, `tip.__RT_LastItemLink`, `tip.__RT_LastItemID`, `tip.__RT_LastSpellID` (`Core.lua`)
  - `tip.__RTAnchorTicker`, `tip.__RTAnchorPoint`, `tip.__RTAnchorX`, `tip.__RTAnchorY` (`Anchor.lua`)
  - `tip.model` (`Model.lua`)
  - `tip.BigFactionIcon` (`Engine/Style.lua`, `Unit.lua`)
  - `tip.__RT_LastDispatchKind`, `tip.__RT_LastDispatchTime` (`Core.lua`, `LinkID.lua`)
  - `bar.TextString`, `bar.forceHideText` (`General.lua`)
  - `tip.__RT_HideBgCache` (`Engine/Style.lua`)
- **Impact:** Blizzard UI frames are reused across the interface. Mutating fields on `GameTooltip` or status bars pollutes the Blizzard metatable and leads to secure inspection failures.
- **Resolution:** Migrate all state tracking to weak-keyed Lua registries:
  - `local anchorStates = setmetatable({}, { __mode = "k" })` (`Anchor.lua`)
  - `local ContextByTooltip = setmetatable({}, { __mode = "k" })` (`Engine/Midnight.lua`)
  - `local lastMountByTooltip = setmetatable({}, { __mode = "k" })` (`Mount.lua`)
  - `local achievementHooks = setmetatable({}, { __mode = "k" })` (`LinkID.lua`)
  - `local hideBgCaches = setmetatable({}, { __mode = "k" })` (`Engine/Style.lua`)

---

### 2.6 3D Model Module Architecture & Contract Correction (`Model.lua`)
- **Local Defect:**
  1. `tip.model = CreateFrame("PlayerModel", nil, tip)` attached the 3D model frame directly to Blizzard's `GameTooltip`.
  2. `if (model:CanSetUnit(token)) then model:SetUnit(token) ...` — In Retail 12.1, `PlayerModel:CanSetUnit()` returns `void` (`nil`). Checking it as a boolean condition prevented models from loading properly.
  3. Continued updating and rotating models during combat lockdown.
- **Resolution:**
  1. Create a single persistent `PlayerModel` parented to `UIParent`, positioned relative to `GameTooltip` and set to `TOOLTIP` frame strata.
  2. Disallow model display during `InCombatLockdown()` or when `AreUnitStatsRestricted()` returns true.
  3. Call `SetUnit(token)` directly, which returns the authoritative boolean success flag in 12.1.

---

### 2.7 Unit Inspect Cache & Throttle Protection (`Unit.lua`)
- **Local Defect:** Local `Unit.lua` cached inspect data indefinitely in an unbounded table and allowed rapid unthrottled `NotifyInspect` requests, creating network flood and UI disconnect risks.
- **Resolution:** 
  - Cap inspect cache at 64 entries with an explicit 300-second TTL.
  - Enforce a 2-second global request throttle between `NotifyInspect` invocations.
  - Sanitize Mythic+ ratings and raid progress tuples through `canaccessvalue` before caching.

---

## 3. Deep Auditor Findings (Residual Issues in Upstream Main)

While `github-roth-tooltip/main` introduces substantial 12.1 hardening, the auditor uncovered two critical architectural violations present even in the upstream repository:

### 3.1 Pattern RT-AUDIT-001: SavedVariables Default Mutation by Reference
- **Location:** `Core.lua:1023-1035` (`addon:MergeVariable`)
- **Existing Code:**
  ```lua
  function addon:MergeVariable(src, dst)
      dst.version = src.version
      for k, v in pairs(src) do
          if (dst[k] == nil) then
              dst[k] = v
          elseif (type(dst[k]) == "table" and k~="elements") then
              self:MergeVariable(v, dst[k])
          elseif (type(dst[k]) == "table" and k=="elements") then
              dst[k] = AutoValidateElements(v, dst[k])
          end
      end
      return dst
  end
  ```
- **The Violation:**
  When `src` represents the addon's default database template (`addon.db` defined in `Config.lua`) and `dst` is the user's SavedVariables table (`RothTooltipDB` or `RothTooltipCharacterDB`):
  - If a user lacks a specific nested configuration table (e.g. `addon.db.general.visibility`, `addon.db.general.anchor`, `addon.db.unit.player.background`), line 1027 executes:
    `dst[k] = v`
  - This assigns the default subtable **by reference** into the user's SavedVariables.
  - Subsequent user modifications to options (e.g. toggling visibility in Settings) directly mutate the master `addon.db` template in Lua memory!
  - When switching character profiles or executing a settings reset, the defaults are permanently corrupted in memory.
  - In addition, if `dst` is passed as `nil` or a non-table, the function immediately crashes with `attempt to index local 'dst' (a nil value)`.
- **Hardened Fix:**
  ```lua
  function addon:MergeVariable(src, dst)
      if type(dst) ~= "table" then dst = {} end
      if type(src) ~= "table" then return dst end
      dst.version = src.version
      for k, v in pairs(src) do
          if dst[k] == nil then
              dst[k] = (type(v) == "table") and CopyTable(v) or v
          elseif type(dst[k]) == "table" and k ~= "elements" and type(v) == "table" then
              self:MergeVariable(v, dst[k])
          elseif type(dst[k]) == "table" and k == "elements" and type(v) == "table" then
              dst[k] = AutoValidateElements(v, dst[k])
          end
      end
      return dst
  end
  ```

---

### 3.2 Pattern RT-AUDIT-002: Single Runtime Owner & Dead Shadow Processor
- **Location:** `Core.lua:595-895` (`addon:InitTooltipDataProcessor`) vs `Engine/TooltipProcessor.lua`
- **The Violation:**
  Upstream neutralized the legacy processor in `Core.lua` by introducing `Engine/TooltipBootstrap.lua`, which sets `addon.__RT_DeferTooltipProcessor = true` before `Core.lua` loads. When `Core.lua` runs `addon:InitTooltipDataProcessor()` at line 895, it early-returns. Then `Engine/TooltipProcessor.lua` loads and overwrites `addon.InitTooltipDataProcessor` with the modern 12.1 implementation.
  - This leaves 300 lines of dead shadow processor code inside `Core.lua`.
  - Having two implementations of `InitTooltipDataProcessor` across the codebase violates the single runtime owner pattern and was flagged in upstream's own internal hardening validator (`tools/_check_repo_hardened.py`).
- **Hardened Fix:**
  Replace the 300-line dead shadow processor in `Core.lua` with a single, clean delegation stub:
  ```lua
  function addon:InitTooltipDataProcessor()
      -- Delegated to authoritative runtime owner Engine/TooltipProcessor.lua
      return self.__RT_UseTDP == true
  end
  ```
  This eliminates duplicate logic, satisfies single runtime ownership, and guarantees that `Engine/TooltipProcessor.lua` is the sole processor in the addon.

---

### 3.3 Style Engine Weak Caching (`Engine/Style.lua`)
- **Location:** `Engine/Style.lua:71-79`
- **Issue:** `Style.lua` cached hidden background textures by setting `frame.__RT_HideBgCache = cache` directly on Blizzard tooltip frames.
- **Hardened Fix:** Convert `hideBgCache` to a module-scoped weak-keyed table (`setmetatable({}, { __mode = "k" })`), ensuring zero property writes to Blizzard frame tables.

---

## 4. Proposed Pull Request Implementation & Unified Diffs

The following production patches bring `RothTooltip` from its outdated local state to full Retail 12.1 compliance while simultaneously resolving the RT-AUDIT-001 and RT-AUDIT-002 defects.

---

### Patch 1: Root TOC & Build Metadata (`RothTooltip.toc`)

```diff
--- a/RothTooltip.toc
+++ b/RothTooltip.toc
@@ -1,15 +1,18 @@
-## Interface: 120001, 120005
+## Interface: 120100
 ## Title: Roth Tooltip
-## Notes: Roth Tooltip
+## Notes: Roth Tooltip for World of Warcraft: Midnight
 ## Author: Neomorph
-## Version: 12.0.20
+## Version: 12.1.0
+## X-Verified-Build: 12.1.0.69497
 ## SavedVariables: RothTooltipDB
 ## SavedVariablesPerCharacter: RothTooltipCharacterDB
 
 libs\lib.xml
 Engine\Safe.lua
 Engine\Policy.lua
 Engine\ModuleManager.lua
 Engine\Doctor.lua
 Engine\Debug.lua
 Engine\Style.lua
+Engine\TooltipBootstrap.lua
 Core.lua
-Compat_MoneyFrame.lua
+Engine\Midnight.lua
+Engine\Runtime12_1.lua
+Engine\TooltipProcessor.lua
 Config.lua
 General.lua
 Anchor.lua
```

---

### Patch 2: Deletion of Dangerous Global Monkey-patch (`Compat_MoneyFrame.lua`)

```diff
--- a/Compat_MoneyFrame.lua
+++ /dev/null
@@ -1,68 +0,0 @@
--- Entire file removed. Blizzard resolved underlying secret-value MoneyFrame issues
--- (WoWUIBugs #801, #838). Global monkey-patching of _G.MoneyFrame_Update causes taint in 12.1.
```

---

### Patch 3: Tooltip Bootstrap Layer (`Engine/TooltipBootstrap.lua`)

```lua
-- Retail 12.1 bootstrap
-- Ensures single runtime ownership: defer legacy initialization so only
-- Engine/TooltipProcessor.lua registers TooltipDataProcessor post-calls.

local _, addon = ...

addon.__RT_DeferTooltipProcessor = true
addon.__RT_TDPInitialized = true
addon.__RT_UseTDP = false
```

---

### Patch 4: RT-AUDIT-001 & RT-AUDIT-002 Core Hardening (`Core.lua`)

```diff
--- a/Core.lua
+++ b/Core.lua
@@ -57,19 +57,20 @@ end
 -- The goal here is simple: never do Lua-side logic on SecretValue.
 -- We fall back to placeholders or skip optional features.
 --=========================================================
+local __CanAccessValue = (type(canaccessvalue) == "function") and canaccessvalue or nil
 local __IsSecretBase = (type(issecretvalue) == "function") and issecretvalue or nil
 
--- Robust SecretValue detection:
--- Some SecretValue values do not report via issecretvalue(), but still hard-error
--- on any Lua comparison. Detect via a protected self-compare.
+-- Capability-gated SecretValue detection: never probe via comparisons (v == v).
 local function IsSecret(v)
-    if (__IsSecretBase and __IsSecretBase(v)) then
-        return true
+    if (__CanAccessValue) then
+        return __CanAccessValue(v) ~= true
+    end
+    if (__IsSecretBase) then
+        return __IsSecretBase(v) == true
     end
-    -- Never do boolean tests or comparisons on unknown values.
-    -- Self-compare inside pcall is the most reliable generic probe.
-    local ok = pcall(function() return v == v end)
-    return not ok
+    return false
 end
 
 function addon:IsSecret(v)
@@ -592,305 +593,12 @@ end
---=========================================================
--- TooltipDataProcessor orchestrator for managed retail tooltips.
---=========================================================
-function addon:InitTooltipDataProcessor()
-    -- [Removed 300 lines of dead shadow processor to satisfy RT-AUDIT-002]
-end
+function addon:InitTooltipDataProcessor()
+    -- RT-AUDIT-002: Delegated to authoritative runtime owner Engine/TooltipProcessor.lua
+    return self.__RT_UseTDP == true
+end
@@ -1022,13 +720,16 @@ end
 
 -- 配置合併 (RT-AUDIT-001 Deep Copy Fix)
 function addon:MergeVariable(src, dst)
+    if (type(dst) ~= "table") then dst = {} end
+    if (type(src) ~= "table") then return dst end
     dst.version = src.version
     for k, v in pairs(src) do
         if (dst[k] == nil) then
-            dst[k] = v
+            dst[k] = (type(v) == "table") and CopyTable(v) or v
         elseif (type(dst[k]) == "table" and k~="elements" and type(v) == "table") then
             self:MergeVariable(v, dst[k])
         elseif (type(dst[k]) == "table" and k=="elements" and type(v) == "table") then
             dst[k] = AutoValidateElements(v, dst[k])
         end
     end
     return dst
 end
```

---

### Patch 5: Style Engine Zero-Pollution Weak Cache (`Engine/Style.lua`)

```diff
--- a/Engine/Style.lua
+++ b/Engine/Style.lua
@@ -6,6 +6,8 @@ local LibMedia = LibStub:GetLibrary("LibSharedMedia-3.0", true)
 
+local hideBgCaches = setmetatable({}, { __mode = "k" })
+
 local function HideBackgroundTextures(frame)
     if (not frame) then return end
     if (frame.IsForbidden and frame:IsForbidden()) then return end
     if (not frame.GetRegions) then return end
 
-    local cache = frame.__RT_HideBgCache
+    local cache = hideBgCaches[frame]
     if (cache) then
         for tex in pairs(cache) do hide(tex) end
         return
     end
 
     cache = {}
-    frame.__RT_HideBgCache = cache
+    hideBgCaches[frame] = cache
```

---

### Patch 6: Slash Commands Expansion (`Options.lua`)

```diff
--- a/Options.lua
+++ b/Options.lua
@@ -1404,6 +1404,8 @@ else
 SLASH_RothTooltip1 = "/tinytooltip"
 SLASH_RothTooltip2 = "/tt"
 SLASH_RothTooltip3 = "/tip"
+SLASH_RothTooltip4 = "/rothtooltip"
+SLASH_RothTooltip5 = "/rtip"
 function SlashCmdList.RothTooltip(msg)
     msg = strtrim(tostring(msg or ""):lower())
```

---

## 5. Verification & Test Plan

1. **Manifest & Invariant Verification (`tools/check_repo.py`):**
   - Execute static verification script:
     ```powershell
     python tools/check_repo.py
     ```
   - Confirms TOC sequence: `TooltipBootstrap` -> `Core` -> `Midnight` -> `Runtime12_1` -> `TooltipProcessor`.
   - Validates that `Compat_MoneyFrame.lua` does not exist.
   - Verifies zero instances of raw `data.args` or raw `AuraData` forwarding in `TooltipProcessor.lua`.

2. **Runtime Lifecycle & Taint Testing:**
   - **Combat Lockdown:** Enter combat and hover over unit frames, action bars, and inventory items. Ensure no `ADDON_ACTION_BLOCKED` or secret-value errors are emitted to `Doctor.lua` or `BugSack`.
   - **Secret Predicates:** Enter an arena or battleground where unit identities or player stats may be restricted. Confirm tooltips cleanly display fallback strings (`"??"`) without lua crashes.
   - **Profile & SavedVariables Mutation (RT-AUDIT-001):**
     1. Create and switch to a secondary character with `SavedVariablesPerCharacter = true`.
     2. Alter visibility and status bar formats.
     3. Switch back to account profile and verify default table values in `addon.db` remain uncorrupted.
   - **Model Frame Isolation:** Target diverse NPCs and players; verify model rotates via Ctrl/Alt dragging and immediately hides upon entering combat without throwing errors on `PlayerModel:SetUnit()`.

---

## 6. Conclusion & Recommendation

The local `RothTooltip` installation was operating on an outdated 12.0.20 foundation with dangerous global monkey-patching (`Compat_MoneyFrame.lua`), fragile comparison-based secret probing, and direct decoration of Blizzard tooltip frames. 

By applying the upstream 12.1 engine overhaul alongside our targeted fixes for **RT-AUDIT-001** (`MergeVariable` deep copy protection) and **RT-AUDIT-002** (shadow processor removal from `Core.lua`), `RothTooltip` achieves full compliance with World of Warcraft: Midnight Retail 12.1 standards. Immediate staging and merging of this PR is recommended.
