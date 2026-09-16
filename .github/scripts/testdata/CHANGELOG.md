# Changelog

Fixture for changelog_to_html.py. Covers every construct the HTML path handles.

## [Unreleased]

### Added
- Something not yet released, to prove the section boundary holds.

## [9.9.9] - 2026-09-16

An intro paragraph with *italics*, **bold**, `inline code`, a bare URL
https://github.com/andrew-waters/orchard and a [labelled link](https://example.com/docs).

### Added
- A top-level bullet with a bare URL https://example.com/a, a [link](https://example.com/b)
  and some *emphasis*.
  - A nested bullet, one level down.
    - And one deeper still, with `code` in it.
  - Back to the first nesting level.
- A second top-level bullet.

  A continuation paragraph belonging to that bullet, with **bold** in it.

- A third top-level bullet, after a blank line.

### Changed
Run it like this:

```bash
# comment with *asterisks*, **bold**, `backticks` and a [link](https://example.com)
if [[ -n "$VERSION" ]]; then
    python3 .github/scripts/changelog_to_html.py "$VERSION" CHANGELOG.md > notes.html
fi
```

---

A paragraph after a horizontal rule, ending with a URL in brackets
(https://example.com/trailing) and one ending a sentence: https://example.com/end.

### Fixed
- Escaping: 5 < 6 & "quoted" text, <not-a-tag>, and an AT&T-style ampersand.

## [9.9.8] - 2026-09-15

### Fixed
- The previous section, which must not leak into the one above.
