#!/usr/bin/env bash
# pmd — Java source analyser (category: JVM JAR, distributed as a zip).
# Downloads the upstream pmd-dist zip, sha256-verifies it, extracts the
# distribution into the cache, locates a JDK 17+, and execs the bundled
# `bin/pmd` launcher script (which sets the classpath correctly across all jars
# included in the distribution).
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOOK_DIR}/../.." && pwd)"

# shellcheck source=../../lib/platform.sh
source "${REPO_ROOT}/lib/platform.sh"
# shellcheck source=../../lib/download.sh
source "${REPO_ROOT}/lib/download.sh"
# shellcheck source=../../lib/jvm.sh
source "${REPO_ROOT}/lib/jvm.sh"

VERSION="$(grep -v '^#' "${HOOK_DIR}/version.txt" | tr -d '[:space:]')"
CHECKSUMS="${HOOK_DIR}/checksums.txt"

asset_name="pmd-dist-${VERSION}-bin.zip"
url="https://github.com/pmd/pmd/releases/download/pmd_releases%2F${VERSION}/${asset_name}"

java_bin="$(locate_java)"

archive_path="$(download_tool pmd "${VERSION}" "${url}" "${asset_name}" "${CHECKSUMS}")"
extract_dir="$(dirname "${archive_path}")/extracted"
pmd_launcher="${extract_dir}/pmd-bin-${VERSION}/bin/pmd"

if [[ ! -x "${pmd_launcher}" ]]; then
  if ! command -v unzip >/dev/null 2>&1; then
    printf 'pmd: `unzip` not available; install it to extract the pmd distribution.\n' >&2
    exit 1
  fi
  # Extract to a temporary directory first, then move atomically.
  # This prevents concurrent extraction processes from conflicting.
  temp_extract_dir="${extract_dir}.$$-${RANDOM}"
  mkdir -p "${temp_extract_dir}"
  unzip -q -d "${temp_extract_dir}" "${archive_path}"
  chmod +x "${temp_extract_dir}/pmd-bin-${VERSION}/bin/pmd"
  # Atomic rename (only one process will succeed).
  mkdir -p "$(dirname "${extract_dir}")"
  mv -f "${temp_extract_dir}" "${extract_dir}" || rm -rf "${temp_extract_dir}" 2>/dev/null || true
fi

# Make the launcher pick up our verified JDK.
export JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "${java_bin}")")}"

exec "${pmd_launcher}" "$@"
