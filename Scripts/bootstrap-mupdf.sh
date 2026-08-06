#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
MUPDF_ROOT="$PROJECT_ROOT/Vendor/mupdf"

if [[ ! -f "$MUPDF_ROOT/Makefile" ]]; then
    mkdir -p "$PROJECT_ROOT/Vendor"
    git clone --depth 1 --branch 1.28.2 --recurse-submodules \
        https://github.com/ArtifexSoftware/mupdf.git "$MUPDF_ROOT"
fi

if [[ ! -f "$MUPDF_ROOT/build/release-tofu/libmupdf.a" || \
      ! -f "$MUPDF_ROOT/build/release-tofu/libmupdf-third.a" ]]; then
    JOB_COUNT=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
    MACOSX_DEPLOYMENT_TARGET=14.0 make -C "$MUPDF_ROOT" -j"$JOB_COUNT" \
        build=release shared=no HAVE_GLUT=no \
        brotli=no mujs=no html=no xps=no svg=no extract=no tofu=yes libs
fi
