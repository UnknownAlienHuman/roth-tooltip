#!/usr/bin/env python3
"""Static repository and Retail 12.1 ownership checks."""

from __future__ import annotations

import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "RothTooltip.toc"
EXPECTED_INTERFACE = "120100"
EXPECTED_VERSION = "12.1.1"

REQUIRED_ORDER = [
    "Engine/Safe.lua",
    "Engine/Policy.lua",
    "Engine/ModuleManager.lua",
    "Engine/Doctor.lua",
    "Engine/Debug.lua",
    "Engine/Schema.lua",
    "Engine/Locale.lua",
    "Core.lua",
    "Engine/Midnight.lua",
    "Engine/TooltipLines.lua",
    "Engine/Style.lua",
    "Engine/StyleController.lua",
    "Engine/TooltipRegistry.lua",
    "Engine/TooltipProcessor.lua",
    "Config.lua",
    "General.lua",
]

OBSOLETE_PATHS = {
    "Compat_MoneyFrame.lua",
    "Engine/TooltipBootstrap.lua",
    "Engine/Runtime12_1.lua",
    "todo.md",
    ".refactor_payload",
    ".deep_audit",
}

TEMPORARY_WORKFLOW_PREFIXES = (
    "audit-",
    "deep-audit-",
    "modernize-",
    "finalize-",
    "post-final-",
    "force-finalize-",
    "main-authoritative-",
    "promote-",
)

FEATURE_MODULES = {
    "Anchor.lua": "Anchor",
    "Target.lua": "Target",
    "Unit.lua": "Unit",
    "Model.lua": "Model",
    "Item.lua": "Item",
    "Spell.lua": "Spell",
    "Quest.lua": "Quest",
    "LinkID.lua": "LinkID",
    "Mount.lua": "Mount",
    "ExpansionInfo.lua": "ExpansionInfo",
    "SkinFrames.lua": "SkinFrames",
    "General.lua": "General",
}

ENGINE_DIRECT_EVENT_OWNERS = {
    "Engine/Locale.lua",
    "Engine/ModuleManager.lua",
    "Engine/Style.lua",
    "Engine/StyleController.lua",
    "Engine/TooltipLines.lua",
    "Engine/TooltipRegistry.lua",
    "Core.lua",
}


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def norm(value: str) -> str:
    return value.strip().replace("\\", "/")


def strip_lua_comments(source: str) -> str:
    output: list[str] = []
    index = 0
    length = len(source)
    quote: str | None = None

    while index < length:
        char = source[index]
        next_char = source[index + 1] if index + 1 < length else ""

        if quote:
            output.append(char)
            if char == "\\" and index + 1 < length:
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
                if end < 0:
                    return "".join(output)
                output.append("\n" * source[index : end + len(closing)].count("\n"))
                index = end + len(closing)
                continue

            end = source.find("\n", index)
            if end < 0:
                break
            output.append("\n")
            index = end + 1
            continue

        output.append(char)
        index += 1

    return "".join(output)


def lua(path: str) -> tuple[str, str]:
    raw = (ROOT / path).read_text(encoding="utf-8")
    return raw, strip_lua_comments(raw)


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
        files.append(norm(line))
    return files, metadata


def validate_toc() -> list[str]:
    files, metadata = read_toc()
    if metadata.get("Interface") != EXPECTED_INTERFACE:
        fail(f"expected Interface {EXPECTED_INTERFACE}, got {metadata.get('Interface')!r}")
    if metadata.get("Version") != EXPECTED_VERSION:
        fail(f"expected Version {EXPECTED_VERSION}, got {metadata.get('Version')!r}")
    if len(files) != len(set(files)):
        fail("TOC contains duplicate entries")

    for relative in files:
        if not (ROOT / relative).is_file():
            fail(f"TOC references missing file: {relative}")

    for obsolete in OBSOLETE_PATHS:
        if (ROOT / obsolete).exists() or obsolete in files:
            fail(f"obsolete path remains: {obsolete}")

    positions: list[int] = []
    for required in REQUIRED_ORDER:
        try:
            positions.append(files.index(required))
        except ValueError:
            fail(f"TOC is missing required owner: {required}")
    if positions != sorted(positions):
        fail("runtime owners are loaded in the wrong order")

    workflow_dir = ROOT / ".github/workflows"
    for workflow in workflow_dir.glob("*.yml"):
        if workflow.name != "static-checks.yml" and workflow.name.startswith(TEMPORARY_WORKFLOW_PREFIXES):
            fail(f"temporary workflow remains: {workflow.relative_to(ROOT)}")
    return files


def resolve_xml_reference(xml_path: Path, value: str) -> Path:
    value = norm(value)
    direct = xml_path.parent / value
    return direct if direct.exists() else ROOT / value


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
            fail(f"{xml_path.relative_to(ROOT)} references missing file {norm(reference)}")
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
            target = urllib.parse.unquote(target.split("#", 1)[0].strip())
            if target and not (markdown.parent / target).resolve().exists():
                fail(f"broken local Markdown link in {markdown.relative_to(ROOT)}: {raw_target}")


def validate_single_owners() -> None:
    lua_files = sorted(ROOT.rglob("*.lua"))
    code_by_path = {
        path.relative_to(ROOT).as_posix(): strip_lua_comments(path.read_text(encoding="utf-8"))
        for path in lua_files
    }
    all_code = "\n".join(code_by_path.values())

    if all_code.count("function addon:InitTooltipDataProcessor") != 1:
        fail("there must be exactly one TooltipDataProcessor implementation")
    if all_code.count("AddTooltipPostCall") != 1:
        fail("there must be exactly one AddTooltipPostCall owner")
    if all_code.count("AddLinePostCall") != 1:
        fail("there must be exactly one AddLinePostCall owner")
    if "AddTooltipPostCall" not in code_by_path.get("Engine/TooltipProcessor.lua", ""):
        fail("TooltipProcessor.lua must own AddTooltipPostCall")
    if "AddLinePostCall" not in code_by_path.get("Engine/TooltipLines.lua", ""):
        fail("TooltipLines.lua must own AddLinePostCall")

    core = code_by_path.get("Core.lua", "")
    forbidden_core = {
        "LibEvent:attach": "Core.lua still subscribes to presentation events",
        "GameTooltip_SetDefaultAnchor": "Core.lua still owns anchoring",
        "SharedTooltip_SetBackdropStyle": "Core.lua still owns backdrop hooks",
        "GameTooltip_SetBackdropStyle": "Core.lua still owns backdrop hooks",
        "tooltip.statusbar": "Core.lua still owns status-bar runtime",
        "function addon:GetNpcTitle": "Core.lua still owns semantic native lines",
        "RegisterTooltipFrame": "Core.lua still owns the registry",
        "TooltipDataProcessor": "Core.lua still contains tooltip integration",
    }
    for pattern, message in forbidden_core.items():
        if pattern in core:
            fail(message)

    owners = {
        "GameTooltip_SetDefaultAnchor": "Anchor.lua",
        "SharedTooltip_SetBackdropStyle": "Engine/Style.lua",
        "GameTooltip_SetBackdropStyle": "Engine/Style.lua",
        "function addon:RegisterTooltipFrame": "Engine/TooltipRegistry.lua",
        "function addon:GetNpcTitle": "Engine/TooltipLines.lua",
        "function addon:RefreshStatusBar": "General.lua",
        "function addon:BuildProfile": "Engine/Schema.lua",
        "function addon:RegisterLocaleOverlay": "Engine/Locale.lua",
    }
    for symbol, expected_path in owners.items():
        found = [path for path, code in code_by_path.items() if symbol in code]
        if found != [expected_path]:
            fail(f"{symbol} owner mismatch: expected {expected_path}, found {found}")

    forbidden_global = {
        "TooltipDataType.Action": "nonexistent TooltipDataType.Action was restored",
        "dataTypes.Action": "nonexistent TooltipDataType.Action was restored",
        "RebuildFromTooltipInfo(": "raw tooltip replay was restored",
        "tooltipData.args": "raw TooltipData args are inspected",
        "data.args": "raw TooltipData args are inspected",
        "pcall(function() return v == v end)": "comparison-based secret probe was restored",
        '"mouseover"': "mouseover identity reconstruction was restored",
        "DisableDrawLayer": "whole Blizzard draw-layer suppression was restored",
        "C_PvP.IsArena": "obsolete arena predicate was restored",
    }
    for pattern, message in forbidden_global.items():
        if pattern in all_code:
            fail(message)

    for relative, module_name in FEATURE_MODULES.items():
        code = code_by_path.get(relative)
        if code is None:
            fail(f"feature module is missing: {relative}")
        registrations = re.findall(r'addon\.MM:RegisterModule\("([^"]+)"', code)
        if registrations != [module_name]:
            fail(f"{relative} must register exactly {module_name}, got {registrations}")
        if "LibEvent:attachEvent" in code or "LibEvent:attachTrigger" in code:
            fail(f"{relative} bypasses ModuleManager")

    for path, code in code_by_path.items():
        if path in ENGINE_DIRECT_EVENT_OWNERS or path.startswith("tests/"):
            continue
        if "LibEvent:attachEvent" in code or "LibEvent:attachTrigger" in code:
            fail(f"unexpected direct LibEvent owner: {path}")

    default_anchor_files = [path for path, code in code_by_path.items() if "GameTooltip_SetDefaultAnchor" in code]
    if default_anchor_files != ["Anchor.lua"]:
        fail(f"default anchor hook ownership mismatch: {default_anchor_files}")

    modifier_event_files = [
        path for path, code in code_by_path.items()
        if "MODIFIER_STATE_CHANGED" in code and not path.startswith("tests/")
    ]
    allowed_modifier = {"Engine/TooltipRegistry.lua", "Model.lua"}
    unexpected_modifier = sorted(set(modifier_event_files) - allowed_modifier)
    if unexpected_modifier:
        fail(f"duplicate modifier refresh owners: {unexpected_modifier}")


def validate_module_manager_contract() -> None:
    _, manager = lua("Engine/ModuleManager.lua")
    used: set[str] = set()
    defined: set[str] = set(re.findall(r"function\s+MM:([A-Za-z_][A-Za-z0-9_]*)", manager))
    for path in ROOT.rglob("*.lua"):
        if path.name == "ModuleManager.lua" or "tests" in path.parts:
            continue
        code = strip_lua_comments(path.read_text(encoding="utf-8"))
        used.update(re.findall(r"addon\.MM:([A-Za-z_][A-Za-z0-9_]*)", code))
    missing = sorted(used - defined)
    if missing:
        fail(f"undefined ModuleManager API methods are used: {missing}")

    required_markers = (
        "CallLifecycle",
        "RollbackLinks",
        "SnapshotLinks",
        "state.attached = false",
        "state.enabled = false",
    )
    for marker in required_markers:
        if marker not in manager:
            fail(f"transactional module lifecycle marker missing: {marker}")
    if re.search(r"SafeCall\([^\n]*:Enable", manager):
        fail("module Enable still uses ambiguous SafeCall lifecycle handling")


def validate_locale_contract() -> None:
    locale_raw, locale_code = lua("Engine/Locale.lua")
    if "function addon:RegisterLocaleOverlay" not in locale_code:
        fail("Locale.lua does not own overlay registration")
    if "FormatSignature" not in locale_code:
        fail("locale format signatures are not validated")

    overlays = sorted((ROOT / "locales").glob("*.lua"))
    if not overlays:
        fail("no locale overlays found")
    for overlay in overlays:
        code = strip_lua_comments(overlay.read_text(encoding="utf-8"))
        if re.search(r"addon\.L\s*=", code):
            fail(f"locale replaces addon.L: {overlay.relative_to(ROOT)}")
        if "RegisterLocaleOverlay" not in code:
            fail(f"locale does not register an overlay: {overlay.relative_to(ROOT)}")

    # Every literal non-config localization lookup must have a base entry.
    base_match = re.search(r"local\s+BASE\s*=\s*\{(.*?)\n\}", locale_raw, re.S)
    if not base_match:
        fail("unable to parse Locale.lua BASE table")
    base_keys = set(re.findall(r'\["([^"]+)"\]\s*=', base_match.group(1)))
    lookups: set[str] = set()
    for path in ROOT.rglob("*.lua"):
        if path.name == "Locale.lua" or path.parent.name == "locales" or "tests" in path.parts:
            continue
        code = strip_lua_comments(path.read_text(encoding="utf-8"))
        lookups.update(re.findall(r'(?:addon\.L|\bL)\["([^"]+)"\]', code))
    missing = sorted(key for key in lookups if "." not in key and key not in base_keys)
    if missing:
        fail(f"base locale is missing literal keys: {missing}")


def validate_runtime_contract() -> None:
    _, registry = lua("Engine/TooltipRegistry.lua")
    _, processor = lua("Engine/TooltipProcessor.lua")
    _, lines = lua("Engine/TooltipLines.lua")
    _, model = lua("Model.lua")
    _, mount = lua("Mount.lua")
    _, schema = lua("Engine/Schema.lua")

    required_registry = (
        "RequestManagedTooltipRefresh",
        "refreshQueue",
        "REFRESHABLE_TYPES",
        "RedispatchTooltipContext",
        "RestrictionsActive",
    )
    for marker in required_registry:
        if marker not in registry:
            fail(f"registry contract missing: {marker}")
    if "function addon:RedispatchTooltipContext" not in processor:
        fail("processor cannot redispatch action-like item enrichment")
    if "registered[lineType]" not in lines:
        fail("semantic line post-calls are not deduplicated")
    if "if not rotationActive" not in model:
        fail("residual model OnUpdate is not inert")
    if "lastMountByTooltip" in mount:
        fail("mount correctness still depends on tooltip clear state")
    if "SanitizeScalar" not in schema or "RANGES" not in schema or "ENUMS" not in schema:
        fail("SavedVariables values are not schema/range validated")


def main() -> int:
    toc_files = validate_toc()
    validate_xml_graph(toc_files)
    validate_markdown_links()
    validate_single_owners()
    validate_module_manager_contract()
    validate_locale_contract()
    validate_runtime_contract()
    print("RothTooltip 12.1.1 repository, ownership, locale, and runtime invariants are valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
