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
source "${WORKDIR}/scripts/utils.sh"
source "${WORKDIR}/scripts/build_common.sh"

WORKAREA="${WORKDIR}/workarea"

# TI's v4l-utils patches, unchanged from meta-arago (scarthgap, commit
# dd1b7f9b85c0), applied in file name order. They are kept here because
# git.ti.com often fails from the CI runners.
PATCH_DIR="${WORKDIR}/patches/v4l2-utils"

SECONDS=0
current_dir=$(pwd)

log_info "Preparing v4l2-utils source tree..."

log_info "Resolving repository info for 'v4l2-utils'..."
extract_repo_info "v4l2-utils"

log_info "Cloning v4l2-utils into ${WORKAREA}..."
mkdir -p "${WORKAREA}"
cd "${WORKAREA}"
rm -rf "${WORKAREA}/v4l2-utils"
clone_repo "$repo_url" "$repo_tag" "$repo_branch" "$repo_commit" v4l2-utils
log_success "Clone complete."

log_info "Applying the patches in ${PATCH_DIR}..."
cd v4l2-utils
for patch_path in "${PATCH_DIR}"/*.patch; do
    patch_file=$(basename "${patch_path}")
    log_info "Applying patch: ${patch_file}"
    if patch -p1 < "${patch_path}"; then
        log_success "Patch applied: ${patch_file}"
    else
        log_error "Failed to apply patch: ${patch_file}"
        exit 1
    fi
done

log_info "Fixing permissions on workarea..."
chmod -R a+w "${WORKAREA}"

cd "${current_dir}"

duration=${SECONDS}
log_success "$(basename "$0"): Completed in $(( duration / 60 )) minutes and $(( duration % 60 )) seconds."
