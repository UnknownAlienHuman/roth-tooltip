#!/usr/bin/env python3
"""Normalize the inspect-cache block before the canonical finalizer."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "Unit.lua"
text = path.read_text(encoding="utf-8")
function_start = text.index("local function OnInspectReady")
function_end = text.index("local function RequestInspect", function_start)
segment = text[function_start:function_end]

new_block = '''        if itemLevel ~= nil or specID ~= nil then
            local now = GetTime and GetTime() or 0
            PruneInspectCache(now)
            local isNewEntry = inspectCache[guid] == nil
            inspectCache[guid] = {
                ilvl = itemLevel,
                specID = specID,
                time = now,
            }
            if isNewEntry then inspectCacheCount = inspectCacheCount + 1 end
        end
'''

if new_block not in segment:
    normalized_start = segment.find("        if itemLevel ~= nil or specID ~= nil then")
    if normalized_start < 0:
        normalized_start = segment.find("        local now = GetTime and GetTime() or 0")
    if normalized_start < 0:
        raise SystemExit("Unit.lua: inspect-cache start anchor missing")

    outer_end_marker = "\n    end\n\n    ClearPendingInspect()"
    normalized_end = segment.index(outer_end_marker, normalized_start)
    segment = segment[:normalized_start] + new_block.rstrip("\n") + segment[normalized_end:]
    text = text[:function_start] + segment + text[function_end:]
    path.write_text(text, encoding="utf-8")

print("Inspect cache block normalized.")
