# ClaudeView

![Release](https://img.shields.io/github/v/release/vincentlauriat/ClaudeView)

A native macOS app to browse, search, and analyze your **Claude Code** sessions —
100% local, no account, no server. A macOS-only, customizable reinterpretation
of [agentsview](https://github.com/kenn-io/agentsview), focused on Claude Code.

## Features

| Feature | Status |
|---|---|
| Session browsing with rich transcripts (markdown, tool calls, thinking) | ✅ |
| Full-text search (SQLite FTS5) with filters | ✅ |
| Cost tracking (cache-aware, editable model prices, budgets) | ✅ |
| Stats: activity heatmap, daily/monthly trends, model/project breakdowns | ✅ |
| **Live view** — real-time "sniffer" stream of session events | ✅ |
| **Customizable dashboard** — modular widgets, drag to reorder | ✅ |
| Configurable columns, saved views, themes (accent, density, fonts) | ✅ |

## How it works

ClaudeView incrementally indexes `~/.claude/projects/**/*.jsonl` into a local
SQLite database (FTS5), then watches the directory with FSEvents: every new
transcript line feeds both the index and the real-time Live view. Costs are
computed at query time from token counts × editable per-model prices.

Data stays on your Mac: `~/Library/Application Support/ClaudeView/`.

## Requirements

- macOS 15+
- Claude Code sessions in `~/.claude/projects/`

## Install

Download the latest DMG from the
[Releases page](https://github.com/vincentlauriat/ClaudeView/releases/latest),
open it and drag **ClaudeView** to Applications. The app is signed, notarized,
and updates itself via Sparkle (ClaudeView → Rechercher les mises à jour…).

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

- [x] v1 — sessions, search, costs, stats, live view, customizable dashboard
- [x] Saved views & named filters
- [x] Signed & notarized DMG release with Sparkle auto-update
- [ ] Export (CSV/JSON) of sessions and costs
- [ ] Menu bar companion
