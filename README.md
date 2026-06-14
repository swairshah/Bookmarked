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

## CLI

Bookmarked exposes a local CLI for agents and scripts while the app is running:

```bash
swift run bookmarked search "oauth" --json
swift run bookmarked link 7602A4C8
swift run bookmarked read 7602A4C8 --format text
swift run bookmarked note 7602A4C8 "Follow up on this."
swift run bookmarked tag 7602A4C8 add research
```

The CLI talks to the running app over a loopback-only local broker, so bookmark
changes update the same in-memory library the UI is showing.
Search and get JSON include an `appLink` such as
`bookmarked://open/7602A4C8-...`, which opens the bookmark inside Bookmarked on
machines where the app is installed.

## Build App Bundle

```bash
./scripts/build-app.sh
open .build/Bookmarked.app
```

The first capture may prompt for Accessibility and browser automation permissions.
