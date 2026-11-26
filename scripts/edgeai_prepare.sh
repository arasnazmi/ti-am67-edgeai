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

# --- Load Utility Functions ---
UTILS_SCRIPT="${WORKDIR}/scripts/utils.sh"
if [ ! -f "${UTILS_SCRIPT}" ]; then
    log_error "Utility script not found: ${UTILS_SCRIPT}"
    exit 1
fi
source "${UTILS_SCRIPT}"

OUT_DIR="${WORKDIR}/out"
WORKAREA="${WORKDIR}/workarea"

SECONDS=0

log_info "Installing .deb packages from: ${OUT_DIR}"

deb_files=("${OUT_DIR}"/*.deb)
if [ ! -e "${deb_files[0]}" ]; then
    log_error "No .deb files found in: ${OUT_DIR}"
    exit 1
fi

log_info "Found ${#deb_files[@]} .deb file(s): ${deb_files[*]}"
dpkg -i "${deb_files[@]}"
log_success ".deb packages installed."

log_info "Installing Python wheel packages from: ${OUT_DIR}"

whl_files=("${OUT_DIR}"/*.whl)
if [ ! -e "${whl_files[0]}" ]; then
    log_warn "No .whl files found in: ${OUT_DIR}, skipping pip install."
else
    log_info "Found ${#whl_files[@]} .whl file(s): ${whl_files[*]}"
    pip3 install "${whl_files[@]}"
    log_success "Python wheels installed."
fi

log_info "Cloning edgeai-app-stack repository..."

extract_repo_info "edgeai-app-stack"

cd "${WORKAREA}"
clone_repo "$repo_url" "$repo_tag" "$repo_branch" "$repo_commit" edgeai-app-stack
log_success "edgeai-app-stack cloned."

# edgeai-dl-inferer installs its Python module to python3.12/site-packages, the
# Python of TI's Yocto image. Ubuntu's Python looks in dist-packages instead,
# even where it is 3.12. Install the module to python3/dist-packages, which
# every Python 3 on Ubuntu searches.
log_info "Patching the edgeai-dl-inferer Python module install path..."
DL_INFERER_CMAKE="${WORKAREA}/edgeai-app-stack/edgeai-dl-inferer/cmake/common.cmake"
sed -i 's#^\([[:space:]]*set(CMAKE_INSTALL_PYTHON_LIBDIR\) .*#\1 ${CMAKE_INSTALL_PREFIX}/lib/python3/dist-packages)#' \
    "${DL_INFERER_CMAKE}"
if ! grep -qF 'set(CMAKE_INSTALL_PYTHON_LIBDIR ${CMAKE_INSTALL_PREFIX}/lib/python3/dist-packages)' "${DL_INFERER_CMAKE}"; then
    log_error "Could not patch the Python module install path in: ${DL_INFERER_CMAKE}"
    exit 1
fi
log_success "edgeai-dl-inferer patched."

# The build files of edgeai-dl-inferer, apps_cpp (CMake) and edgeai-gst-plugins
# (the pkg-config file of edgeai-dl-inferer) look for the headers and the
# library of the dlr wheel under python3.10, the Python of Ubuntu 22.04. Point
# them to where pip installed the wheel for the Python of this image.
DLR_OLD_PATH="lib/python3.10/dist-packages/dlr"
DLR_NEW_PATH="lib/${PYTHON_VERSION}/dist-packages/dlr"
DLR_BUILD_FILES=(--include='*.cmake' --include='CMakeLists.txt' --include='*.pc')
if [ "${DLR_OLD_PATH}" != "${DLR_NEW_PATH}" ]; then
    log_info "Pointing the build files to the dlr wheel of ${PYTHON_VERSION}..."
    mapfile -t dlr_build_files < <(grep -rlF "${DLR_OLD_PATH}" "${WORKAREA}/edgeai-app-stack" "${DLR_BUILD_FILES[@]}")
    for build_file in "${dlr_build_files[@]}"; do
        sed -i "s#${DLR_OLD_PATH}#${DLR_NEW_PATH}#g" "${build_file}"
        log_info "  ${build_file#"${WORKAREA}/"}"
    done
    if grep -rqF "${DLR_OLD_PATH}" "${WORKAREA}/edgeai-app-stack" "${DLR_BUILD_FILES[@]}"; then
        log_error "Could not replace ${DLR_OLD_PATH} in the edgeai-app-stack build files."
        exit 1
    fi
    log_success "dlr path updated in ${#dlr_build_files[@]} build file(s)."
fi

duration=${SECONDS}
log_success "$(basename "$0"): Completed in $(( duration / 60 )) minutes and $(( duration % 60 )) seconds."
