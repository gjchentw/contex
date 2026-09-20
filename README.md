# contex

**con**tainer + la**tex** — a pinned, verifiable Docker environment for producing PDFs from
LaTeX sources that mix Traditional Chinese with Latin text and STEM notation.

It is an *environment*, not a document project. Point it at your own `.tex` tree and it
compiles; it never needs your document to accommodate it.

## What it gives you

- **XeLaTeX** with `babel` + `fontspec` so mixed CJK/Latin text needs no manual markup
- **TeX Live 2026 `scheme-full`**, from a base image pinned by content digest, so nothing drifts under you
- **Noto Sans / Noto Serif + Noto CJK TC**, pinned as a package set
- **Reproducible output** via `SOURCE_DATE_EPOCH`, so `\today` does not change your PDF
- **A real acceptance test**: a CJK + STEM stress fixture with a golden PDF, verified page by
  page at the pixel level

## Requirements

Docker, git, and `shasum` (or `sha256sum`). Nothing else — TeX Live, Ghostscript, ImageMagick
and poppler all live inside the image.

## Setup

```sh
printf 'CONTEX_UID=%s\nCONTEX_GID=%s\n' "$(id -u)" "$(id -g)" > .env
docker compose build
```

The `.env` step makes build artifacts owned by you rather than by root. The scripts in
`scripts/` set it themselves, so it only matters for bare `docker compose` calls.

The first build pulls a ~2.6 GB `scheme-full` TeX Live image, so expect it to be dominated by
download time. It is cached afterwards.

`image/Dockerfile` uses `RUN --mount=type=cache` so that an interrupted apt download resumes
instead of restarting, which **requires BuildKit** — i.e. a docker CLI with the `buildx`
plugin. Without it `docker compose build` falls back to the classic builder and fails on that
layer. `scripts/verify-fixture.sh` and `scripts/rebaseline.sh` rebuild the image before they
use it, so that neither can certify a stale one; if you cannot install buildx, run them with
`CONTEX_SKIP_BUILD=1` to use the already-built image, which they will say they are doing.

## Compiling a document

```sh
scripts/compile.sh                            # the bundled template
scripts/compile.sh ~/papers/thesis/main.tex   # anything on disk
scripts/compile.sh ~/papers/thesis main.tex   # explicit source dir + file
```

Or through compose directly:

```sh
TEX_SRC_DIR=~/papers/thesis TEX_FILE=main.tex docker compose run --rm compile-latex
```

The source directory is mounted **read-only**; output always lands in `build/`, never next to
your source. Extra `latexmk` flags go through `LATEXMK_ARGS`.

## Using the style files

```latex
\documentclass[11pt, a4paper]{article}
\usepackage[a4paper, margin=2cm]{geometry}   % page layout stays yours
\usepackage{contex-cjk}                      % [sans] or [serif] (default)
\usepackage{contex-stem}
```

`contex-cjk.sty` sets up languages and fonts. `contex-stem.sty` loads the maths, table and
figure packages. Neither touches page layout, line spacing or indentation — those are
per-document decisions. See `template/document.tex`.

## Verifying the environment

```sh
scripts/verify-fixture.sh
```

Compiles `fixtures/fixture.tex` and compares it against the golden `fixtures/fixture.pdf`:
cheap fingerprints first (page count and size, `\textwidth`, the exact overfull-hbox
magnitude, and the set of font faces the PDF embedded), then a per-page pixel diff requiring
zero differing pixels. If a fingerprint moved, it stops before rendering — the environment
already differs, and a pixel diff would only say so more slowly. Run it after any change to
the image or the style files.

If you deliberately changed the environment and the output legitimately moved:

```sh
CONTEX_REBASELINE=i-understand scripts/rebaseline.sh
```

## For AI agents

Read [AGENTS.md](AGENTS.md) first. It is normative, and it carries both the rules and the
background knowledge needed to work on this environment without breaking its guarantees.
