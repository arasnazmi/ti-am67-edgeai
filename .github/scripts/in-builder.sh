#!/usr/bin/env bash
# Usage: in-builder.sh '<shell command>'
#
# Runs a command in the builder image the way `task box` does locally: the
# repository is mounted at /root, which is $WORKDIR inside the image.
# CMake projects compile through ccache, Meson finds ccache on its own, and the
# cache lives in .ccache/ so the workflow can keep it between runs.
set -euo pipefail

docker run --rm \
    --network host \
    -v "${GITHUB_WORKSPACE:-$PWD}:/root" \
    -w /root \
    -e SDK_VER \
    -e NPROC \
    -e CCACHE_DIR=/root/.ccache \
    -e CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-2G}" \
    -e CMAKE_C_COMPILER_LAUNCHER=ccache \
    -e CMAKE_CXX_COMPILER_LAUNCHER=ccache \
    "${BUILDER_IMAGE:-ti-am67-edgeai:ci}" \
    bash -euo pipefail -c "ccache -z >/dev/null; trap 'ccache -s || true' EXIT; $1"
