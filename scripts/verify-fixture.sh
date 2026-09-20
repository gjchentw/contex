#!/usr/bin/env bash
# AGENTS.md §7 — the acceptance test for the compile-latex service (P2).
#
# Compiles fixtures/fixture.tex through the service and compares the result
# against fixtures/fixture.pdf page by page. Never writes to the fixtures.
#
# Every expected value comes from fixtures/MANIFEST.md, not from this script.
# Every gs/compare/pdfinfo call runs *inside* the compile-latex container, so
# the only host-side dependencies are docker, git and shasum (AGENTS.md P5).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$CONTEX_ROOT"

REF_TEX=fixtures/fixture.tex
REF_PDF=fixtures/fixture.pdf
REF_PDF_C=/work/src/fixture.pdf        # REF_PDF as seen inside the container
OUT_DIR=build/fixture
OUT_DIR_C=/work/out
WORK=build/fixture/verify
WORK_C=/work/out/verify
NEW_PDF="$OUT_DIR/fixture.pdf"
NEW_PDF_C="$OUT_DIR_C/fixture.pdf"
LOG="$OUT_DIR/fixture.log"

DPI="$(manifest_get render_dpi)"
EPOCH="$(manifest_get source_date_epoch)"

# Exported, not passed inline, because every dc_run helper call below also goes
# through docker compose and must see the same mounts: the fixtures tree at
# /work/src (read-only) and the scratch output at /work/out.
export TEX_SRC_DIR=./fixtures
export TEX_OUT_DIR="./$OUT_DIR"
export TEX_FILE=fixture.tex

fail=0
note() { printf '%s\n' "$*"; }
check() { # check <label> <actual> <expected>
    if [ "$2" = "$3" ]; then printf '  PASS  %-26s %s\n' "$1" "$2"
    else printf '  FAIL  %-26s %s (expected %s)\n' "$1" "$2" "$3"; fail=1; fi
}

# --- Step 1: record fixture checksums -------------------------------------
note "== Step 1: fixture checksums (before) =="
before=$(sha256_of "$REF_TEX" "$REF_PDF")
printf '%s\n' "$before" | sed 's/^/  /'
git_before=$(git status --porcelain fixtures/ || true)

# --- Step 2: compile through the service ----------------------------------
note ""; note "== Step 2: compile via docker compose (SOURCE_DATE_EPOCH=$EPOCH) =="
rm -rf "$OUT_DIR"; mkdir -p "$WORK"
ensure_image_current "$WORK/build.out" || {
    note "  image build FAILED — last 20 lines of $WORK/build.out:"
    tail -20 "$WORK/build.out" | sed 's/^/  /'; exit 1; }
SOURCE_DATE_EPOCH="$EPOCH" FORCE_SOURCE_DATE=1 \
    docker compose run --rm compile-latex >"$WORK/compile.out" 2>&1 || {
        note "  compile FAILED — last 30 lines:"
        tail -30 "$WORK/compile.out" | sed 's/^/  /'; exit 1; }
note "  produced $NEW_PDF"

# --- Step 3: cheap fingerprints -------------------------------------------
# Each of these is a direct function of font metrics and line breaking, so a
# mismatch here says the environment is wrong and pixel comparison would only
# confirm it more slowly. Assert them before spending time on rendering.
note ""; note "== Step 3: fingerprints =="
# poppler's pdfinfo, not `gs -c ... runpdfbegin`: the latter needs -dNOSAFER to
# reach the file operator, and there is no reason to disable ghostscript's file
# sandbox for something pdfinfo reports directly. poppler is in the image for
# exactly this (AGENTS.md P5).
pdfinfo_out=$(dc_run pdfinfo "$NEW_PDF_C" 2>&1 | strip_compose_noise)
pages=$(printf '%s\n' "$pdfinfo_out" | sed -n 's/^Pages: *//p' | head -1)
check "page count" "$pages" "$(manifest_get page_count)"

papersize=$(printf '%s\n' "$pdfinfo_out" | sed -n 's/^Page size: *//p' | head -1)
check "page size" "$papersize" "$(manifest_get page_size)"

tw=$(sed -n 's/^\* .textwidth=//p' "$LOG" | head -1)
th=$(sed -n 's/^\* .textheight=//p' "$LOG" | head -1)
check "textwidth" "$tw" "$(manifest_get textwidth)"
check "textheight" "$th" "$(manifest_get textheight)"

overfull=$(grep -c 'Overfull \\hbox' "$LOG" || true)
check "overfull hbox count" "$overfull" "$(manifest_get overfull_count)"
# `|| true`: under `set -o pipefail` a no-match grep would abort the run instead
# of letting the check below report the mismatch it exists to report.
sig=$(grep -o 'Overfull \\hbox ([0-9.]*pt too wide) in paragraph at lines [0-9-]*' "$LOG" | head -1 || true)
check "overfull signature" "$sig" "$(manifest_get overfull_signature)"

# Which faces the PDF actually embedded. This is the check AGENTS.md §6.3 calls
# for ("Inspect, do not assume"), and it is the only one here that can catch a
# font resolving to the wrong face — a pixel diff cannot, because the golden was
# produced by whatever the resolution happened to be at baseline time.
faces_actual=$(pdf_noto_faces "$NEW_PDF_C")
faces_expect=$(manifest_get_block "Embedded font faces" | normalise_faces)
if [ "$faces_actual" = "$faces_expect" ]; then
    printf '  PASS  %-26s %s face(s)\n' "embedded font faces" \
        "$(printf '%s\n' "$faces_actual" | grep -c .)"
else
    printf '  FAIL  %-26s differs from MANIFEST.md\n' "embedded font faces"
    diff <(printf '%s\n' "$faces_expect") <(printf '%s\n' "$faces_actual") \
        | sed 's/^/        /' || true
    fail=1
fi

# §6.4: if a fingerprint moved, the environment is already wrong and rendering
# would only say so more slowly. Skip Steps 4 and 5 — but not Step 6, which is
# P3 enforcement and has to run whatever else happened.
fingerprints_ok=$fail

if [ "$fingerprints_ok" -ne 0 ]; then
    note ""; note "== Steps 4 and 5 skipped =="
    note "  A Step 3 fingerprint moved, so the environment already differs from"
    note "  the one that produced the golden. Diagnose that first; a pixel diff"
    note "  would only say the same thing more slowly (AGENTS.md §6.4)."
else
    # --- Step 4: render both PDFs with the same renderer at the same DPI ------
    # Naming the renderer and the DPI is what makes this reproducible; comparing
    # images produced by two different renderers proves nothing.
    note ""; note "== Step 4: render both at ${DPI}dpi (ghostscript png16m, in-container) =="
    for side in ref new; do
        srcC=$([ "$side" = ref ] && echo "$REF_PDF_C" || echo "$NEW_PDF_C")
        dc_run gs -q -dNOPAUSE -dBATCH -sDEVICE=png16m -r"$DPI" \
            -sOutputFile="$WORK_C/${side}-%02d.png" "$srcC" >/dev/null 2>&1
    done
    ref_pages=$(ls "$WORK"/ref-*.png 2>/dev/null | wc -l | tr -d ' ')
    new_pages=$(ls "$WORK"/new-*.png 2>/dev/null | wc -l | tr -d ' ')
    note "  $ref_pages reference pages, $new_pages new pages"
    # Without this guard an empty render would leave the Step 5 glob unexpanded and
    # the loop would "compare" a literal filename, reporting a confusing miss rather
    # than the real problem. Asserting equality also catches a new PDF that has more
    # pages than the golden, which the Step 5 loop would otherwise never look at.
    if [ "$ref_pages" -eq 0 ] || [ "$new_pages" -eq 0 ]; then
        note "  FAIL  rasterisation produced no pages — cannot compare"; fail=1
    fi
    check "rendered page parity" "$new_pages" "$ref_pages"

    # --- Step 5: per-page pixel comparison (in-container) ----------------------
    note ""; note "== Step 5: per-page pixel diff (metric AE, threshold 0, in-container) =="
    total=0
    shopt -s nullglob
    for ref in "$WORK"/ref-*.png; do
        n=$(basename "$ref" .png); n=${n#ref-}
        new="$WORK/new-$n.png"
        if [ ! -f "$new" ]; then
            printf '  FAIL  page %s: missing in new output\n' "$n"; fail=1; continue; fi
        # `compare` writes its metric to stderr, and so does docker compose's own
        # container lifecycle chatter — im_compare strips the noise before returning.
        raw=$(im_compare "$WORK_C/ref-$n.png" "$WORK_C/new-$n.png" "$WORK_C/diff-$n.png")
        ae=${raw%% *}; ae=${ae%.*}
        # `compare` reports a non-numeric error message when, for example, the two
        # images differ in geometry. Arithmetic on that would abort the whole run
        # under `set -e`, hiding the real cause, so surface it as a page failure.
        if ! [[ "$ae" =~ ^[0-9]+$ ]]; then
            printf '  FAIL  page %s  compare did not return a metric: %s\n' "$n" "${raw:-<empty>}"
            fail=1; continue
        fi
        total=$(( total + ae ))
        if [ "$ae" -eq 0 ]; then printf '  PASS  page %s  differing pixels: %s\n' "$n" "$ae"
        else printf '  FAIL  page %s  differing pixels: %s  (see %s)\n' "$n" "$ae" "$WORK/diff-$n.png"; fail=1; fi
    done
    shopt -u nullglob
    note "  total differing pixels: $total"
fi

# --- Step 6: fixtures untouched -------------------------------------------
note ""; note "== Step 6: fixture checksums (after) =="
after=$(sha256_of "$REF_TEX" "$REF_PDF")
if [ "$before" = "$after" ]; then note "  PASS  fixtures unchanged"
else note "  FAIL  FIXTURES MODIFIED — AGENTS.md P3 violated"; fail=1; fi
check "tex sha256" "$(printf '%s\n' "$after" | awk '/fixture.tex/{print $1}')" "$(manifest_get fixture_tex_sha256)"
check "pdf sha256" "$(printf '%s\n' "$after" | awk '/fixture.pdf/{print $1}')" "$(manifest_get fixture_pdf_sha256)"
# The requirement is that this run did not change the fixtures, which is well
# defined whether or not they are committed yet. Requiring the porcelain output
# to be *empty* would instead fail on a fresh checkout where the fixtures are
# still untracked, which says nothing about whether the run touched them.
git_after=$(git status --porcelain fixtures/ || true)
if [ "$git_before" = "$git_after" ]; then note "  PASS  git state on fixtures/ unchanged by this run"
else
    note "  FAIL  git reports fixture changes caused by this run:"
    diff <(printf '%s\n' "$git_before") <(printf '%s\n' "$git_after") | sed 's/^/        /' || true
    fail=1
fi
# P3's enforcement leans on git being able to restore the fixtures. If they are
# not committed, the checksum check above still holds but that safety net does
# not exist, so say so rather than passing silently.
if printf '%s\n' "$git_after" | grep -qE '^\?\? fixtures/fixture\.(tex|pdf)'; then
    note "  WARN  fixtures are untracked — commit them so P3 has a restore path"
fi

note ""
[ "$fail" -eq 0 ] && note "RESULT: PASS" || note "RESULT: FAIL"
exit "$fail"
