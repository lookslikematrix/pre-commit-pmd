# Platform detection helpers. Source this file from a hook's run.sh.
# Exposes: detect_os, detect_arch, asset_suffix.
# shellcheck shell=bash

detect_os() {
  # Outputs one of: linux, macos, windows.
  local uname_s
  uname_s="$(uname -s)"
  case "${uname_s}" in
  Linux*) printf 'linux\n' ;;
  Darwin*) printf 'macos\n' ;;
  MINGW* | MSYS* | CYGWIN*) printf 'windows\n' ;;
  *)
    printf 'unsupported os: %s\n' "${uname_s}" >&2
    return 1
    ;;
  esac
}

detect_arch() {
  # Outputs one of: x86_64, aarch64.
  local uname_m
  uname_m="$(uname -m)"
  case "${uname_m}" in
  x86_64 | amd64) printf 'x86_64\n' ;;
  aarch64 | arm64) printf 'aarch64\n' ;;
  *)
    printf 'unsupported arch: %s\n' "${uname_m}" >&2
    return 1
    ;;
  esac
}

# Map (os, arch) to a conventional asset suffix. Hooks override per-tool when
# upstream uses a non-standard naming scheme.
asset_suffix() {
  local os arch
  os="$(detect_os)"
  arch="$(detect_arch)"
  printf '%s_%s\n' "${os}" "${arch}"
}
