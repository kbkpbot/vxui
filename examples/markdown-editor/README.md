# Markdown Editor — local files with live preview on vxui

A two-pane markdown editor that **reads and writes real files on this
machine** — the capability that separates a desktop framework from a web
one. Left pane edits, right pane renders, every keystroke batch is one
~0.6ms WebSocket round-trip.

## What it demonstrates

| vxui capability | How |
|---|---|
| **Local file open/save** | `/open` and `/save` do real disk IO through `check_editable_path` (desktop path semantics: absolute paths, `..` and `~` are legitimate — deliberately NOT the web-style `sanitize_path` traversal rules) |
| **Structured JSON responses** | `/open` `/save` `/new` `/stats` return JSON the page parses; `/preview` returns an HTML fragment the page injects — both response styles side by side |
| **Debounced input stream** | typing fires a `/preview` rpc 300ms after the last keystroke — continuous input over the ~0.6ms round-trip |
| **Backend markdown rendering** | dependency-free renderer in V (headings, lists, fenced code, quotes, inline styles, HTML escaping) — fully unit-tested, including XSS escaping |

## Run

```bash
v run examples/markdown-editor/main.v
```

Type a path (e.g. `/tmp/notes.md`), click Open, edit, watch the preview,
Save — then check the file on disk.

## Implementation notes

- The renderer is intentionally a practical subset of markdown, not
  CommonMark: enough for notes and READMEs, small enough to unit-test
  exhaustively (12 tests, including HTML-escaping of raw markup).
- `~/.vmodules/markdown` (a broken third-party package) shadows any vlib
  markdown module on this machine — hence the self-contained renderer.
