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

PATCH_BASE_URL="https://git.ti.com/cgit/arago-project/meta-arago/plain/meta-arago-extras/recipes-multimedia/gstreamer/gstreamer1.0-plugins-good"
PATCH_BRANCH="scarthgap"

PATCH_FILES=(
    "0001-Adding-support-for-raw10-raw12-and-raw16-bayer-formats.patch"
    "0001-v4l2jpegenc-Add-support-for-cropping-in-JPEG-Encoder.patch"
    "0002-Adding-support-for-bayer-formats-with-IR-component.patch"
    "0003-v4l2-Changes-for-DMA-Buf-import-j721s2.patch"
    "0004-v4l2-Give-preference-to-contiguous-format-if-support.patch"
    "0005-HACK-gstv4l2object-Increase-min-buffers-for-CSI-capt.patch"
)

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

# TI publishes its gst-plugins-good patches for GStreamer 1.22 (meta-arago
# scarthgap, downloaded below) and 1.28, but not for 1.24. A GStreamer version
# with a directory under patches/gstreamer gets the patches in it instead:
# TI's, rebased to that version, and what the TI applications need on top.
LOCAL_PATCH_DIR="${WORKDIR}/patches/gstreamer/${repo_branch}"
patch_paths=()

if [ -d "${LOCAL_PATCH_DIR}" ]; then
    log_info "Using the patches in: ${LOCAL_PATCH_DIR}"
    patch_paths=("${LOCAL_PATCH_DIR}"/*.patch)
else
    total=${#PATCH_FILES[@]}
    index=0

    for patch_file in "${PATCH_FILES[@]}"; do
        index=$(( index + 1 ))
        patch_url="${PATCH_BASE_URL}/${patch_file}?h=${PATCH_BRANCH}"

        log_info "[${index}/${total}] Downloading: ${patch_file}"

        if ! retry 5 wget --quiet --show-progress -O "${patch_file}" "${patch_url}"; then
            log_error "Failed to download patch: ${patch_url}"
            exit 1
        fi

        patch_paths+=("${GST_PLUGINS_DIR}/${patch_file}")
    done
fi

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
