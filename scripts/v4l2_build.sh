#!/bin/bash
# Builds v4l2-utils using Meson and Ninja for aarch64 targets.

if [ ! -f /.dockerenv ]; then
    echo "ERROR: This script must be run inside the osrt-build Docker container." >&2
    exit 1
fi

if [ -z "${WORKDIR:-}" ]; then
    echo "ERROR: WORKDIR environment variable is not set." >&2
    exit 1
fi

source "${WORKDIR}/scripts/logging.sh"

V4L2_DIR="${WORKDIR}/workarea/v4l2-utils"
BUILD_DIR="${V4L2_DIR}/build"

source "${WORKDIR}/scripts/build_common.sh"

if [ ! -d "${V4L2_DIR}" ]; then
    log_error "v4l2-utils source directory not found: ${V4L2_DIR}"
    exit 1
fi

SECONDS=0

log_info "Building v4l2-utils with ${NPROC} parallel jobs..."
log_info "Source dir : ${V4L2_DIR}"
log_info "Build dir  : ${BUILD_DIR}"

cd "${V4L2_DIR}"

log_info "Running meson setup..."
rm -rf "${BUILD_DIR}"
meson setup "${BUILD_DIR}"

log_info "Compiling with Ninja (${NPROC} jobs)..."

# Ninja resumes where it stopped, so a retry only redoes the failed step.
if ! retry 3 ninja -C "${BUILD_DIR}" -j"${NPROC}"; then
    log_error "Ninja build failed."
    exit 1
fi

chmod -R a+w "${WORKDIR}/workarea"

duration=${SECONDS}
log_success "$(basename "$0"): Completed in $(( duration / 60 )) minutes and $(( duration % 60 )) seconds."
