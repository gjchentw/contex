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
