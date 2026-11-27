#!/bin/bash

if [ ! -f /.dockerenv ]; then
    echo "ERROR: This script must be run inside the osrt-build Docker container." >&2
    exit 1
fi

if [ -z "${WORKDIR:-}" ]; then
    echo "ERROR: WORKDIR environment variable is not set." >&2
    exit 1
fi

source "${WORKDIR}/scripts/logging.sh"

UTILS_SCRIPT="${WORKDIR}/scripts/utils.sh"
if [ ! -f "${UTILS_SCRIPT}" ]; then
    log_error "Utility script not found: ${UTILS_SCRIPT}"
    exit 1
fi
source "${UTILS_SCRIPT}"
source "${WORKDIR}/scripts/build_common.sh"

WORKAREA="${WORKDIR}/workarea"
GST_PLUGINS_DIR="${WORKAREA}/gstreamer/subprojects/gst-plugins-good"

SECONDS=0

log_info "Cloning GStreamer repository..."

extract_repo_info "gstreamer"

rm -rf "${WORKAREA}/gstreamer"

mkdir -p "${WORKAREA}"
cd "${WORKAREA}"
clone_repo "$repo_url" "$repo_tag" "$repo_branch" "$repo_commit" gstreamer
log_success "GStreamer cloned."

log_info "Applying patches to gst-plugins-good..."

if [ ! -d "${GST_PLUGINS_DIR}" ]; then
    log_error "gst-plugins-good directory not found: ${GST_PLUGINS_DIR}"
    exit 1
fi

cd "${GST_PLUGINS_DIR}"

# Each GStreamer version has its gst-plugins-good patches in
# patches/gstreamer/<version>, applied in file name order. 1.22.12 has TI's
# own, unchanged from meta-arago (scarthgap, commit dd1b7f9b85c0); they are
# kept here because git.ti.com often fails from the CI runners. TI publishes
# none for 1.24, so 1.24.13 has TI's rebased to it, and what the TI
# applications need on top.
LOCAL_PATCH_DIR="${WORKDIR}/patches/gstreamer/${repo_branch}"

if [ ! -d "${LOCAL_PATCH_DIR}" ]; then
    log_error "No gst-plugins-good patches for GStreamer ${repo_branch}: ${LOCAL_PATCH_DIR} not found"
    exit 1
fi

log_info "Using the patches in: ${LOCAL_PATCH_DIR}"
patch_paths=("${LOCAL_PATCH_DIR}"/*.patch)

total=${#patch_paths[@]}
index=0

for patch_path in "${patch_paths[@]}"; do
    index=$(( index + 1 ))

    log_info "[${index}/${total}] Applying: $(basename "${patch_path}")"
    if ! patch -p1 < "${patch_path}"; then
        log_error "Failed to apply patch: ${patch_path}"
        exit 1
    fi
done

duration=${SECONDS}
log_success "$(basename "$0"): Completed in $(( duration / 60 )) minutes and $(( duration % 60 )) seconds."
