#!/usr/bin/env bash
# Shared helpers for the contex scripts. Source, do not execute.
#
# Host-side dependencies are deliberately limited to docker, git and a SHA-256
# tool (AGENTS.md P5). Everything to do with PDFs runs inside the image.

CONTEX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$CONTEX_ROOT/fixtures/MANIFEST.md"

# Run as the invoking user so artifacts in build/ are host-owned, not root-owned.
export CONTEX_UID="${CONTEX_UID:-$(id -u)}"
export CONTEX_GID="${CONTEX_GID:-$(id -g)}"

# macOS has shasum; Debian-ish hosts have sha256sum. Accept either.
sha256_of() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"
    else sha256sum "$@"; fi
}

# Read one `key: value` line out of fixtures/MANIFEST.md. No expected value in
# the verification is hardcoded in a script; every one of them comes from here,
# so the manifest and the golden PDF can only ever be updated together.
manifest_get() {
    local key="$1" val
    val="$(sed -n "s/^${key}: //p" "$MANIFEST" | head -1)"
    if [ -z "$val" ]; then
        echo "contex: key '$key' not found in $MANIFEST" >&2
        return 1
    fi
    printf '%s\n' "$val"
}

# Read the fenced code block that follows a `## <heading>` line in the manifest.
# Used for the embedded-font list, which is a set rather than a scalar and so
# cannot be expressed as a `key: value` line.
manifest_get_block() {
    local heading="$1"
    awk -v h="## $heading" '
        $0 == h   { found = 1; next }
        !found    { next }
        /^```/    { if (infence) exit; infence = 1; next }
        infence   { print }
    ' "$MANIFEST"
}

# Normalise a list of PDF font names for comparison.
#
# Two pieces of every name are noise for this purpose:
#   * the six-letter subset tag xdvipdfmx prepends (XVOZHO+...) — it identifies
#     one subsetting run, not the face;
#   * the -Identity-H suffix on the Type0 wrapper, which duplicates every CID
#     font under a second name.
#
# What is left is the face identity, which is what AGENTS.md §6.3 says to check.
normalise_faces() {
    sed -e 's/^[A-Z][A-Z]*+//' -e 's/-Identity-H$//' \
        | grep -E '.' | sort -u
}

# The embedded Noto faces of a PDF, as seen by ghostscript inside the image.
#
# Restricted to Noto because that is the scope fixtures/MANIFEST.md records. The
# Computer Modern maths faces are embedded too and are NOT covered by this check
# — widening it means migrating the manifest, which is a re-baseline (§8).
pdf_noto_faces() {
    dc_run gs -q -dNODISPLAY -dBATCH -dNOPAUSE -dPDFINFO "$1" 2>&1 \
        | strip_compose_noise \
        | sed -n '/Font/,$p' \
        | grep -oE '[A-Za-z0-9+._-]*Noto[A-Za-z0-9+._-]*' \
        | normalise_faces
}

# Run an arbitrary command inside the compile-latex image, overriding the
# entrypoint. This is how gs/compare/pdfinfo are reached without assuming the
# host has them.
#
# `-T` and `</dev/null` are load-bearing, not tidiness. `docker compose run`
# keeps stdin attached by default, so any tool that falls through to an
# interactive prompt blocks forever instead of exiting — observed with
# `gs -dPDFINFO`, which left containers hung for over half an hour and made a
# font listing come back silently empty. Closing stdin turns that class of
# mistake into an immediate EOF rather than a hang.
dc_run() {
    ( cd "$CONTEX_ROOT" \
      && docker compose run --rm -T --entrypoint "$1" compile-latex "${@:2}" </dev/null )
}

# Rebuild the image before using it, so that a change to image/Dockerfile cannot
# be verified — or baselined — against the previously built image.
#
# `docker compose run` builds only when the image is absent, so without this an
# edited Dockerfile silently passes against the old image, which is precisely the
# drift AGENTS.md §5 says a pin bump must be re-verified for.
#
# image/Dockerfile uses `RUN --mount=type=cache`, which requires BuildKit. On a
# host whose docker CLI has no buildx plugin the build cannot run at all, and
# this returns non-zero rather than certifying an image it could not rebuild.
# CONTEX_SKIP_BUILD=1 is the deliberate, and loudly reported, way past that.
ensure_image_current() {
    local logfile="$1"
    if [ "${CONTEX_SKIP_BUILD:-}" = "1" ]; then
        echo "  WARN  CONTEX_SKIP_BUILD=1 — using the existing image as-is."
        echo "        Nothing in this run certifies that it matches image/Dockerfile."
        return 0
    fi
    if ( cd "$CONTEX_ROOT" && docker compose build compile-latex >"$logfile" 2>&1 ); then
        return 0
    fi
    if grep -qE 'requires BuildKit|buildx component is missing|buildx Docker CLI plugin not found' \
        "$logfile" 2>/dev/null; then
        cat >&2 <<'MSG'
  This host's docker CLI has no buildx plugin, and image/Dockerfile needs
  BuildKit for its `RUN --mount=type=cache` layer. Either install buildx, or
  re-run with CONTEX_SKIP_BUILD=1 to accept the image that is already built.
MSG
    fi
    return 1
}

# Strip the "Container ... Creating/Created/Running" lifecycle lines that docker
# compose writes to stderr, so a tool's own stderr output can be parsed.
# (Forgetting this produced a real bug in the upstream harness this is based on.)
strip_compose_noise() {
    grep -v -E '^ *(Container|Network|Volume) ' || true
}

# ImageMagick 6 installs `compare` as its own binary; ImageMagick 7 may provide
# it only as the `magick compare` subcommand. Resolve inside the container so
# the harness does not depend on which of the two the base image carries.
#
#   im_compare <ref.png> <new.png> <diff.png>   -> prints the AE metric
# `compare` exits non-zero when the two images differ. That is a *result*, not an
# error — and without the `|| true` guard, `set -e` plus `set -o pipefail` in the
# calling script would abort the run on exactly the difference the harness exists
# to detect and report. The caller validates that the output is numeric, so a
# genuine tool failure is still caught, as a page failure rather than a crash.
im_compare() {
    { dc_run sh -c \
        'if command -v compare >/dev/null 2>&1; then exec compare "$@"; else exec magick compare "$@"; fi' \
        _ -metric AE "$1" "$2" "$3" 2>&1 || true; } | strip_compose_noise
}
