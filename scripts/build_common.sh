#!/bin/bash
# build_common.sh — Parallelism and retry helpers for the build scripts.
# Usage: source "${WORKDIR}/scripts/build_common.sh"

if [ -n "${_BUILD_COMMON_SH_LOADED:-}" ]; then
    return 0
fi
_BUILD_COMMON_SH_LOADED=1

# Prints the default number of parallel compile jobs: one per CPU, but at most
# one per 2 GiB of available RAM. The biggest ONNX Runtime / TFLite translation
# units need about that much, and running out of memory kills the compiler.
default_nproc() {
    local cpus mem_kb by_mem
    cpus=$(nproc 2>/dev/null || echo 1)
    mem_kb=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo 2>/dev/null)
    by_mem=$(( ${mem_kb:-0} / (2 * 1024 * 1024) ))
    [ "${by_mem}" -lt 1 ] && by_mem=1
    [ "${by_mem}" -lt "${cpus}" ] && cpus=${by_mem}
    echo "${cpus}"
}

# Set NPROC=<n> in the environment to override.
NPROC="${NPROC:-$(default_nproc)}"

# retry <attempts> <command...>
# Re-runs a command until it succeeds, at most <attempts> times, waiting
# 5, 10, 15, ... seconds between attempts.
retry() {
    local _retry_max=$1
    shift
    local _retry_n=1
    until "$@"; do
        if [ "${_retry_n}" -ge "${_retry_max}" ]; then
            echo "[ERROR] Failed after ${_retry_max} attempts: $*" >&2
            return 1
        fi
        echo "[WARN]  Attempt ${_retry_n}/${_retry_max} failed: $*. Retrying in $(( 5 * _retry_n )) seconds..." >&2
        sleep $(( 5 * _retry_n ))
        _retry_n=$(( _retry_n + 1 ))
    done
}
