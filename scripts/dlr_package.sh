#!/bin/bash
# Builds the DLR Python wheel package and copies it to the output directory.

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

PYTHON_DIR="${WORKDIR}/workarea/neo-ai-dlr/python"
DIST_DIR="${PYTHON_DIR}/dist"
OUT_DIR="${WORKDIR}/out"

if [ ! -d "${PYTHON_DIR}" ]; then
    log_error "Python source directory not found: ${PYTHON_DIR}"
    exit 1
fi

if [ ! -f "${PYTHON_DIR}/setup.py" ]; then
    log_error "setup.py not found in: ${PYTHON_DIR}"
    exit 1
fi

if [ ! -d "${OUT_DIR}" ]; then
    log_warn "Output directory not found, creating: ${OUT_DIR}"
    mkdir -p "${OUT_DIR}"
fi

SECONDS=0

log_info "Building DLR Python wheel package..."
log_info "Python dir : ${PYTHON_DIR}"
log_info "Output dir : ${OUT_DIR}"

cd "${PYTHON_DIR}"
# The wheel carries libdlr.so, built for this image's architecture and C
# library. Tag it with the Python and platform it was built for, as with the
# other wheels, instead of py3-none-any, so that the wheels built for different
# Ubuntu releases neither have the same name nor install on the wrong one.
python_tag=$(python3 -c 'import sys; print("cp%d%d" % sys.version_info[:2])')
python3 setup.py bdist_wheel --python-tag "${python_tag}" --plat-name linux_aarch64

log_info "Searching for built wheel in: ${DIST_DIR}"
whl_path=$(find "${DIST_DIR}" -name "dlr-*.whl" | head -n 1)

if [ -z "${whl_path}" ]; then
    log_error "DLR wheel package not found in ${DIST_DIR}."
    exit 1
fi

log_info "Found wheel: ${whl_path}"

cp "${whl_path}" "${OUT_DIR}/"
log_success "Wheel copied to: ${OUT_DIR}/$(basename "${whl_path}")"

chmod -R a+w "${WORKDIR}/workarea"

duration=${SECONDS}
log_success "$(basename "$0"): Completed in $(( duration / 60 )) minutes and $(( duration % 60 )) seconds."
