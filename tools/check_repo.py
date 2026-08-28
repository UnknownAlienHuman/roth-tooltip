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
    "Engine/TooltipBootstrap.lua",
    "Core.lua",
    "Engine/Midnight.lua",
    "Engine/Runtime12_1.lua",
    "Engine/TooltipProcessor.lua",
]


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def normalize_repo_path(value: str) -> str:
    return value.strip().replace("\\", "/")


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
    if "Compat_MoneyFrame.lua" in files:
        fail("obsolete Compat_MoneyFrame.lua is still loaded")

    for relative in files:
        if not (ROOT / relative).is_file():
            fail(f"TOC references missing file: {relative}")

    positions = {}
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


def validate_runtime_markers() -> None:
    bootstrap = (ROOT / "Engine/TooltipBootstrap.lua").read_text(encoding="utf-8")
    processor = (ROOT / "Engine/TooltipProcessor.lua").read_text(encoding="utf-8")
    midnight = (ROOT / "Engine/Midnight.lua").read_text(encoding="utf-8")

    if "__RT_DeferTooltipProcessor = true" not in bootstrap:
        fail("Tooltip bootstrap no longer defers the legacy Core processor")
    if "function addon:InitTooltipDataProcessor" not in processor:
        fail("Retail TooltipDataProcessor entrypoint is missing")
    if "canaccessvalue" not in midnight or "C_Secrets" not in midnight:
        fail("Retail access/restriction boundary is incomplete")
    if "RebuildFromTooltipInfo(" in midnight:
        fail("Midnight runtime actively calls RebuildFromTooltipInfo")


def main() -> int:
    toc_files = validate_toc()
    validate_xml_graph(toc_files)
    validate_markdown_links()
    validate_runtime_markers()
    print("Repository manifest, XML graph, Markdown links, and runtime markers are valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
