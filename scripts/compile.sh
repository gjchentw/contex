#!/usr/bin/env bash
# Compile a document through the compile-latex service.
#
#   scripts/compile.sh                          # template/document.tex
#   scripts/compile.sh path/to/paper.tex        # a document anywhere on disk
#   scripts/compile.sh path/to/dir paper.tex    # explicit source dir + file
#
# Extra latexmk flags can be passed via LATEXMK_ARGS. The output always lands in
# build/ (override with TEX_OUT_DIR), never next to the source.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case $# in
  0) src="$CONTEX_ROOT/template"; file="document.tex" ;;
  1) src="$(cd "$(dirname "$1")" && pwd)"; file="$(basename "$1")" ;;
  2) src="$(cd "$1" && pwd)"; file="$2" ;;
  *) echo "usage: $0 [<file.tex> | <srcdir> <file.tex>]" >&2; exit 64 ;;
esac

out="${TEX_OUT_DIR:-$CONTEX_ROOT/build}"
mkdir -p "$out"

echo "contex: compiling $file"
echo "        source $src (read-only)"
echo "        output $out"

cd "$CONTEX_ROOT"
TEX_SRC_DIR="$src" TEX_OUT_DIR="$out" TEX_FILE="$file" \
    docker compose run --rm compile-latex ${LATEXMK_ARGS:-}

echo "contex: wrote $out/$(basename "$file" .tex).pdf"
