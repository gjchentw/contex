# contex — build environment for the `compile-latex` service.
#
# Every pin in this file exists so that the same .tex source produces a
# byte-comparable PDF today and a year from now. Do not "upgrade" anything
# here casually: bumping a pin is a re-baseline (AGENTS.md §8), not a chore.

# TeX Live 2026, scheme-full, pinned by immutable content digest.
#
# Why a digest rather than a dated tlnet snapshot: a digest names exactly one
# set of bytes and cannot be changed under us, which is a stronger guarantee
# than any URL. (The `latest` tag moves; this digest does not. Never replace it
# with `:latest`.)
#
# The trade-off, recorded here because it is not visible from this file alone:
# the Dockerfile no longer states *which day's* TeX Live is inside. That is why
# `scripts/rebaseline.sh` records the engine banner and TeX Live version into
# fixtures/MANIFEST.md on every baseline — see AGENTS.md §5.
FROM texlive/texlive@sha256:6530544393bd37b4aec8801292231ff61599aca43a04571306479a21591e87dd

ENV DEBIAN_FRONTEND=noninteractive

# fonts-noto-core    -> "Noto Sans" / "Noto Serif"      (Latin slots)
# fonts-noto-cjk*    -> "Noto Sans CJK TC" / "Noto Serif CJK TC"
# poppler-utils      -> pdftoppm/pdfinfo
# ghostscript        -> gs, for page counts and PNG rasterisation
# imagemagick        -> compare/magick, for the per-page pixel diff
#
# ghostscript and imagemagick are deliberately baked in so that
# scripts/verify-fixture.sh runs entirely through this image. The harness must
# never depend on what happens to be installed on the host (AGENTS.md P5).
#
# The CJK font package set is itself a pin: the installed weight set is what
# decides whether a bold request resolves to Bold or to Black. Changing these
# packages changes typeset output (AGENTS.md §6.3).
# The cache mounts and the retry setting are not incidental. This layer pulls
# ~230 MB, which on a slow link takes long enough that a transient DNS or network
# failure part-way through is likely — and without them, such a failure discards
# everything already downloaded and the whole layer starts over.
#
#   - the two cache mounts keep apt's package lists and downloaded .debs outside
#     the image layer, so a retry resumes instead of restarting;
#   - docker-clean is removed because the stock Debian image configures apt to
#     delete downloaded .debs immediately, which would defeat the cache mount;
#   - Acquire::Retries lets apt itself ride out a brief resolver failure.
#
# Because the lists and archives live in cache mounts, they are not part of the
# published image and need no explicit `rm -rf`.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    set -eux; \
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    printf '%s\n' \
      'Acquire::Retries "10";' \
      'Acquire::http::Timeout "60";' \
      'Binary::apt::APT::Keep-Downloaded-Packages "true";' \
      > /etc/apt/apt.conf.d/99contex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        fontconfig \
        fonts-noto-core fonts-noto-cjk fonts-noto-cjk-extra \
        poppler-utils ghostscript imagemagick; \
    fc-cache -f

# Writable scratch locations, so the container can run as an arbitrary non-root
# UID (docker-compose.yml `user:`) without a writable $HOME. This is what keeps
# build artifacts owned by the host user rather than root.
ENV HOME=/tmp \
    XDG_CACHE_HOME=/tmp/.cache \
    TEXMFVAR=/tmp/texmf-var \
    TEXMFCONFIG=/tmp/texmf-config \
    TEXMFHOME=/tmp/texmf-home

# contex's own style files are mounted read-only at /work/style. The trailing
# "//" recurses; the trailing ":" preserves the default search path.
ENV TEXINPUTS=/work/style//:

COPY compile.sh /usr/local/bin/compile.sh
RUN chmod +x /usr/local/bin/compile.sh

WORKDIR /work/src
ENTRYPOINT ["/usr/local/bin/compile.sh"]
