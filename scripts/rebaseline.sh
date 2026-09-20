#!/usr/bin/env bash
# Regenerate fixtures/fixture.pdf and fixtures/MANIFEST.md (AGENTS.md §8).
#
# This is the ONLY legitimate way for fixtures/fixture.pdf to change. It is
# guarded, loud, and it rewrites the manifest in the same run, so that a commit
# changing the golden PDF without updating its recorded fingerprints cannot be
# produced by accident.
#
# A re-baseline is legitimate when the environment is deliberately changed — a
# new tlnet snapshot, a different font package set, an edit to style/ — and NOT
# as a way to make a failing verification pass. If you did not intend to change
# typeset output, a re-baseline is the wrong tool: find out why the output moved.
#
#   CONTEX_REBASELINE=i-understand scripts/rebaseline.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$CONTEX_ROOT"

if [ "${CONTEX_REBASELINE:-}" != "i-understand" ]; then
    cat >&2 <<'MSG'
rebaseline: refusing to run.

This overwrites the golden PDF that the acceptance test compares against.
If the verification is failing and you did not deliberately change the
environment, this is not the fix — diagnose the change instead (AGENTS.md §9).

To proceed deliberately:

    CONTEX_REBASELINE=i-understand scripts/rebaseline.sh
MSG
    exit 1
fi

REF_TEX=fixtures/fixture.tex
REF_PDF=fixtures/fixture.pdf
OUT_DIR=build/rebaseline
WORK="$OUT_DIR/verify"
WORK_C=/work/out/verify
NEW_PDF="$OUT_DIR/fixture.pdf"
NEW_PDF_C=/work/out/fixture.pdf
LOG="$OUT_DIR/fixture.log"

# On a first baseline there is no manifest yet, so these fall back to defaults.
EPOCH="${SOURCE_DATE_EPOCH:-$(manifest_get source_date_epoch 2>/dev/null || echo 1789862400)}"
DPI="${CONTEX_DPI:-$(manifest_get render_dpi 2>/dev/null || echo 150)}"
BASE_IMAGE="$(sed -n 's/^FROM //p' image/Dockerfile | head -1)"

# Exported so that the dc_run helper calls below see the same mounts.
export TEX_SRC_DIR=./fixtures
export TEX_OUT_DIR="./$OUT_DIR"
export TEX_FILE=fixture.tex

echo "== compiling fixture (SOURCE_DATE_EPOCH=$EPOCH) =="
rm -rf "$OUT_DIR"; mkdir -p "$WORK"
SOURCE_DATE_EPOCH="$EPOCH" FORCE_SOURCE_DATE=1 \
    docker compose run --rm compile-latex >"$OUT_DIR/compile.out" 2>&1 || {
        echo "compile FAILED — last 30 lines:"; tail -30 "$OUT_DIR/compile.out"; exit 1; }

# --- show what is about to change ----------------------------------------
if [ -f "$REF_PDF" ]; then
    echo ""; echo "== pixel delta against the OUTGOING golden (${DPI}dpi) =="
    cp "$REF_PDF" "$OUT_DIR/outgoing.pdf"
    for side in old:outgoing.pdf new:fixture.pdf; do
        name=${side%%:*}; f=${side#*:}
        dc_run gs -q -dNOPAUSE -dBATCH -sDEVICE=png16m -r"$DPI" \
            -sOutputFile="$WORK_C/${name}-%02d.png" "/work/out/$f" >/dev/null 2>&1
    done
    for old in "$WORK"/old-*.png; do
        n=$(basename "$old" .png); n=${n#old-}
        new="$WORK/new-$n.png"
        if [ ! -f "$new" ]; then printf '  page %s: REMOVED\n' "$n"; continue; fi
        ae=$(im_compare "$WORK_C/old-$n.png" "$WORK_C/new-$n.png" "$WORK_C/diff-$n.png")
        printf '  page %s  differing pixels: %s\n' "$n" "${ae%% *}"
    done
    for new in "$WORK"/new-*.png; do
        n=$(basename "$new" .png); n=${n#new-}
        [ -f "$WORK/old-$n.png" ] || printf '  page %s: ADDED\n' "$n"
    done
else
    echo ""; echo "== no existing golden; this is the first baseline =="
fi

# --- adopt the new golden -------------------------------------------------
echo ""; echo "== adopting new golden =="
cp "$NEW_PDF" "$REF_PDF"

# --- collect fingerprints -------------------------------------------------
pages=$(dc_run gs -q -dNODISPLAY -dNOSAFER \
    -c "($NEW_PDF_C) (r) file runpdfbegin pdfpagecount = quit" 2>&1 \
    | strip_compose_noise | tr -d '[:space:]')
papersize=$(dc_run pdfinfo "$NEW_PDF_C" 2>&1 | strip_compose_noise \
    | sed -n 's/^Page size: *//p' | head -1)
tw=$(sed -n 's/^\* .textwidth=//p' "$LOG" | head -1)
th=$(sed -n 's/^\* .textheight=//p' "$LOG" | head -1)
ovc=$(grep -c 'Overfull \\hbox' "$LOG" || true)
ovs=$(grep -o 'Overfull \\hbox ([0-9.]*pt too wide) in paragraph at lines [0-9-]*' "$LOG" | head -1)
engine=$(grep -m1 -oE 'This is XeTeX[^(]*' "$LOG" | sed 's/ *$//')
# The base image is pinned by digest, which does not say which day's TeX Live
# is inside it. Record that here instead, so the manifest remains a complete
# description of the environment (AGENTS.md §5).
tlversion=$(dc_run tlmgr --version 2>&1 | strip_compose_noise \
    | grep -E 'tlmgr revision|TeX Live .* version' | tr '\n' ' ' | sed 's/ *$//')
fonts=$(dc_run gs -q -dNODISPLAY -dPDFINFO "$NEW_PDF_C" 2>&1 | strip_compose_noise \
    | sed -n '/Font/,$p' | grep -oE '[A-Za-z0-9+._-]*Noto[A-Za-z0-9+._-]*' | sort -u)
texsha=$(sha256_of "$REF_TEX" | awk '{print $1}')
pdfsha=$(sha256_of "$REF_PDF" | awk '{print $1}')

cat > "$MANIFEST" <<MD
# fixtures/MANIFEST.md

Machine-readable record of the golden fixture and the environment that produced
it. \`scripts/verify-fixture.sh\` reads every expected value from here, so this
file and \`fixture.pdf\` are only ever updated together, by
\`scripts/rebaseline.sh\` (AGENTS.md §8).

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Environment

base_image: $BASE_IMAGE
texlive_version: $tlversion
engine: $engine

## Build determinism

source_date_epoch: $EPOCH
render_dpi: $DPI

## Fixture integrity

fixture_tex_sha256: $texsha
fixture_pdf_sha256: $pdfsha

## Layout fingerprints

page_count: $pages
page_size: $papersize
textwidth: $tw
textheight: $th
overfull_count: $ovc
overfull_signature: $ovs

## Embedded font faces

\`\`\`
$fonts
\`\`\`
MD

echo ""
sed 's/^/  /' "$MANIFEST"
echo ""
echo "Commit fixtures/fixture.pdf and fixtures/MANIFEST.md together, and state"
echo "in the commit message what environment change made the re-baseline necessary."
