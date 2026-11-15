"""Dependency-free package checks; does not replace native Godot integration tests."""

from __future__ import annotations

import ast
import configparser
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
IGNORED = {".git", ".godot", ".test_work", ".test_tools", "__pycache__"}
TEXT_SUFFIXES = {".md", ".gd", ".cs", ".txt", ".py", ".cfg", ".yml"}
BRANDING = re.compile("ta" + "nk|bang" + "bang", re.IGNORECASE)
LINK = re.compile(r"!?\[[^\]\n]*\]\(([^)\n]+)\)")


def local_link(document: Path, target: str) -> Path | None:
    """Resolve relative Markdown links, leaving web URLs and anchors alone."""
    target = target.strip().split(' "', 1)[0].strip("<>")
    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc or not parsed.path:
        return None
    return document.parent / unquote(parsed.path)


def self_check() -> None:
    """Check the parsing branches used by repository validation."""
    document = ROOT / "addons/addressables/docs/API.md"
    assert local_link(document, "https://example.com/page") is None
    assert local_link(document, "#section") is None
    assert local_link(document, "../README.md#install") == document.parent / "../README.md"
    assert local_link(document, "guide%20name.md") == document.parent / "guide name.md"
    assert BRANDING.search("TA" + "NK")
    assert BRANDING.search("Bang" + "Bang")
    assert not BRANDING.search("Addressables")


def main() -> None:
    self_check()
    addon = ROOT / "addons/addressables"
    metadata = configparser.ConfigParser()
    metadata.read(addon / "plugin.cfg", encoding="utf-8")
    assert metadata["plugin"]["version"].strip('"') == "0.1.0", "Plugin version mismatch"
    assert (addon / metadata["plugin"]["script"].strip('"')).is_file(), "Missing editor entry"
    license_text = (ROOT / "LICENSE").read_text(encoding="utf-8")
    assert license_text == (addon / "LICENSE").read_text(encoding="utf-8"), "License copies differ"
    assert "MIT License" in license_text and "Permission is hereby granted" in license_text
    for readme in (ROOT / "README.md", addon / "README.md"):
        text = readme.read_text(encoding="utf-8")
        assert "0.1.0" in text and "experimental" in text.lower(), readme
    for directory in ("runtime", "editor", "dotnet", "tests", "docs"):
        assert (addon / directory).is_dir(), directory

    checked = 0
    for path in ROOT.rglob("*"):
        if not path.is_file() or IGNORED.intersection(path.relative_to(ROOT).parts):
            continue
        if path.suffix not in TEXT_SUFFIXES and path.name != "LICENSE":
            continue
        text = path.read_text(encoding="utf-8")
        assert not BRANDING.search(text), f"Application branding: {path}"
        assert not any(c.isalpha() and not c.isascii() for c in text), f"Non-English text: {path}"
        assert not re.search(r"[A-Za-z]:[/\\](?:Users|Workspace|Tools)[/\\]", text), f"Developer path: {path}"
        if path.suffix == ".py":
            ast.parse(text, filename=str(path))
        if path.suffix == ".md":
            assert len(re.findall(r"^```", text, re.MULTILINE)) % 2 == 0, f"Unbalanced fences: {path}"
            for target in LINK.findall(text):
                destination = local_link(path, target)
                assert destination is None or destination.exists(), f"Broken link: {path}: {target}"
        checked += 1
    print(f"PASS repository checks: {checked} text files; licenses, layout, Python syntax and documentation")


if __name__ == "__main__":
    main()
