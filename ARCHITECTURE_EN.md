# ClaudeView — Architecture (source of truth)

> French mirror: `ARCHITECTURE.md`. Keep both in sync.

## Overview

Native macOS app (SwiftUI, macOS 15+). No server, no daemon. One process:
the app hosts the indexer, the file watcher, and the UI.

```
~/.claude/projects/**/*.jsonl
        │
   [LiveWatcher — FSEvents]
        │  changed files
        ▼
  [Indexer — incremental, byte-offset per file]
        │
   ┌────┴─────┐
   ▼          ▼
[SQLite     [LiveEvent
 GRDB+FTS5]  AsyncStream]
   │          │
   ▼          ▼
Sessions/Search/  Live "sniffer"
Stats/Costs       view
```

## Core modules (UI-independent)

| Module | Responsibility |
|---|---|
| `JSONLParser` | Tolerant decoding of Claude Code transcript lines (`user`, `assistant`, `system`, `ai-title`; content blocks `text`/`thinking`/`tool_use`/`tool_result`; usage tokens incl. cache). Malformed lines counted, never fatal. |
| `Store` (GRDB) | SQLite schema + migrations: `project`, `session`, `message`, `message_fts` (FTS5), `file_state`, `model_price`, `app_setting`. |
| `Indexer` | Startup scan + per-file incremental ingestion (byte offset cursor; truncation ⇒ per-file reindex). Full resync from Settings. |
| `LiveWatcher` | FSEvents stream on the projects dir, debounced; feeds the Indexer; ingested messages re-emitted as `LiveEvent`s (AsyncStream). |
| `PricingEngine` | Embedded default per-MTok prices + user overrides; costs computed at query time (tokens × price), never stored. |

## Key decisions

- **Payloads are not duplicated in SQLite.** `message` rows keep extracted text
  and `byteOffset/byteLength`; the transcript detail re-reads the JSONL line
  lazily. Keeps the DB small (source data ≈ 835 MB).
- **Costs at query time.** Editing a model price never requires reindexing.
- **Single ingestion path.** Startup scan and live tailing share the same
  Indexer code; the Live view is just a subscriber of ingestion output.

## UI (SwiftUI)

`NavigationSplitView` with sections: Dashboard (modular widget grid, layout
persisted in `app_setting`), Sessions (project tree → customizable `Table` →
transcript), Search (FTS5 + filters), Live (real-time table + payload
inspector, follow/pause), Stats (Swift Charts + heatmap), Settings (appearance,
pricing, budgets, data/resync).

## Storage

`~/Library/Application Support/ClaudeView/claudeview.sqlite` — disposable,
rebuilt from JSONL files (source of truth).

## Build & tooling

xcodegen (`project.yml`), GRDB via SPM, unit tests on real anonymized JSONL
fixtures. Release: standard DevApps DMG sign/notarize pipeline.
