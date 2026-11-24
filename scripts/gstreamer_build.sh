#! /bin/bash
# This script should be run inside the CONTAINER

if [ ! -f /.dockerenv ]; then
    echo "This script should be run inside the osrt-build Docker container"
    exit 1
fi

if [ -z "${WORKDIR:-}" ]; then
    echo "ERROR: WORKDIR environment variable is not set." >&2
    exit 1
fi

source "${WORKDIR}/scripts/logging.sh"
source "${WORKDIR}/scripts/build_common.sh"

set -e

current_dir=$(pwd)

cd $WORKDIR/workarea/gstreamer

SECONDS=0

rm -rf builddir
meson setup builddir \
  --prefix=/usr/local \
  --wrap-mode=nofallback \
  -Dexamples=disabled \
  -Dtests=disabled

log_info "Compiling GStreamer with ${NPROC} jobs..."

# Meson resumes where it stopped, so a retry only redoes the failed step.
retry 3 meson compile -C builddir -j "${NPROC}"

# chmod
chmod -R a+w $WORKDIR/workarea

cd $current_dir

duration=$SECONDS
log_success "$(basename "$0"): Completed in $(( duration / 60 )) minutes and $(( duration % 60 )) seconds."
