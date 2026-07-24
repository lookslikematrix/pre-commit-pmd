# Download + sha256-verify + cache helpers.
# Exposes: cache_root, download_tool.
#
# Cache layout:
#   ${XBERG_HOOKS_CACHE:-$HOME/.cache/xberg-pre-commit-hooks}/<tool>/<version>/<arch>/
# Inside that dir: the resolved binary (or extracted tree). A `.verified` sentinel
# is written after sha256 verification so subsequent runs can skip re-verification.
# shellcheck shell=bash

cache_root() {
  printf '%s\n' "${XBERG_HOOKS_CACHE:-${HOME}/.cache/xberg-pre-commit-hooks}"
}

# Compute sha256 portably (Linux: sha256sum, macOS: shasum -a 256).
_sha256_of() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${path}" | awk '{print $1}'
  else
    printf 'no sha256 tool available (need sha256sum or shasum)\n' >&2
    return 1
  fi
}

# Look up an expected sha256 for an asset name in a checksums.txt file.
# checksums.txt format: `<sha256>  <asset_name>` (one per line, blank/# comments allowed).
_lookup_checksum() {
  local checksums_file="$1" asset_name="$2"
  awk -v want="${asset_name}" '
    /^[[:space:]]*$/ {next}
    /^[[:space:]]*#/ {next}
    {
      sum=$1; name=$2;
      if (name == want) { print sum }
    }
  ' "${checksums_file}"
}

# True if the actual sha matches any expected sha registered for the asset name.
_checksum_matches() {
  local checksums_file="$1" asset_name="$2" actual="$3"
  while IFS= read -r expected; do
    [[ -z "${expected}" ]] && continue
    if [[ "${expected}" == "${actual}" ]]; then
      return 0
    fi
  done < <(_lookup_checksum "${checksums_file}" "${asset_name}")
  return 1
}

# Print the first non-placeholder sha registered for the asset name, or empty.
_first_real_checksum() {
  local checksums_file="$1" asset_name="$2"
  local placeholder="0000000000000000000000000000000000000000000000000000000000000000"
  while IFS= read -r sum; do
    [[ -z "${sum}" ]] && continue
    [[ "${sum}" == "${placeholder}" ]] && continue
    printf '%s\n' "${sum}"
    return 0
  done < <(_lookup_checksum "${checksums_file}" "${asset_name}")
}

# download_tool <tool_name> <version> <url> <asset_name> <checksums_file>
# On success, prints the absolute path to the cached, verified asset on stdout.
# On failure, prints an error to stderr and returns non-zero.
download_tool() {
  local tool="$1" version="$2" url="$3" asset_name="$4" checksums_file="$5"
  local arch_dir
  arch_dir="$(asset_suffix)"

  local dest_dir="$(cache_root)/${tool}/${version}/${arch_dir}"
  local dest_path="${dest_dir}/${asset_name}"
  local sentinel="${dest_dir}/.verified"

  if [[ -f "${sentinel}" && -f "${dest_path}" ]]; then
    printf '%s\n' "${dest_path}"
    return 0
  fi

  mkdir -p "${dest_dir}"

  # Multiple per-platform assets may share the same logical asset_name
  # (e.g. palantir-java-format ships one binary per OS/arch but the run.sh
  # references a single name). Accept any sha registered against the name
  # rather than treating the file as a single-sha lookup.
  local first_expected
  first_expected="$(_first_real_checksum "${checksums_file}" "${asset_name}")"
  if [[ -z "${first_expected}" ]]; then
    if [[ -z "$(_lookup_checksum "${checksums_file}" "${asset_name}")" ]]; then
      printf 'no checksum entry for %s in %s\n' "${asset_name}" "${checksums_file}" >&2
    else
      printf 'refusing to download %s: every registered checksum is a placeholder. populate %s with the real sha256 from upstream releases.\n' \
        "${asset_name}" "${checksums_file}" >&2
    fi
    return 1
  fi

  # Download to a temp file inside dest_dir to keep verification atomic.
  local tmp
  tmp="$(mktemp "${dest_dir}/.download.XXXXXX")"

  if command -v curl >/dev/null 2>&1; then
    curl --fail --silent --show-error --location --output "${tmp}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet --output-document="${tmp}" "${url}"
  else
    rm -f "${tmp}"
    printf 'neither curl nor wget available\n' >&2
    return 1
  fi

  local actual
  actual="$(_sha256_of "${tmp}")"
  if ! _checksum_matches "${checksums_file}" "${asset_name}" "${actual}"; then
    rm -f "${tmp}"
    printf 'sha256 mismatch for %s: got %s, none of the registered checksums matched\n' "${asset_name}" "${actual}" >&2
    printf '  upstream likely rebuilt the release asset; refresh with:\n' >&2
    printf '    uv run python scripts/fetch_checksums.py --force --hook %s\n' "${tool}" >&2
    return 1
  fi

  # Set perms BEFORE the mv so the moved file is executable atomically.
  # Tarball/JAR/PHAR consumers don't need this but standalone binaries do;
  # setting it unconditionally is harmless. Errors are not suppressed so a
  # filesystem that rejects chmod surfaces a real diagnostic instead of a
  # silent "Permission denied" from a downstream exec.
  chmod 0755 "${tmp}"
  mv "${tmp}" "${dest_path}"
  : >"${sentinel}"
  printf '%s\n' "${dest_path}"
}

# download_tool_from_archive <tool_name> <version> <url> <asset_name> <checksums_file> <binary_in_archive>
# Downloads a .tar.gz or .zip archive, sha256-verifies the archive, extracts a named binary,
# caches the binary, and prints the absolute path to the extracted binary on stdout.
# On failure, prints an error to stderr and returns non-zero.
#
# The binary is cached at:
#   $(cache_root)/<tool_name>/<version>/<arch_suffix>/<binary_in_archive>
# A .verified sentinel prevents re-extraction on subsequent runs.
download_tool_from_archive() {
  local tool="$1" version="$2" url="$3" asset_name="$4" checksums_file="$5" binary_in_archive="$6"
  local arch_dir
  arch_dir="$(asset_suffix)"

  local dest_dir
  dest_dir="$(cache_root)/${tool}/${version}/${arch_dir}"
  local bin_path="${dest_dir}/${binary_in_archive}"
  local sentinel="${dest_dir}/.verified"

  if [[ -f "${sentinel}" && -f "${bin_path}" ]]; then
    printf '%s\n' "${bin_path}"
    return 0
  fi

  mkdir -p "${dest_dir}"

  # Same per-platform multi-sha tolerance as download_tool: each platform may
  # publish its own asset under the same logical name.
  local first_expected
  first_expected="$(_first_real_checksum "${checksums_file}" "${asset_name}")"
  if [[ -z "${first_expected}" ]]; then
    if [[ -z "$(_lookup_checksum "${checksums_file}" "${asset_name}")" ]]; then
      printf 'no checksum entry for %s in %s\n' "${asset_name}" "${checksums_file}" >&2
    else
      printf 'refusing to download %s: every registered checksum is a placeholder. populate %s with the real sha256 from upstream releases.\n' \
        "${asset_name}" "${checksums_file}" >&2
    fi
    return 1
  fi

  # Download archive to a temp file inside dest_dir to keep verification atomic.
  local tmp
  tmp="$(mktemp "${dest_dir}/.download.XXXXXX")"

  if command -v curl >/dev/null 2>&1; then
    curl --fail --silent --show-error --location --output "${tmp}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet --output-document="${tmp}" "${url}"
  else
    rm -f "${tmp}"
    printf 'neither curl nor wget available\n' >&2
    return 1
  fi

  local actual
  actual="$(_sha256_of "${tmp}")"
  if ! _checksum_matches "${checksums_file}" "${asset_name}" "${actual}"; then
    rm -f "${tmp}"
    printf 'sha256 mismatch for %s: got %s, none of the registered checksums matched\n' "${asset_name}" "${actual}" >&2
    printf '  upstream likely rebuilt the release asset; refresh with:\n' >&2
    printf '    uv run python scripts/fetch_checksums.py --force --hook %s\n' "${tool}" >&2
    return 1
  fi

  # Extract to a per-invocation staging dir so the bin_path is published via
  # atomic rename. Concurrent invocations of the same hook (e.g. when prek
  # splits files across parallel processes) used to race on the extracted
  # binary and surface as ETXTBSY ("Text file busy") when one wrapper tried
  # to exec a partially-written file. Staging + rename eliminates the race.
  local stage
  stage="$(mktemp -d "${dest_dir}/.stage.XXXXXX")"
  case "${asset_name}" in
  *.tar.gz | *.tgz)
    tar -xzf "${tmp}" -C "${stage}" "${binary_in_archive}"
    ;;
  *.zip)
    unzip -q -o "${tmp}" "${binary_in_archive}" -d "${stage}"
    ;;
  *)
    rm -rf "${stage}"
    rm -f "${tmp}"
    printf 'unsupported archive format for %s (expected .tar.gz/.tgz/.zip)\n' "${asset_name}" >&2
    return 1
    ;;
  esac

  rm -f "${tmp}"
  chmod 0755 "${stage}/${binary_in_archive}"
  # Atomic publish. If a concurrent process beat us to it, the rename still
  # succeeds (overwriting an identical, fully-written file) — bin_path keeps
  # the same inode contents either way.
  mv "${stage}/${binary_in_archive}" "${bin_path}"
  rm -rf "${stage}"
  : >"${sentinel}"
  printf '%s\n' "${bin_path}"
}

# extract_archive_atomic <archive_path> <extract_dir> <bin_path> <tar_flags...>
# Extract an archive into ${extract_dir} concurrency-safely:
#
#   1. tar into a per-invocation staging dir under ${extract_dir} (so the
#      eventual `mv` stays on the same filesystem and `rename(2)` is atomic).
#   2. atomically `mv` the relevant subtree into place. If another concurrent
#      caller beat us to it, the target already exists and we drop our staged
#      copy. The published binary therefore goes from "doesn't exist" → "fully
#      written" in a single rename, so `exec ${bin_path}` from a parallel
#      caller cannot observe a partially-written file (no ETXTBSY).
#
# bin_path is expected to live one directory under extract_dir (most upstream
# tarballs ship as `tool-vX/<binary>`); for archives that drop the binary
# directly at the top level, pass extract_dir == dirname(bin_path) and the
# helper still does the right thing.
extract_archive_atomic() {
  local archive_path="$1" extract_dir="$2" bin_path="$3"
  shift 3
  if [[ -x "${bin_path}" ]]; then
    return 0
  fi
  mkdir -p "${extract_dir}"
  local stage
  stage="$(mktemp -d "${extract_dir}/.stage.XXXXXX")"
  tar "$@" -f "${archive_path}" -C "${stage}"
  # Recompute bin_path within stage by swapping the extract_dir prefix. This
  # works whether the archive ships a subdir wrapper or drops the binary at
  # the top level.
  local rel="${bin_path#"${extract_dir}/"}"
  local staged_bin="${stage}/${rel}"
  if [[ ! -e "${staged_bin}" ]]; then
    rm -rf "${stage}"
    printf 'extract_archive_atomic: expected %s inside archive %s, not found after extraction\n' \
      "${rel}" "${archive_path}" >&2
    return 1
  fi
  chmod 0755 "${staged_bin}"
  # Compute the top-level entry inside stage that we need to promote into
  # extract_dir. For a nested layout (`shellcheck-vX/shellcheck`), this is
  # `shellcheck-vX`. For a flat layout (`kubeconform`), this is the binary
  # itself. Either way `rename(2)` is atomic when the target doesn't exist.
  local top="${rel%%/*}"
  if [[ ! -e "${extract_dir}/${top}" ]]; then
    mv "${stage}/${top}" "${extract_dir}/${top}" 2>/dev/null || true
  fi
  rm -rf "${stage}"
}
