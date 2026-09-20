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
dc_run() {
    ( cd "$CONTEX_ROOT" && docker compose run --rm --entrypoint "$1" compile-latex "${@:2}" )
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
im_compare() {
    dc_run sh -c \
        'if command -v compare >/dev/null 2>&1; then exec compare "$@"; else exec magick compare "$@"; fi' \
        _ -metric AE "$1" "$2" "$3" 2>&1 | strip_compose_noise
}
