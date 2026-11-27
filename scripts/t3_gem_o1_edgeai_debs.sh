#!/bin/bash

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
source "${WORKDIR}/scripts/deb_common.sh"

WORKAREA="${WORKDIR}/workarea"
OUT_DIR="${WORKDIR}/out"
APP_STACK_DIR="${WORKAREA}/edgeai-app-stack"
MODEL_ZOO_URL="https://packages.t3gemstone.org/sdk/models/model_zoo.tar.xz"
MODEL_ZOO_ARCHIVE="${WORKAREA}/model_zoo.tar.xz"

PKG_VERSION="11.0-2"
PKG_ARCHITECTURE="arm64"
PKG_MAINTAINER="T3 Gemstone Project Development Team <support@t3gemstone.org>"
# 11.0-1 follows the published 11.0 of this package. 11.0-2 brings the
# edgeai-gst-apps fix that keeps the first IDR frame of .mkv outputs.
# edgeai-dl-inferer 11.0.0-1 is the first one whose Python module the system
# Python finds. The python3-* and gir1.2-* packages are what apps_python needs.
PKG_DEPENDS="t3-edgeai-firmware (>= 11.0.0), arm-tidl-j722s, edgeai-apps-utils, \
edgeai-dl-inferer (>= 11.0.0-1), edgeai-tiovx-kernels, edgeai-tiovx-modules, t3-gstreamer, \
edgeai-gst-plugins, t3-libtensorflow-lite-dev, libti-vision-apps-j722s, t3-onnxruntime, \
ti-rpmsg-char, t3-v4l2-utils, libyaml-cpp-dev, libopencv-dev, libncurses-dev, python3-pip, \
python3-yaml, python3-opencv, python3-gi, gir1.2-gstreamer-1.0, gir1.2-gst-plugins-base-1.0, \
libegl1, libgles2, libgbm1, libgudev-1.0-0"
# t3-edgeai-dev is this package under another name and ships the same files.
# Take its place, so that apt removes it instead of failing on the shared files.
PKG_REPLACES="t3-edgeai-dev (<= 11.0-1)"

. /etc/os-release
OS_NAME="${ID}_${VERSION_ID//./_}"

DST_DIR="${WORKAREA}/t3-gem-o1-edgeai-${OS_NAME}_aarch64"
DEB_NAME="t3-gem-o1-edgeai-${OS_NAME}_aarch64.deb"
APPS_CPP_DIR="${APP_STACK_DIR}/edgeai-gst-apps/apps_cpp"
APPS_CPP_BUILD="${WORKAREA}/edgeai-apps-cpp-${OS_NAME}_aarch64"

if [ ! -d "${APP_STACK_DIR}" ]; then
    log_error "edgeai-app-stack directory not found: ${APP_STACK_DIR}"
    log_error "Make sure install_and_clone.sh has been run first."
    exit 1
fi

if [ ! -d "${OUT_DIR}" ] || [ -z "$(ls "${OUT_DIR}"/*.whl 2>/dev/null)" ]; then
    log_error "No .whl files found in: ${OUT_DIR}"
    log_error "Make sure all package build scripts have been run first."
    exit 1
fi

SECONDS=0

log_info "Assembling t3-gem-o1-edgeai package..."
log_info "App stack  : ${APP_STACK_DIR}"
log_info "Staging dir: ${DST_DIR}"
log_info "Output dir : ${OUT_DIR}"

# edgeai-app-stack ships prebuilt app_edgeai and app_config_checker binaries
# that were built for a newer distribution (GLIBC 2.38, OpenCV 4.9) and do not
# start on Ubuntu 22.04. Build them against the libraries in this image. The
# build goes to its own directory so that the app stack checkout stays clean.
#
# apps_cpp takes the GStreamer headers from /usr/include and leaves the
# libraries to the default linker path, where this image has the distribution's
# GStreamer 1.20. Put the GStreamer that pkg-config finds (t3-gstreamer 1.22 in
# /usr/local) first: -I is searched before -isystem, and the -L of LDFLAGS
# before the default directories. Linking against 1.20 fails, because our
# libgstbase needs symbols that only libgstreamer 1.22 has.
GST_MODULES="gstreamer-1.0 gstreamer-app-1.0"
if ! GST_CFLAGS=$(pkg-config --cflags-only-I ${GST_MODULES}) ||
   ! GST_LDFLAGS=$(pkg-config --libs-only-L ${GST_MODULES}); then
    log_error "pkg-config cannot find: ${GST_MODULES}"
    exit 1
fi
log_info "Building the C++ demo applications against GStreamer $(pkg-config --modversion gstreamer-1.0) with ${NPROC} jobs..."
rm -rf "${APPS_CPP_BUILD}"
if ! CXXFLAGS="${GST_CFLAGS} ${CXXFLAGS:-}" LDFLAGS="${GST_LDFLAGS} ${LDFLAGS:-}" \
        cmake -S "${APPS_CPP_DIR}" -B "${APPS_CPP_BUILD}/build" -DCMAKE_OUTPUT_DIR="${APPS_CPP_BUILD}" ||
   ! cmake --build "${APPS_CPP_BUILD}/build" -j "${NPROC}"; then
    log_error "Failed to build the C++ demo applications in: ${APPS_CPP_DIR}"
    exit 1
fi
log_success "C++ demo applications built."

log_info "Preparing staging directory structure..."
rm -rf "${DST_DIR}"
mkdir -p \
    "${DST_DIR}/DEBIAN" \
    "${DST_DIR}/opt/whl_packages"

log_info "Downloading model_zoo archive..."
rm -f "${MODEL_ZOO_ARCHIVE}"
wget --show-progress "${MODEL_ZOO_URL}" -P "${WORKAREA}/"
log_success "model_zoo downloaded."

log_info "Copying edgeai-app-stack assets..."
cp -r "${APP_STACK_DIR}/edgeai-gst-apps"   "${DST_DIR}/opt/"
cp -r "${APP_STACK_DIR}/edgeai-test-data"  "${DST_DIR}/opt/"
cp -r "${APP_STACK_DIR}/imaging"           "${DST_DIR}/opt/"
cp -r "${APP_STACK_DIR}/vision_apps"       "${DST_DIR}/opt/"
cp    "${APP_STACK_DIR}/vx_app_arm_remote_log.out" "${DST_DIR}/opt/"
# Most of the configs in edgeai-gst-apps/configs write their output there, and
# the apps do not create it.
mkdir -p "${DST_DIR}/opt/edgeai-test-data/output"
log_success "App stack assets copied."

log_info "Replacing the prebuilt C++ demo applications..."
if ! install -m 755 "${APPS_CPP_BUILD}/bin/Release/app_edgeai" \
        "${APPS_CPP_BUILD}/bin/Release/app_config_checker" \
        "${DST_DIR}/opt/edgeai-gst-apps/apps_cpp/bin/Release/"; then
    log_error "Failed to copy the C++ demo applications from: ${APPS_CPP_BUILD}/bin/Release"
    exit 1
fi
log_success "C++ demo applications replaced."

log_info "Extracting model_zoo archive..."
tar -xJf "${MODEL_ZOO_ARCHIVE}" -C "${DST_DIR}/opt/"
log_success "model_zoo extracted."

log_info "Copying Python wheels..."
cp "${OUT_DIR}"/*.whl "${DST_DIR}/opt/whl_packages/"

chmod -x "${DST_DIR}/opt/whl_packages/"*.whl
log_success "Python wheels copied."

# The TI GStreamer plugins (libgstti.so) link against libdlr.so, which the dlr
# wheel installs under its own module directory. Make it reachable through the
# linker search path, so that the plugins load without LD_LIBRARY_PATH, e.g.
# under sudo. postinst installs the wheel; the ldconfig trigger below then
# adds the library to the cache.
log_info "Adding /usr/lib/libdlr.so symlink..."
mkdir -p "${DST_DIR}/usr/lib"
ln -s ../local/lib/python3.10/dist-packages/dlr/libdlr.so "${DST_DIR}/usr/lib/libdlr.so"

# The published 11.0 and the documentation use /opt/t3-edgeai-env.
log_info "Writing t3-edgeai-env script..."
cat > "${DST_DIR}/opt/t3-edgeai-env" <<'EOF'
#!/bin/bash
export CPLUS_INCLUDE_PATH=/usr/local/include/gstreamer-1.0:${CPLUS_INCLUDE_PATH:-}
export LIBRARY_PATH=/usr/local/lib/python3.10/dist-packages/dlr:${LIBRARY_PATH:-}
export LD_LIBRARY_PATH=/usr/local/lib/python3.10/dist-packages/dlr:${LD_LIBRARY_PATH:-}
export GST_PLUGIN_PATH=/usr/local/lib/aarch64-linux-gnu/gstreamer-1.0
export EDGEAI_GST_APPS_PATH=/opt/edgeai-gst-apps
export OOB_DEMO_ASSETS_PATH=/opt/oob-demo-assets
export MODEL_ZOO_PATH=/opt/model_zoo
export EDGEAI_DATA_PATH=/opt/edgeai-test-data
export EDGEAI_SDK_VERSION=11_00_00
export EDGEAI_VERSION=11.0
export SOC=j722s
export DEVICE_NAME=AM67A
export PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h(edge-ai)\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
echo -e "\033[1;32m[INFO] T3 EdgeAI environment successfully loaded!\033[0m"
echo -e "\033[1;34mSOC: ${SOC} | DEVICE: ${DEVICE_NAME} | SDK: ${EDGEAI_SDK_VERSION}\033[0m"
EOF
chmod +x "${DST_DIR}/opt/t3-edgeai-env"
log_success "t3-edgeai-env written."

log_info "Writing DEBIAN/control..."
cat > "${DST_DIR}/DEBIAN/control" <<EOF
Package: t3-gem-o1-edgeai
Version: ${PKG_VERSION}
Section: misc
Priority: optional
Architecture: ${PKG_ARCHITECTURE}
Installed-Size: $(deb_installed_size "${DST_DIR}")
Maintainer: ${PKG_MAINTAINER}
Depends: ${PKG_DEPENDS}
Conflicts: ${PKG_REPLACES}
Replaces: ${PKG_REPLACES}
Description: T3 EdgeAI development package with necessary libraries, header files and tools
 for T3 EdgeAI application development.
EOF
cat "${DST_DIR}/DEBIAN/control"

log_info "Writing DEBIAN/postinst..."
cat > "${DST_DIR}/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e
# 11.0 installed opencv-python from PyPI. It needs numpy 2 and would hide the
# distribution's python3-opencv, which this version uses instead.
if [ "$1" = configure ] && [ "${2:-}" = 11.0 ]; then
    pip3 uninstall -y opencv-python || true
fi
# numpy is kept below 2: onnxruntime-tidl 1.15, tflite-runtime 2.12 and the
# distribution's python3-opencv are all built against the numpy 1.x ABI.
pip3 install "numpy<2" /opt/whl_packages/*.whl
exit 0
EOF
chmod 755 "${DST_DIR}/DEBIAN/postinst"

# Add /usr/lib/libdlr.so to the dynamic linker cache once postinst has
# installed the library it points to.
cat > "${DST_DIR}/DEBIAN/triggers" <<'EOF'
activate-noawait ldconfig
EOF
log_success "DEBIAN files written."

mkdir -p "${OUT_DIR}"
log_info "Building .deb package: ${DEB_NAME}"
# The model_zoo archive stores its files as uid/gid 1000 and tar keeps that
# when it runs as root; everything in the package belongs to root.
dpkg-deb --root-owner-group --build "${DST_DIR}" "${OUT_DIR}/${DEB_NAME}"
log_success "Package ready: ${OUT_DIR}/${DEB_NAME}"

chmod -R a+w "${WORKAREA}"

duration=${SECONDS}
log_success "$(basename "$0"): Completed in $(( duration / 60 )) minutes and $(( duration % 60 )) seconds."
