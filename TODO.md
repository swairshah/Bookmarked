# TODO — exploratory features

Experiments to try, roughly in order. These are explorations, not commitments —
the point is to prototype, see what's possible, and keep what works.

## 1. Document sync + the release story

Write up the sync architecture in the README (file-per-bookmark iCloud container +
Multipeer local sync, one-writer model) and figure out the release path:

- How would we ship the iOS app (App Store) and the macOS app (direct download /
  notarized DMG vs Mac App Store)?
- How does sync work for *released* apps? Open problem: the Mac app is
  non-sandboxed (Accessibility + Apple Events for capture) and writes directly
  into `~/Library/Mobile Documents/iCloud~com~swairshah~Bookmarked/...`. Mac App
  Store requires the sandbox, which breaks capture and the direct-write trick.
  - Options to explore: ship Mac app outside MAS (notarized, keeps current model);
    split a sandboxed sync helper; or move both apps to CloudKit proper.
- Document the pairing-code Multipeer flow for someone who isn't me.

## 2. Capture / import articles from iOS

Today iOS is read-only. I want to bookmark an article *from* iPhone/iPad and have
it land in the library. Processing (fetch, index, reader extraction) can happen on
the Mac. Explore what's possible:

- iOS share sheet extension → save URL + title as a "pending" bookmark.
- Transport: write an intent file into the iCloud container (Mac watches and
  processes), and/or push over Multipeer when the Mac is reachable.
- This breaks the one-writer assumption (SYNC.md limitation) — need
  last-writer-wins by `updatedAt`, a separate `Pending/` directory the Mac owns
  merging for, or a move to CloudKit.
- Can iOS do its own lightweight fetch/extraction when the Mac is away, with the
  Mac redoing a full index later?

## 3. Note-taking experiments

Attach notes to bookmarks in whatever way feels natural per device. Experiment
with several modes and see which stick:

- **Audio** — record a voice note (walking, reading), transcribe on-device.
- **Handwriting** — PencilKit on iPad, scribble over/next to an article.
- **Typing** — Mac (already have `bookmarked note` in the CLI + notes in the data
  model); quick-add UI in the reader.
- Notes travel inside the per-bookmark JSON already — check size/format
  implications (audio blobs? ink data? store alongside as `<uuid>.note.*`?).

## 4. Richer search

Flesh out what real search should be and which features to expose:

- Full-text over indexed article content, not just titles/URLs.
- Filters: type (article/repo/video/...), tags, date ranges, domain.
- Ranking, fuzzy matching, snippets with highlighted matches.
- Where it lives: library UI, menu bar quick search, CLI (`bookmarked search`) —
  keep all three consistent.

## 5. Agentic search + LLMs in the app

Related to #4 but bigger: language models as part of the app.

- **On-device**: Apple's Foundation Models framework (new OS releases) — free,
  private, offline. Good for: summarize, auto-tag, semantic-ish search, "what did
  I save about X?"
- **Remote**: Claude / GPT for heavier work — talk to an article, ask questions
  across bookmarks, draft notes from a conversation.
- Experiments: chat-with-article pane, model-written notes saved back to the
  bookmark, natural-language search that falls back from on-device → remote.

## 6. Article narration (listen on the go)

Convert an article to narrated audio and listen away from the screen:

- Start with system TTS (AVSpeechSynthesizer / personal voice), then compare
  higher-quality options (local neural TTS, remote APIs).
- Long articles: chunking, background audio, lock-screen / AirPods controls,
  remember playback position.
- Sync angle: narration generated once (Mac?) and synced as an audio asset vs
  generated on-device on demand.
