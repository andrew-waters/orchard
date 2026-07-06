#!/usr/bin/env python3
"""Emit the CHANGELOG section for a version for release notes.

Usage: changelog_to_html.py [--markdown] <version> [changelog_path]

Default: prints the HTML for the `## [<version>]` section (headings, bullet lists,
links, bold, inline code) — used inline in the Sparkle appcast.
With --markdown: prints the section body verbatim as markdown (heading line excluded)
— used as the GitHub release body. Either way, prints nothing and exits 0 if the
section is absent, so callers can fall back to a plain link.
"""
from __future__ import annotations

import sys
import re
import html


def extract_section(version: str, path: str) -> list[str] | None:
    """Return the lines of the `## [<version>]` section body, or None if absent.

    Excludes the version heading itself and stops at the next `## ` header.
    """
    lines = open(path, encoding="utf-8").read().splitlines()
    target = re.compile(r"^## \[" + re.escape(version) + r"\]")
    start = next((i + 1 for i, ln in enumerate(lines) if target.match(ln)), None)
    if start is None:
        return None

    section = []
    for ln in lines[start:]:
        if ln.startswith("## "):  # next version header
            break
        section.append(ln)
    return section


def inline(text: str) -> str:
    """Escape HTML, then re-introduce links / bold / inline code from markdown."""
    text = html.escape(text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return text


def main() -> None:
    args = sys.argv[1:]
    markdown = False
    if args and args[0] == "--markdown":
        markdown = True
        args = args[1:]
    if not args:
        return
    version = args[0]
    path = args[1] if len(args) > 1 else "CHANGELOG.md"

    section = extract_section(version, path)
    if section is None:
        return  # no section → caller falls back

    if markdown:
        # Emit the section body verbatim, trimmed of leading/trailing blank lines.
        print("\n".join(section).strip())
        return

    out: list[str] = []
    in_list = False

    def close_list() -> None:
        nonlocal in_list
        if in_list:
            out.append("</ul>")
            in_list = False

    for ln in section:
        s = ln.rstrip()
        if s.startswith("### "):
            close_list()
            out.append(f"<h3>{inline(s[4:])}</h3>")
        elif s.lstrip().startswith("- "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(s.lstrip()[2:])}</li>")
        elif s.strip() == "":
            close_list()
        else:
            close_list()
            out.append(f"<p>{inline(s.strip())}</p>")
    close_list()

    print("\n".join(out).strip())


if __name__ == "__main__":
    main()
