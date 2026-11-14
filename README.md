# humanpls

*Human, please.* A native macOS app that lets an AI agent ask you to pick between options, or just show you files.

The agent runs one command. A popup opens, you choose, and the answer goes back into the chat (or to the command that waited for it). No browser, no lost focus, no paths to open by hand.

```
humanpls pick --id narrator --question "Which take fits?" a.wav::calm "*b.wav::older, raspy" c.wav
humanpls pick --id ep02 --section Name text:Aung text:Maung --section Plates --multi a.png b.png c.png
humanpls show gen/ clip.mp4 notes.md
humanpls reopen          # open the last popup again
```

## What it does

- **pick**: a sidebar page with one card per option. Text, audio (waveform), image (zoom), video, markdown and code (with syntax colors), HTML, PDF, and any other file (Quick Look thumbnail, Open, Reveal). Pick one or several, "none of these", a note per question, a Recommended badge that starts picked, select all.
- **show**: a viewer with a file list. Images: pinch zoom, pen, rectangle, arrow, text, colors, undo; Info panel with the prompt and seed stored in PNG files; A/B compare (side by side with synced zoom, or flip with `F`). Video: J K L (backward, pause, forward, faster on repeat), frame step, `M` to mark a moment with a note. Audio: waveform, marks.
- **Send**: the answer is pasted into the terminal that ran the command and Enter is pressed. With tmux it goes to the exact pane, even if you switched apps. Otherwise it goes to the terminal app (needs the Accessibility permission). **Copy only** just copies. `--wait` prints the answer instead, for agents that can wait.
- **Menu bar icon** with the history. Click a popup to open it again with your picks.
- **Keyboard**: `A`-`Z` pick, `0` none of these, `[` `]` change question, `Space` or `⌘Y` Quick Look, `⌘↩` send, `Esc` cancel.

Files are read from the path the agent gave. Nothing is copied. An annotated image is the only new file: it is written to `~/Library/Application Support/humanpls/annotations/` and deleted after 14 days.

## Install

```
./scripts/install.sh
```

Builds `humanpls.app` into `~/Applications` and links the `humanpls` command into `~/.local/bin`. Needs macOS 14+ and Xcode (Swift 6).

Development: `swift build`, `swift test`, `./scripts/e2e.sh`, `./scripts/build-app.sh debug`.

## Layout

```
Sources/HumanplsCore   job model, option parsing, answer text, history, marks, annotations, socket. No UI. Unit tested.
Sources/humanpls       the app and the CLI (one binary: no arguments = menu bar app)
Tests/                 unit tests for the core
scripts/               install, build-app, e2e, icon, vendor
vendor/                marked and highlight.js, turned into Sources/humanpls/Vendor.swift by scripts/gen-vendor.py
docs/PROTOCOL.md       the CLI, the socket protocol, the JSON options format and the answer text
```

## Tests

- `swift test`: core logic (option parsing, answers, history, PNG text chunks, marks, annotation undo, socket).
- `./scripts/e2e.sh`: CLI to socket to app to answer, with no window (`HUMANPLS_AUTOANSWER`). Run it on the built app with `BIN=build/humanpls.app/Contents/MacOS/humanpls ./scripts/e2e.sh`.
- `humanpls selftest`: draws annotations, exports a PNG and checks pixels, color profile and file locations.

The visual parts (layout, clicks, zoom feel) are checked by hand.

## maggot

The `humanpls` maggot tool is a bridge: it finds the `humanpls` command and passes the arguments on. It lives in the maggot drafts folder, not in this repo.
