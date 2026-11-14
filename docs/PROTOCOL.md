# humanpls protocol

## CLI

```
humanpls pick --id ID [--title T] [--question Q] [--multi] [--recommend KEY]... [--default KEY]... [--no-preselect]
              [--items FILE.json] [--section TITLE OPTION...]... [--wait] [--timeout SECONDS] [--dump-job] [OPTION...]
humanpls show [--id ID] [--title T] [--compare] [--wait] [--dump-job] FILE_OR_FOLDER...
humanpls reopen [ID]      humanpls list      humanpls quit      humanpls install-cli [DIR]      humanpls serve      humanpls selftest
```

`show --compare` opens the first two images side by side (it needs at least two images).

An OPTION is `path`, `path::label`, `text:Aung` or `text:Aung::note`. A leading `*` marks it recommended (it starts picked).
Short text (up to 80 characters, one line) is shown as a big chip, longer text as a text card.
Kinds are chosen from the file extension: image, video, audio, markdown, code (language from the extension), html, pdf, text.
An unknown extension is text if the start of the file is UTF-8 text, else a generic file card.

Exit codes: `0` answered or opened, `2` bad input, `3` popup closed without an answer (`--wait`), `4` timeout (`--wait`), `5` app problem.

Without `--wait` the command prints `opened: ID (N items)` and returns. The answer is pasted into the terminal that ran the command.
With `--wait` the command prints the answer text and returns; nothing is pasted.

## Options JSON (`--items`)

A list, `{"items": [...]}` or `{"sections": [...]}`.

```json
{"sections": [
  {"id": "name", "title": "Name", "question": "What do we call him?", "multi": false, "recommend": "B",
   "items": [{"text": "Aung"}, {"text": "Maung"}]},
  {"id": "plates", "title": "Plates", "multi": true,
   "items": [{"file": "a.png", "label": "Wide", "recommended": true}, {"markdown": "# Notes"}, {"code": "let x = 1", "language": "swift"}]}
]}
```

Item keys: one of `file`, `text`, `markdown`, `code` (+ `language`), `html`, `url`; and `label`, `note`, `recommended`, `selected`.
Relative `file` paths are relative to the JSON file. Question keys: `id`, `title`, `question`, `multi`, `recommend`, `default`, `preselect`.

## Answer text

One question:

```
[narrator-voice] picked: B "older, raspy" (take2.wav)
feedback: a bit slower
```

Several questions:

```
[ep02]
Name: B "Maung"
Voice: none of these: try again | note: all too young
Plates: A "Living room" (a.png); C "Garden" (c.png) | annotated: A "Living room" /path/a-annotated-251115-021000.png
feedback: same house as episode 1
```

`show`:

```
[look]
clip.mp4: @0:02.4 "hand glitch"; @0:03.1
face.png: annotated /path/face-annotated-251115-021000.png
a message from the person
```

## Socket (for other clients)

Unix socket `~/Library/Application Support/humanpls/humanpls.sock` (`HUMANPLS_SOCKET` overrides, `HUMANPLS_HOME` moves all app data).
One JSON object per line, both ways.

Request: `{"cmd": "pick|show|reopen|list|quit|ping", "job": {...}, "env": {...}, "wait": false, "ref": "id"}`.
Response lines: `{"type": "accepted"}` then, with `wait`, `{"type": "answer", "status": "sent|copied|cancelled", "answer": "..."}`;
`{"type": "jobs", "jobs": [...]}` for `list`; `{"type": "error", "message": "..."}`.
`humanpls pick --dump-job` prints a valid `job`. `env` carries `tmuxPane`, `tmuxSocket`, `tmuxPath`, `bundleId`, `cwd` so the answer reaches the right chat.

## Test mode

`HUMANPLS_AUTOANSWER=send|copy|cancel` on the CLI makes the app answer at once with the default picks and open no window.
