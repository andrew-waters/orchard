#!/usr/bin/env python3
"""Emit the CHANGELOG section for a version for release notes.

Usage: changelog_to_html.py [--markdown] <version> [changelog_path]

Default: prints the HTML for the `## [<version>]` section (headings, nested bullet
lists, fenced code blocks, horizontal rules, links, bold, italics, inline code), for
inline use in the Sparkle appcast.
With --markdown: prints the section body verbatim as markdown (heading line excluded),
used as the GitHub release body. Either way, prints nothing and exits 0 if the
section is absent, so callers can fall back to a plain link.

This is deliberately a small subset of markdown, matching what the changelog
actually uses, not a CommonMark implementation.
"""
from __future__ import annotations

import sys
import re
import html

# Sparkle renders the notes in a WKWebView with no stylesheet of its own, so a <pre>
# would otherwise be unpadded and would force the panel wide. A translucent grey reads
# as a panel against both the light and the dark background: the same HTML ships to
# every user, so it cannot depend on the reader's appearance.
CODE_STYLE = """<style>
pre {
  background: rgba(127, 127, 127, 0.18);
  padding: 10px 12px;
  border-radius: 6px;
  overflow-x: auto;
}
</style>"""

URL = re.compile(r"(?<!\]\()\bhttps?://[^\s<>\"']+")
MD_LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")
BOLD = re.compile(r"\*\*([^*]+)\*\*")
ITALIC = re.compile(r"(?<!\*)\*([^*\s][^*]*)\*(?!\*)")
CODE_SPAN = re.compile(r"(`[^`]+`)")
RULE = re.compile(r"(-{3,}|\*{3,}|_{3,})$")  # thematic break, e.g. a --- separator


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


def autolink(m: re.Match[str]) -> str:
    """Link a bare URL, leaving trailing sentence punctuation outside the anchor."""
    url = m.group(0)
    trailing = ""
    while url and url[-1] in ".,;:!?)":
        url, trailing = url[:-1], url[-1] + trailing
    return f'<a href="{url}">{url}</a>{trailing}'


def inline(text: str) -> str:
    """Escape HTML, then re-introduce links / bold / italics from markdown.

    Code spans are split out first so that markdown inside them is left alone.
    """
    out = []
    for part in CODE_SPAN.split(text):
        if part.startswith("`") and part.endswith("`") and len(part) > 1:
            out.append(f"<code>{html.escape(part[1:-1])}</code>")
            continue
        part = html.escape(part)
        part = URL.sub(autolink, part)  # before MD_LINK: the lookbehind spares [](url)
        part = MD_LINK.sub(r'<a href="\2">\1</a>', part)
        part = BOLD.sub(r"<strong>\1</strong>", part)
        part = ITALIC.sub(r"<em>\1</em>", part)
        out.append(part)
    return "".join(out)


def to_html(section: list[str]) -> str:
    """Render the section body as HTML."""
    out: list[str] = []
    stack: list[int] = []  # indent width of each open <ul>; its last <li> is still open
    fence: list[str] | None = None  # collected lines while inside ``` ... ```
    buf: list[str] = []  # text lines of the block being read, joined on flush
    buf_tag = "p"  # what that block becomes: a paragraph or a list item

    def flush_text() -> None:
        """Emit the block we have been reading, if any. Soft-wrapped lines join up."""
        nonlocal buf
        if not buf:
            return
        text = inline(" ".join(buf))
        out.append(f"<li>{text}" if buf_tag == "li" else f"<p>{text}</p>")
        buf = []

    def close_lists(indent: int) -> None:
        """Close every list nested deeper than `indent`."""
        while stack and stack[-1] > indent:
            out.extend(("</li>", "</ul>"))
            stack.pop()

    def close_all() -> None:
        flush_text()
        close_lists(-1)

    def flush_fence() -> None:
        nonlocal fence
        out.append(f"<pre><code>{html.escape(chr(10).join(fence or []))}</code></pre>")
        fence = None

    for ln in section:
        if ln.lstrip().startswith("```"):
            if fence is None:
                close_all()
                fence = []
            else:
                flush_fence()
            continue
        if fence is not None:
            fence.append(ln)  # verbatim: leading whitespace is part of the code
            continue

        s = ln.rstrip()
        stripped = s.lstrip()
        indent = len(s) - len(stripped)

        if RULE.match(stripped):
            close_all()
            out.append("<hr>")
        elif stripped.startswith("### "):
            close_all()
            out.append(f"<h3>{inline(stripped[4:])}</h3>")
        elif stripped.startswith("- "):
            flush_text()
            close_lists(indent)
            if stack and stack[-1] == indent:
                out.append("</li>")  # sibling of the bullet we are already in
            else:
                out.append("<ul>")
                stack.append(indent)
            buf, buf_tag = [stripped[2:]], "li"
        elif not stripped:
            flush_text()  # a blank line ends a block but does not end a list
        elif buf:
            buf.append(stripped)  # soft wrap of the bullet or paragraph above
        elif stack and indent:
            buf, buf_tag = [stripped], "p"  # further paragraph inside the open bullet
        else:
            close_all()
            buf, buf_tag = [stripped], "p"

    if fence is not None:
        flush_fence()  # unterminated fence at the end of the section
    close_all()

    body = "\n".join(out).strip()
    return f"{CODE_STYLE}\n{body}" if "<pre>" in body else body


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

    print(to_html(section))


if __name__ == "__main__":
    main()
