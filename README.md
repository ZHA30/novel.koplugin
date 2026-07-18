# Novel for KOReader

Read online novels in KOReader, manage a bookshelf, and cache chapters for offline reading.

## What it does

- Search and browse enabled book sources.
- View book details and chapter catalogs.
- Add books to a bookshelf and track reading progress.
- Read chapters online or download them for offline use.
- Manage downloads, cache data, reading appearance, and book sources.
- Retry failed search and discovery requests from the error dialog or action bar.

## Installation

1. Place the plugin directory under KOReader's `plugins/` directory:
   `plugins/novel.koplugin`
2. Restart KOReader.

## How to access it

From the KOReader main menu, open:

```text
Search
└─ Novel
```

## Interface preview

The following TUI mockups show the main navigation and common pages. They are illustrative; the action bar can be placed at the bottom, left, or right side.

```text
┌──────────────────────────────────────────────┐
│ Bookshelf                         [refresh]   │
│                                   [select]    │
├──────────────────────────────────────────────┤
│ The Three-Body Problem                    ⋮  │
│   12 unread · 3 offline · 120 chapters       │
│ The Wandering Earth                        ⋮  │
│    4 unread · 0 offline ·  80 chapters       │
│                                              │
├──────────────────────────────────────────────┤
│ Bookshelf    Discover       More        Exit  │
└──────────────────────────────────────────────┘
```

```text
┌──────────────────────────────────────────────┐
│ More                                         │
├──────────────────────────────────────────────┤
│ ⚙  Settings                              ›  │
│ ↓  Download queue                         2  │
│ ◈  Sources                                5  │
│                                              │
├──────────────────────────────────────────────┤
│ Bookshelf    Discover       More        Exit  │
└──────────────────────────────────────────────┘
```

## Configuration / Usage

### Bookshelf and reading

Book actions include `Intro`, `Chapters`, `Refresh`, `Download`, and remove. The chapter catalog supports filtering, sorting, read/unread state, offline status, and bulk actions for downloading or deleting chapters.

Cached chapters can be opened without another network request. Download tasks run while KOReader is running and can be paused or resumed from `Download queue`.

### Discover and search

Use `Discover` to browse source groups and discovery entries, or search a selected source. Result lists support local and source-provided pagination. When a request fails, use `Retry` in the error dialog or the action bar.

### Downloads

`Settings > Download` controls the background mode:

- `Only in Novel`
- `Pause while reading`
- `Always download in background`

It also controls the number of simultaneous downloads.

### Interface, reading, and cache

- `Settings > Interface`: place the action bar at the bottom, left, or right, and optionally follow its side.
- `Settings > Reading`: adjust the intro font, font size, and margins.
- `Settings > Cache`: view cache usage, set the metadata cache limit, or clear metadata records.

Clearing metadata cache does not delete downloaded chapter files.

### Sources

Place book source JSON files in the plugin's `source/` directory. Each source defines how Novel searches or discovers books, reads details, loads chapter catalogs, and extracts chapter content.

Source rules must follow the supported subset documented in [`source/AGENTS.md`](source/AGENTS.md). They should use real HTML or JSON responses and must not depend on browser JavaScript, WebView behavior, login scripts, or dynamic signing logic.

## Limits / Notes

- Sources may stop working when upstream websites change.
- Network access is required for uncached searches, metadata, catalogs, and chapters.
- Background downloads run only while KOReader is running.
- Retry can repeat a request, but cannot fix an unavailable site or invalid source rule.
