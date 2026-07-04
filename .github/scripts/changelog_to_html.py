#!/usr/bin/env python3
"""Emit the CHANGELOG section for a version as minimal HTML for Sparkle release notes.

Usage: changelog_to_html.py <version> [changelog_path]

Prints the HTML for the `## [<version>]` section (headings, bullet lists, links,
bold, inline code) to stdout. Prints nothing and exits 0 if the section is absent,
so the release workflow can fall back to a plain link.
"""
import sys
import re
import html


def inline(text: str) -> str:
    """Escape HTML, then re-introduce links / bold / inline code from markdown."""
    text = html.escape(text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return text


def main() -> None:
    if len(sys.argv) < 2:
        return
    version = sys.argv[1]
    path = sys.argv[2] if len(sys.argv) > 2 else "CHANGELOG.md"

    lines = open(path, encoding="utf-8").read().splitlines()
    target = re.compile(r"^## \[" + re.escape(version) + r"\]")
    start = next((i + 1 for i, ln in enumerate(lines) if target.match(ln)), None)
    if start is None:
        return  # no section → caller falls back

    section = []
    for ln in lines[start:]:
        if ln.startswith("## "):  # next version header
            break
        section.append(ln)

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
