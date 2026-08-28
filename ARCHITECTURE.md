# ClaudeView — Architecture (miroir français)

> Source de vérité : `ARCHITECTURE_EN.md`. Maintenir les deux synchronisés.

## Vue d'ensemble

App macOS native (SwiftUI, macOS 15+). Pas de serveur, pas de daemon. Un seul
processus : l'app héberge l'indexeur, le watcher de fichiers et l'UI.

```
~/.claude/projects/**/*.jsonl
        │
   [LiveWatcher — FSEvents]
        │  fichiers modifiés
        ▼
  [Indexer — incrémental, offset d'octets par fichier]
        │
   ┌────┴─────┐
   ▼          ▼
[SQLite     [LiveEvent
 GRDB+FTS5]  AsyncStream]
   │          │
   ▼          ▼
Sessions/Recherche/  Vue Live
Stats/Coûts          « sniffer »
```

## Modules cœur (indépendants de l'UI)

| Module | Responsabilité |
|---|---|
| `JSONLParser` | Décodage tolérant des lignes transcript Claude Code (`user`, `assistant`, `system`, `ai-title` ; blocs `text`/`thinking`/`tool_use`/`tool_result` ; tokens usage cache compris). Lignes malformées comptées, jamais fatales. |
| `Store` (GRDB) | Schéma SQLite + migrations : `project`, `session`, `message`, `message_fts` (FTS5), `file_state`, `model_price`, `app_setting`. |
| `Indexer` | Scan au démarrage + ingestion incrémentale par fichier (curseur d'offset ; troncature ⇒ réindexation du fichier). Resync complet depuis les Réglages. |
| `LiveWatcher` | Flux FSEvents sur le répertoire des projets, débounce ; alimente l'Indexer ; les messages ingérés sont réémis en `LiveEvent`s (AsyncStream). |
| `PricingEngine` | Tarifs par défaut embarqués (par MTok) + overrides utilisateur ; coûts calculés à la requête (tokens × tarif), jamais stockés. |

## Décisions clés

- **Les payloads ne sont pas dupliqués dans SQLite.** Les lignes `message`
  gardent le texte extrait et `byteOffset/byteLength` ; le détail de
  transcription relit la ligne JSONL à la demande. Base compacte (source
  ≈ 835 Mo).
- **Coûts à la requête.** Modifier un tarif ne réindexe jamais.
- **Chemin d'ingestion unique.** Scan de démarrage et tail temps réel partagent
  le même code d'Indexer ; la vue Live n'est qu'un abonné de la sortie
  d'ingestion.

## UI (SwiftUI)

`NavigationSplitView` avec sections : Dashboard (grille de widgets modulaires,
layout persisté dans `app_setting`), Sessions (arbre projets → `Table`
personnalisable → transcription), Recherche (FTS5 + filtres), Live (table
temps réel + inspecteur de payload, follow/pause), Stats (Swift Charts +
heatmap), Réglages (apparence, tarifs, budgets, données/resync).

## Stockage

`~/Library/Application Support/ClaudeView/claudeview.sqlite` — jetable,
reconstruit depuis les fichiers JSONL (source de vérité).

## Build & outillage

xcodegen (`project.yml`), GRDB via SPM, tests unitaires sur fixtures JSONL
réelles anonymisées. Release : pipeline DevApps standard DMG signé/notarisé.
