# Third-party software

humanpls itself is MIT licensed (see `LICENSE`). It includes two JavaScript libraries, built into the app
(`vendor/`, turned into `Sources/humanpls/Vendor.swift` by `scripts/gen-vendor.py`). They render markdown and
color code inside the app, offline.

## marked 12.0.2

- Source: https://github.com/markedjs/marked
- License: MIT
- Copyright (c) 2018+, MarkedJS (https://github.com/markedjs/)
- Copyright (c) 2011-2018, Christopher Jeffrey (https://github.com/chjj/)

## highlight.js 11.9.0

- Source: https://github.com/highlightjs/highlight.js
- License: BSD-3-Clause
- Copyright (c) 2006, Ivan Sagalaev. All rights reserved. Copyright (c) the highlight.js contributors.
- The `github` and `github-dark` color themes (`vendor/*.css`) are part of highlight.js.

The full license texts are in those repositories and at the top of the files in `vendor/`.
Everything else in this repository was written for humanpls.
