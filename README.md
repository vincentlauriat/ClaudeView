# ClaudeView

A native macOS app to browse, search, and analyze your **Claude Code** sessions —
100% local, no account, no server. A macOS-only, customizable reinterpretation
of [agentsview](https://github.com/kenn-io/agentsview), focused on Claude Code.

## Features

| Feature | Status |
|---|---|
| Session browsing with rich transcripts (markdown, tool calls, thinking) | 🚧 |
| Full-text search (SQLite FTS5) with filters | 🚧 |
| Cost tracking (cache-aware, editable model prices, budgets) | 🚧 |
| Stats: activity heatmap, daily/monthly trends, model/project breakdowns | 🚧 |
| **Live view** — real-time "sniffer" stream of session events | 🚧 |
| **Customizable dashboard** — modular widgets, drag to reorder | 🚧 |
| Configurable columns, saved views, themes (accent, density, fonts) | 🚧 |

## How it works

ClaudeView incrementally indexes `~/.claude/projects/**/*.jsonl` into a local
SQLite database (FTS5), then watches the directory with FSEvents: every new
transcript line feeds both the index and the real-time Live view. Costs are
computed at query time from token counts × editable per-model prices.

Data stays on your Mac: `~/Library/Application Support/ClaudeView/`.

## Requirements

- macOS 15+
- Claude Code sessions in `~/.claude/projects/`

## Build

```bash
xcodegen generate
xcodebuild -scheme ClaudeView -configuration Debug build
```

## Project layout

```
ClaudeView/          App sources (SwiftUI + Core modules)
ClaudeViewTests/     Unit tests (parser, indexer, pricing)
docs/                Design specs and documentation
project.yml          xcodegen project definition
```

## Roadmap

- [ ] v1 — sessions, search, costs, stats, live view, customizable dashboard
- [ ] Saved views & named filters
- [ ] Signed & notarized DMG release
