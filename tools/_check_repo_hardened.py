#!/usr/bin/env python3
"""Static repository checks that do not require a running WoW client."""

from __future__ import annotations

import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "RothTooltip.toc"

REQUIRED_LOAD_ORDER = [
    "Engine/Safe.lua",
    "Core.lua",
    "Engine/Midnight.lua",
    "Engine/Style.lua",
    "Engine/TooltipRegistry.lua",
    "Engine/TooltipProcessor.lua",
    "Config.lua",
    "General.lua",
]

OBSOLETE_PATHS = [
    "Compat_MoneyFrame.lua",
    "Engine/TooltipBootstrap.lua",
    "Engine/Runtime12_1.lua",
    "todo.md",
    ".refactor_payload",
    "tools/_post_final_hardening.py",
    "tools/_post_final_hardening_v2.py",
    "tools/_check_repo_hardened.py",
    ".github/workflows/normalize-runtime.yml",
    ".github/workflows/audit-source-export.yml",
    ".github/workflows/audit-donors-export.yml",
    ".github/workflows/apply-single-runtime.yml",
    ".github/workflows/finalize-main.yml",
    ".github/workflows/force-finalize-main.yml",
    ".github/workflows/finalize-retail-12-1-authoritative.yml",
    ".github/workflows/finalize-and-report-retail-12-1.yml",
    ".github/workflows/main-authoritative-finalizer.yml",
    ".github/workflows/post-final-runtime-hardening.yml",
    ".github/workflows/post-final-runtime-hardening-v2.yml",
]


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def normalize_repo_path(value: str) -> str:
    return value.strip().replace("\\", "/")


def strip_lua_comments(source: str) -> str:
    """Strip Lua comments while preserving quoted strings."""

    output: list[str] = []
    index = 0
    length = len(source)
    quote: str | None = None

    while index < length:
        char = source[index]
        next_char = source[index + 1] if index + 1 < length else ""

        if quote:
            output.append(char)
            if char == "\\":
                if index + 1 < length:
                    index += 1
                    output.append(source[index])
            elif char == quote:
                quote = None
            index += 1
            continue

        if char in {"'", '"'}:
            quote = char
            output.append(char)
            index += 1
            continue

        if char == "-" and next_char == "-":
            long_match = re.match(r"--\[(=*)\[", source[index:])
            if long_match:
                equals = long_match.group(1)
                closing = f"]{equals}]"
                end = source.find(closing, index + long_match.end())
                if end == -1:
                    return "".join(output)
                output.append("\n" * source[index : end + len(closing)].count("\n"))
                index = end + len(closing)
                continue

            end = source.find("\n", index)
            if end == -1:
                break
            output.append("\n")
            index = end + 1
            continue

        output.append(char)
        index += 1

    return "".join(output)


def read_toc() -> tuple[list[str], dict[str, str]]:
    if not TOC.is_file():
        fail("RothTooltip.toc is missing")

    files: list[str] = []
    metadata: dict[str, str] = {}
    for raw_line in TOC.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("##"):
            key, separator, value = line[2:].partition(":")
            if separator:
                metadata[key.strip()] = value.strip()
            continue
        if line.startswith("#"):
            continue
        files.append(normalize_repo_path(line))
    return files, metadata


def validate_toc() -> list[str]:
    files, metadata = read_toc()

    if metadata.get("Interface") != "120100":
        fail(f"expected Interface 120100, got {metadata.get('Interface')!r}")
    if metadata.get("Version") != "12.1.0":
        fail(f"expected Version 12.1.0, got {metadata.get('Version')!r}")

    for obsolete in OBSOLETE_PATHS:
        if obsolete in files:
            fail(f"obsolete file is still loaded: {obsolete}")
        if (ROOT / obsolete).exists():
            fail(f"obsolete or temporary path still exists: {obsolete}")

    if len(files) != len(set(files)):
        fail("TOC contains duplicate file entries")

    for relative in files:
        if not (ROOT / relative).is_file():
            fail(f"TOC references missing file: {relative}")

    positions: dict[str, int] = {}
    for required in REQUIRED_LOAD_ORDER:
        try:
            positions[required] = files.index(required)
        except ValueError:
            fail(f"TOC is missing required runtime layer: {required}")

    ordered_positions = [positions[path] for path in REQUIRED_LOAD_ORDER]
    if ordered_positions != sorted(ordered_positions):
        fail("Retail 12.1 runtime layers are in the wrong order")

    return files


def resolve_xml_reference(xml_path: Path, value: str) -> Path:
    value = normalize_repo_path(value)
    direct = xml_path.parent / value
    if direct.exists():
        return direct
    return ROOT / value


def validate_xml(xml_path: Path, visited: set[Path]) -> None:
    xml_path = xml_path.resolve()
    if xml_path in visited:
        return
    visited.add(xml_path)

    try:
        tree = ET.parse(xml_path)
    except ET.ParseError as error:
        fail(f"invalid XML in {xml_path.relative_to(ROOT)}: {error}")

    for element in tree.iter():
        tag = element.tag.rsplit("}", 1)[-1]
        if tag not in {"Script", "Include"}:
            continue
        reference = element.attrib.get("file")
        if not reference:
            continue
        target = resolve_xml_reference(xml_path, reference)
        if not target.is_file():
            fail(
                f"{xml_path.relative_to(ROOT)} references missing file "
                f"{normalize_repo_path(reference)}"
            )
        if target.suffix.lower() == ".xml":
            validate_xml(target, visited)


def validate_xml_graph(toc_files: list[str]) -> None:
    visited: set[Path] = set()
    for relative in toc_files:
        path = ROOT / relative
        if path.suffix.lower() == ".xml":
            validate_xml(path, visited)


def validate_markdown_links() -> None:
    link_pattern = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")

    for markdown in ROOT.rglob("*.md"):
        text = markdown.read_text(encoding="utf-8")
        for raw_target in link_pattern.findall(text):
            target = raw_target.strip()
            if not target or target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            target = target.split("#", 1)[0].strip()
            if not target:
                continue
            target = urllib.parse.unquote(target)
            resolved = (markdown.parent / target).resolve()
            if not resolved.exists():
                fail(
                    f"broken local Markdown link in {markdown.relative_to(ROOT)}: "
                    f"{raw_target}"
                )


def read_lua(path: str) -> tuple[str, str]:
    raw = (ROOT / path).read_text(encoding="utf-8")
    return raw, strip_lua_comments(raw)


def validate_runtime_invariants() -> None:
    safe_raw, _ = read_lua("Engine/Safe.lua")
    _, core = read_lua("Core.lua")
    midnight_raw, midnight = read_lua("Engine/Midnight.lua")
    style_raw, style = read_lua("Engine/Style.lua")
    processor_raw, processor = read_lua("Engine/TooltipProcessor.lua")
    registry_raw, registry = read_lua("Engine/TooltipRegistry.lua")
    unit_raw, unit = read_lua("Unit.lua")
    _, expansion = read_lua("ExpansionInfo.lua")

    if "canaccessvalue" not in safe_raw or "canaccessallvalues" not in safe_raw:
        fail("Safe.lua is missing Retail capability gates")
    if "C_Secrets" not in midnight_raw or "ShouldSpellAuraBeSecret" not in midnight_raw:
        fail("Midnight.lua is missing the Retail 12.1 restriction boundary")
    if "function addon:InitTooltipDataProcessor" not in processor_raw:
        fail("Retail TooltipDataProcessor entrypoint is missing")
    if "function addon:RegisterTooltipFrame" not in midnight_raw:
        fail("managed tooltip registry API is missing")
    if "ADDON_RESTRICTION_STATE_CHANGED" not in registry_raw:
        fail("addon restriction changes no longer invalidate tooltip context")
    if "SPELL_SECRECY_CHANGED" in registry_raw:
        fail("unknown SPELL_SECRECY_CHANGED event was restored")

    all_lua_code = "\n".join(
        strip_lua_comments(path.read_text(encoding="utf-8"))
        for path in ROOT.rglob("*.lua")
    )
    if all_lua_code.count("function addon:InitTooltipDataProcessor") != 1:
        fail("there must be exactly one tooltip processor implementation")

    forbidden_core_patterns = {
        "TooltipDataProcessor": "Core.lua contains a shadow tooltip processor",
        "RebuildFromTooltipInfo": "Core.lua contains raw tooltip rebuild logic",
        "UnitTokenFromGUID": "Core.lua contains unit identity reconstruction",
        '"mouseover"': "Core.lua contains mouseover identity recovery",
        "data.args": "Core.lua reads raw TooltipData arguments",
        "tooltipData.args": "Core.lua reads raw TooltipData arguments",
        "__RT_Last": "Core.lua stores legacy tooltip side-channel state",
    }
    for pattern, message in forbidden_core_patterns.items():
        if pattern in core:
            fail(message)

    forbidden_global_patterns = {
        "dataTypes.Action": "nonexistent TooltipDataType.Action was restored",
        "pcall(function() return v == v end)": "comparison-based secret probing was restored",
        "RebuildFromTooltipInfo(": "raw tooltip replay was restored",
        "data.args": "raw TooltipData argument vectors are inspected",
        "tooltipData.args": "raw TooltipData argument vectors are inspected",
    }
    for pattern, message in forbidden_global_patterns.items():
        if pattern in all_lua_code:
            fail(message)

    if re.search(
        r"LibEvent:trigger\(\s*[\"']tooltip:aura[\"']\s*,\s*tooltip\s*,\s*(?:data|tooltipData)",
        processor,
    ):
        fail("Retail processor forwards a raw aura payload")
    if re.search(r"\b(?:tip|tooltip)\.(?:GetBackdrop|GetBackdropColor|GetBackdropBorderColor)\s*=", style):
        fail("Style.lua replaces Blizzard tooltip methods")
    if ".__RT_HideBgCache" in style or ".__RTStyle" in style:
        fail("Style.lua stores visual bookkeeping on Blizzard tooltip fields")
    if "GetRegions" in style:
        fail("Style.lua enumerates potentially secret-returning frame regions")
    if re.search(r"\b(?:tip|tooltip|bar)\.(?:BigFactionIcon|TextString|forceHideText)\s*=", all_lua_code):
        fail("addon bookkeeping was restored on a Blizzard tooltip/status bar")
    if ".BigFactionIcon" in all_lua_code:
        fail("legacy frame-owned faction icon access was restored")

    refresh_markers = (
        "context.type == dataTypes.Unit",
        "context.type == dataTypes.Item",
        "context.type == dataTypes.Spell",
    )
    if not all(marker in midnight_raw for marker in refresh_markers):
        fail("tooltip refresh is no longer type preserving")
    if "ContextByTooltip[tooltip] = nil" not in midnight_raw:
        fail("inaccessible tooltip data no longer clears stale context")
    if "addon:SetPrimaryTooltipContext(tooltip, nil)" not in processor_raw:
        fail("processor no longer clears context for inaccessible raw payload")

    if "SanitizeMythicPlusSummary" not in unit_raw:
        fail("Mythic+ summaries are no longer sanitized before caching")
    if "single global request channel" not in unit:
        fail("NotifyInspect is no longer globally throttled")
    if "GET_ITEM_INFO_RECEIVED" not in registry:
        fail("managed item tooltips no longer refresh from the central item-cache event")
    if "GET_ITEM_INFO_RECEIVED" in expansion:
        fail("ExpansionInfo restored a duplicate item-cache refresh listener")
    if "if installed then HookedTooltips[tooltip] = true end" not in style_raw:
        fail("temporarily forbidden tooltip hooks are no longer retryable")

    if "setmetatable({}, { __mode = \"k\" })" not in style_raw:
        fail("Style.lua no longer owns tooltip state in weak-key tables")
    if "setmetatable({}, { __mode = \"k\" })" not in registry_raw:
        fail("TooltipRegistry.lua no longer uses a weak managed-tooltip set")


def main() -> int:
    toc_files = validate_toc()
    validate_xml_graph(toc_files)
    validate_markdown_links()
    validate_runtime_invariants()
    print(
        "Repository manifest, XML graph, Markdown links, and hardened Retail "
        "12.1 runtime invariants are valid."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
