# ClaudeView — Design Spec

Date: 2026-08-28
Status: Approved by Vincent (chat, 2026-08-28)

## Purpose

A native macOS app that browses, searches, and analyzes Claude Code sessions —
a macOS-only, more customizable reinterpretation of
[agentsview](https://github.com/kenn-io/agentsview), scoped to Claude Code only.
100% local, no account, no server.

## Scope

- **Data source**: `~/.claude/projects/**/*.jsonl` (Claude Code transcripts only).
- **Platform**: macOS 15+, SwiftUI native app. No web UI, no daemon.
- **v1 features**: session browsing + rich transcripts, full-text search (FTS5),
  cost tracking with editable prices, stats & heatmaps, and a real-time
  "sniffer" view streaming live session events (Wireshark-style).
- **Customization** (the differentiator vs. the original):
  - Modular dashboard: add/remove/reorder/configure widgets.
  - Configurable table columns, saved filters, named views.
  - Editable model prices, budgets/thresholds, reference periods.
  - Themes: accent color, light/dark/auto, display density, transcript font.

## Architecture

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
[SQLite    [LiveEvent stream
 GRDB+FTS5] (AsyncStream)]
   │          │
   ▼          ▼
Search/Stats  Live "sniffer" view
Costs/Sessions
```

### Core modules (no UI dependency)

- **JSONLParser** — tolerant line-by-line decoder (JSONSerialization-based) of
  Claude Code transcript lines. Relevant line types: `user`, `assistant`,
  `system`, `ai-title`. Others (`attachment`, `file-history-*`, `mode`, …) are
  skipped. Content blocks: `text`, `thinking`, `tool_use`, `tool_result`.
  Usage: `input_tokens`, `output_tokens`, `cache_read_input_tokens`,
  `cache_creation_input_tokens`. Malformed lines are counted, never fatal.
- **Store (GRDB)** — schema:
  - `project(id, dirName, path, name)`
  - `session(id, projectId, title, filePath, firstTs, lastTs, messageCount,
    inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens, model,
    gitBranch, cwd)`
  - `message(uuid, sessionId, projectId, ts, kind, role, model, text,
    toolNames, inputTokens, outputTokens, cacheReadTokens,
    cacheCreationTokens, isSidechain, byteOffset, byteLength)` — full payload
    is **not** duplicated in SQLite; the detail view lazily re-reads the JSONL
    line via `filePath + byteOffset/byteLength`.
  - `message_fts` — FTS5 over message text.
  - `file_state(path, byteOffset, mtime, size)` — incremental ingestion cursor.
  - `model_price(model, inputPerMTok, outputPerMTok, cacheReadPerMTok,
    cacheWritePerMTok, isCustom)` — costs are computed **at query time** from
    tokens × prices, so editing prices never requires reindexing.
  - `app_setting(key, valueJSON)` — dashboard layout, theme, saved views,
    column configs, budgets.
- **Indexer** — startup scan + on-demand per-file ingestion. Reads only bytes
  past the stored offset; truncated/rewritten files (size < offset) trigger a
  per-file reindex. Full resync available in Settings.
- **LiveWatcher** — FSEvents stream on `~/.claude/projects`, debounced;
  routes changed `.jsonl` files to the Indexer; newly ingested messages are
  published as `LiveEvent`s on an AsyncStream consumed by the Live view.
- **PricingEngine** — embedded default per-MTok prices for Claude models +
  user overrides from `model_price`.

### UI (SwiftUI, NavigationSplitView)

Sidebar sections: **Dashboard, Sessions, Recherche, Live, Stats** + Settings scene.

- **Dashboard** — customizable widget grid (`LazyVGrid`). Widget kinds v1:
  today/month cost, activity heatmap, top models, top projects, recent
  sessions, token totals, budget gauge. Layout (ordered list of widget configs)
  persisted in `app_setting`. Edit mode: add/remove/reorder/resize.
- **Sessions** — project tree → session `Table` with `TableColumnCustomization`
  (persisted), sortable, filterable; saved named views. Detail: transcript with
  Markdown rendering, collapsible tool calls (input+output), thinking blocks,
  per-message tokens/cost.
- **Recherche** — FTS5 query + filters (project, role, date range), highlighted
  snippets, jump to message in transcript.
- **Live** — real-time event table (time, project, session, role, kind, model,
  tokens, preview), follow/pause toggle, live filters, inspector pane with the
  full decoded payload of the selected event.
- **Stats** — Swift Charts: daily/monthly cost trends, GitHub-style activity
  heatmap, per-model and per-project breakdowns, session durations.
- **Settings** — General (data path, resync), Appearance (accent, scheme,
  density, transcript font), Pricing (editable table), Budgets.

## Error handling

- Malformed JSONL line → skipped + counted (surfaced as a discreet badge).
- Missing/removed files → sessions purged on resync.
- DB lives in `~/Library/Application Support/ClaudeView/claudeview.sqlite`;
  deletable at any time (rebuilt from JSONL source of truth).

## Testing

- Unit tests: JSONLParser (real anonymized fixtures), PricingEngine,
  Indexer incremental logic (offsets, truncation, malformed lines).
- `xcodebuild build` + `xcodebuild test` after changes.

## Project conventions

- xcodegen (`project.yml`), GRDB via SPM, standard DevApps layout.
- Auto-maintained docs: README, ARCHITECTURE_EN/FR, PLAN, TODOS, MEMORY,
  CHANGES, COMMANDS. Release later via standard DMG sign/notarize pipeline.

## Out of scope (v1)

Semantic search/embeddings, multi-agent sources, team sync (PostgreSQL/DuckDB),
CLI, menu bar extra, Sparkle auto-update.
