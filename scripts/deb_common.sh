#!/bin/bash
# deb_common.sh — Helpers for writing DEBIAN/control of the packages built
# with `dpkg-deb --build` from a staging directory.
# Usage: source "${WORKDIR}/scripts/deb_common.sh"

if [ -n "${_DEB_COMMON_SH_LOADED:-}" ]; then
    return 0
fi
_DEB_COMMON_SH_LOADED=1

# deb_installed_size <staging dir>
# Prints the Installed-Size of the staging directory in KiB, counted the way
# dpkg-gencontrol does: regular files and symlinks rounded up to a whole KiB,
# every other entry as 1 KiB. DEBIAN/ is not installed, so it is skipped.
deb_installed_size() {
    local root="$1"

    find "${root}" -mindepth 1 -path "${root}/DEBIAN" -prune -o \
        \( \( -type f -o -type l \) -printf '%s\n' \) -o -printf 'other\n' |
        awk '$1 == "other" { total += 1; next }
             { total += int(($1 + 1023) / 1024) }
             END { print total + 0 }'
}

# deb_shlibs_depends <staging dir>
# Prints the Depends value for the shared libraries that the ELF files in the
# staging directory link against, worked out by dpkg-shlibdeps from the
# packages installed in the build container.
# Libraries that the staging directory ships itself add no dependency, so they
# never resolve to another installed copy (for example the distribution's
# GStreamer next to ours).
deb_shlibs_depends() {
    local root="$1"
    local tmp out
    local -a elf_files lib_dirs

    # dpkg-shlibdeps finds the package root by its DEBIAN directory and only
    # then treats the libraries under it as part of the package. Without it,
    # it falls back to the installed copies of the same libraries.
    mkdir -p "${root}/DEBIAN"

    mapfile -t elf_files < <(find "${root}" -path "${root}/DEBIAN" -prune -o -type f -print0 |
        xargs -0 -r file -N -F '//' |
        sed -n 's#^\(.*\)// ELF .*\(executable\|shared object\).*#\1#p')
    if [ "${#elf_files[@]}" -eq 0 ]; then
        return 0
    fi

    mapfile -t lib_dirs < <(find "${root}" -path "${root}/DEBIAN" -prune -o \
        -type f -name '*.so*' -printf '-l%h\n' | sort -u)

    # dpkg-shlibdeps only runs inside a source tree, so give it a minimal one.
    tmp=$(mktemp -d)
    mkdir "${tmp}/debian"
    printf 'Source: shlibdeps\n\nPackage: shlibdeps\nArchitecture: any\n' > "${tmp}/debian/control"

    # --ignore-missing-info: the libraries shipped in the staging directory
    # have no shlibs information, which is expected.
    if ! out=$(cd "${tmp}" && dpkg-shlibdeps -O --ignore-missing-info --warnings=0 \
            "${lib_dirs[@]}" "${elf_files[@]}"); then
        rm -rf "${tmp}"
        return 1
    fi
    rm -rf "${tmp}"

    sed -n 's/^shlibs:Depends=//p' <<< "${out}"
}
