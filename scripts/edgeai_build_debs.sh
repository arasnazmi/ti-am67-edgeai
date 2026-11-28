#!/bin/bash

set -euo pipefail

source "${WORKDIR}/scripts/logging.sh"

if [ ! -f /.dockerenv ]; then
    log_error "This script must be run inside the osrt-build Docker container."
    exit 1
fi

if [ -z "${WORKDIR:-}" ]; then
    log_error "WORKDIR environment variable is not set."
    exit 1
fi

SCRIPT_DIR="${WORKDIR}/workarea/edgeai-app-stack"
OUT_DIR="${WORKDIR}/out"

PKG_VERSION="11.0.0"
PKG_ARCHITECTURE="arm64"
PKG_MAINTAINER="T3 Gemstone Project Development Team <support@t3gemstone.org>"
PKG_DESCRIPTION="T3 Gemstone Project - Edge AI Utilities and Modules"
source "${WORKDIR}/scripts/build_common.sh"

CMAKE_PROJECTS=(
    "edgeai-apps-utils"
    "edgeai-tiovx-kernels"
    "edgeai-tiovx-modules"
    "edgeai-dl-inferer"
)

# Debian revision of the packages that changed without a new upstream version.
# The packages not listed here are built as plain ${PKG_VERSION}.
declare -A PKG_REVISION=(
    # The Python module moved from python3.12/site-packages to
    # python3/dist-packages (see edgeai_prepare.sh).
    [edgeai-dl-inferer]=1
)

pkg_version() {
    local revision="${PKG_REVISION[$1]:-}"
    echo "${PKG_VERSION}${revision:+-${revision}}"
}

# The packages are built for one Ubuntu release. Their file names say which,
# like those of the other packages, so that the files built for different
# releases can sit side by side, e.g. in a GitHub release or an apt pool.
. /etc/os-release
OS_NAME="${ID}_${VERSION_ID//./_}"

deb_name() {
    echo "${1}_$(pkg_version "$1")_${OS_NAME}_${PKG_ARCHITECTURE}.deb"
}

write_control() {
    local deb_dir="$1"
    local package_name="$2"
    local installed_size="${3:-}"

    mkdir -p "${deb_dir}"

    {
        echo "Package: ${package_name}"
        echo "Version: $(pkg_version "${package_name}")"
        echo "Section: utils"
        echo "Priority: optional"
        echo "Architecture: ${PKG_ARCHITECTURE}"
        [ -n "${installed_size}" ] && echo "Installed-Size: ${installed_size}"
        echo "Maintainer: ${PKG_MAINTAINER}"
        echo "Description: ${PKG_DESCRIPTION} (${package_name})"
    } > "${deb_dir}/control"
}

build_deb() {
    local install_dir="$1"
    local deb_name="$2"
    local deb_path="${OUT_DIR}/${deb_name}"

    log_info "Building .deb package: ${deb_name}"
    dpkg-deb --build "${install_dir}" "${deb_path}"
    dpkg -i "${deb_path}"
    log_success "Package ready: ${deb_path}"
}

mkdir -p "${OUT_DIR}"

SECONDS=0

log_info "========================================"
log_info " DEB Package Builder"
log_info " Output directory: ${OUT_DIR}"
log_info "========================================"

for PROJECT in "${CMAKE_PROJECTS[@]}"; do
    PROJECT_PATH="${SCRIPT_DIR}/${PROJECT}"

    if [ ! -d "${PROJECT_PATH}" ]; then
        log_warn "Directory not found, skipping: ${PROJECT_PATH}"
        continue
    fi

    log_info "----------------------------------------"
    log_info " Project: ${PROJECT}"
    log_info "----------------------------------------"

    cd "${PROJECT_PATH}"

    log_info "[1/4] Preparing build directory..."

    if [ ! -d build ]; then
        mkdir build
        cd build
        log_info "[2/4] Running CMake configuration..."
        cmake -DTARGET_FS="" ..
    else
        cd build
    fi

    log_info "[3/4] Compiling with ${NPROC} jobs..."
    make -j${NPROC}

    log_info "[4/4] Installing into staging directory..."
    INSTALL_DIR="${PROJECT_PATH}/build/_install"
    rm -rf "${INSTALL_DIR}"
    make install DESTDIR="${INSTALL_DIR}"

    INSTALLED_SIZE=$(du -sk "${INSTALL_DIR}" | cut -f1)
    write_control "${INSTALL_DIR}/DEBIAN" "${PROJECT}" "${INSTALLED_SIZE}"
    log_info "DEBIAN/control written:"
    cat "${INSTALL_DIR}/DEBIAN/control"

    DEB_NAME=$(deb_name "${PROJECT}")
    build_deb "${INSTALL_DIR}" "${DEB_NAME}"
done

GST_PROJECT="edgeai-gst-plugins"
GST_PROJECT_PATH="${SCRIPT_DIR}/${GST_PROJECT}"
GST_BUILD_DIR="${GST_PROJECT_PATH}/build"
GST_DEB_DIR="${GST_PROJECT_PATH}/deb_package"

log_info "----------------------------------------"
log_info " Project: ${GST_PROJECT} (Meson)"
log_info "----------------------------------------"

if [ ! -d "${GST_PROJECT_PATH}" ]; then
    log_error "Directory not found: ${GST_PROJECT_PATH}"
    exit 1
fi

cd "${GST_PROJECT_PATH}"

log_info "[1/4] Cleaning previous build artifacts..."
rm -rf "${GST_BUILD_DIR}" "${GST_DEB_DIR}"

log_info "[2/4] Running Meson configuration..."

meson setup build --prefix=/usr/local -Dpkg_config_path=pkgconfig
log_info "[3/4] Compiling with Ninja..."
ninja -C build -j"${NPROC}"

log_info "[4/4] Installing into staging directory..."
mkdir -p "${GST_DEB_DIR}/DEBIAN"
meson install -C build --destdir="${GST_DEB_DIR}"

write_control "${GST_DEB_DIR}/DEBIAN" "${GST_PROJECT}"
GST_DEB_NAME=$(deb_name "${GST_PROJECT}")
build_deb "${GST_DEB_DIR}" "${GST_DEB_NAME}"

duration=${SECONDS}
echo ""
log_info "========================================"
log_info " All packages completed!"
log_info " Output: ${OUT_DIR}"
ls -lh "${OUT_DIR}"/*.deb 2>/dev/null || log_warn "No .deb files produced in output directory."
log_info "========================================"
log_success "$(basename "$0"): Completed in $(( duration / 60 )) minutes and $(( duration % 60 )) seconds."
