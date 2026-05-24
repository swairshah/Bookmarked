# Bookmarked

Bookmarked is a native macOS menu bar bookmark curator inspired by Trackie, with a two-pane library for browsing saved items and reading indexed content.

## Features

- Menu bar app with recent bookmarks, quick search, quick URL add, and capture action.
- Main library window with searchable bookmark list on the left and preview/reader on the right.
- Bookmark classification for web pages, GitHub repositories, images, videos, audio, podcasts, files, and notes.
- `Cmd+Shift+M` global capture shortcut for the frontmost browser page.
- Browser capture for Safari, Chrome, Brave, Edge, Vivaldi, Opera, and Arc using the current tab URL/title.
- Web page indexing via local fetch and HTML text extraction.
- Local JSON storage in `~/Library/Application Support/Bookmarked/bookmarks.json`.

## Run

```bash
swift run Bookmarked
```

## Build App Bundle

```bash
./scripts/build-app.sh
open .build/Bookmarked.app
```

The first capture may prompt for Accessibility and browser automation permissions.
