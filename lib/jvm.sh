# JDK discovery helper. Exposes: locate_java.
# Detection order:
#   1. JAVA_HOME (if it points at a JDK 17+)
#   2. /usr/libexec/java_home -v 17 (macOS)
#   3. SDKMAN init: ~/.sdkman/bin/sdkman-init.sh + sdk current java
#   4. `java` on PATH
# If none yields JDK 17+, prints a warning and exits 0 (warn-and-skip pattern).
# shellcheck shell=bash

_java_major_version() {
  local java_bin="$1"
  # `java -version` prints to stderr in the form: openjdk version "17.0.10" ...
  local raw
  raw="$("${java_bin}" -version 2>&1 | head -n 1 || true)"
  # Extract the version literal between the first pair of double quotes.
  local ver
  ver="$(printf '%s\n' "${raw}" | sed -n 's/.*"\([0-9][0-9.]*\).*"/\1/p')"
  if [[ -z "${ver}" ]]; then
    printf '0\n'
    return
  fi
  # Pre-Java-9 used "1.8.x" — the major is the second segment. Java 9+ uses the first.
  local first second
  first="${ver%%.*}"
  second="${ver#*.}"
  second="${second%%.*}"
  if [[ "${first}" == "1" ]]; then
    printf '%s\n' "${second}"
  else
    printf '%s\n' "${first}"
  fi
}

# Try a candidate java binary, succeed (printing the path) only if it is JDK 17+.
_try_java() {
  local java_bin="$1"
  if [[ ! -x "${java_bin}" ]]; then
    return 1
  fi
  local major
  major="$(_java_major_version "${java_bin}")"
  if [[ "${major}" =~ ^[0-9]+$ ]] && ((major >= 17)); then
    printf '%s\n' "${java_bin}"
    return 0
  fi
  return 1
}

# locate_java: print path to a JDK 17+ java binary, or print a warning + exit 0.
# Hooks call this near the top of run.sh and abort gracefully on miss.
locate_java() {
  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
    if _try_java "${JAVA_HOME}/bin/java"; then return 0; fi
  fi

  if [[ "$(uname -s)" == "Darwin" && -x /usr/libexec/java_home ]]; then
    local mac_home
    if mac_home="$(/usr/libexec/java_home -v 17 2>/dev/null)"; then
      if _try_java "${mac_home}/bin/java"; then return 0; fi
    fi
  fi

  if [[ -f "${HOME}/.sdkman/bin/sdkman-init.sh" ]]; then
    # shellcheck source=/dev/null
    source "${HOME}/.sdkman/bin/sdkman-init.sh" >/dev/null 2>&1 || true
    if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
      if _try_java "${JAVA_HOME}/bin/java"; then return 0; fi
    fi
  fi

  if command -v java >/dev/null 2>&1; then
    if _try_java "$(command -v java)"; then return 0; fi
  fi

  printf 'xberg-pre-commit-hooks: skipping JVM hook — no JDK 17+ found.\n' >&2
  printf '  set JAVA_HOME, install JDK 17+ via SDKMAN/Homebrew/apt, or run `sdk install java 17-tem`.\n' >&2
  exit 0
}

# jvm_quiet_flags: print extra `java` CLI flags that silence noisy "WARNING: A
# terminally deprecated method in sun.misc.Unsafe has been called" output from
# JDK 23+ runtimes. The flag itself (`--sun-misc-unsafe-memory-access=allow`)
# only exists on JDK 23+; calling older JDKs with it aborts with
# "Unrecognized option". So we gate on the detected major version.
#
# Usage:
#   read -ra quiet_flags < <(jvm_quiet_flags "${java_bin}")
#   "${java_bin}" "${quiet_flags[@]}" -jar "${jar_path}" "$@"
jvm_quiet_flags() {
  local java_bin="${1:-java}"
  local major
  major="$(_java_major_version "${java_bin}")"
  if [[ "${major}" =~ ^[0-9]+$ ]] && ((major >= 23)); then
    printf '%s\n' '--sun-misc-unsafe-memory-access=allow'
  fi
}
