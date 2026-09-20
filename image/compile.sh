#!/bin/sh
# Compile a caller-specified .tex document (AGENTS.md P1).
#
#   TEX_FILE  document to compile, relative to /work/src
#
# /work/src is mounted read-only, so no build artifact can ever land next to
# the source. All output goes to /work/out via -output-directory (AGENTS.md P3).
#
# Any extra arguments are passed through to latexmk, which is how a caller
# opts in to something non-default (e.g. -shell-escape) for one invocation
# without it becoming the default for everyone.
set -eu

TEX_FILE="${TEX_FILE:-document.tex}"
SRC_DIR=/work/src
OUT_DIR=/work/out

if [ ! -f "$SRC_DIR/$TEX_FILE" ]; then
    echo "compile-latex: TEX_FILE not found: $TEX_FILE (looked in $SRC_DIR)" >&2
    exit 2
fi

mkdir -p "$OUT_DIR"
cd "$SRC_DIR"

# -cd makes latexmk chdir into the document's own directory, so a TEX_FILE in
# a subdirectory still resolves its relative \input and \includegraphics paths.
# -output-directory must therefore be absolute.
#
# latexmk reruns xelatex until cross-references settle; a single xelatex pass
# leaves \ref/\eqref/toc unresolved (AGENTS.md §6.5).
exec latexmk \
    -xelatex \
    -cd \
    -halt-on-error \
    -file-line-error \
    -interaction=nonstopmode \
    -output-directory="$OUT_DIR" \
    "$@" \
    "$TEX_FILE"
