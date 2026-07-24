# pmd

Static analysis for Java (and other languages) using
[PMD](https://github.com/pmd/pmd).

## Category

JVM JAR, distributed as a binary zip. The hook downloads the verified zip,
extracts the bundled launcher (`bin/pmd`) and supporting jars, and execs the
launcher directly.

## JDK requirement

JDK 17+ (detected via `JAVA_HOME`, `/usr/libexec/java_home -v 17`, SDKMAN,
or `java` on PATH). If none is available, the hook prints a skip warning and
exits 0. The hook exports the discovered `JAVA_HOME` so the launcher uses it.

## Default args

`check -R rulesets/java/quickstart.xml -f text` — quickstart ruleset, text
formatter. Override with your own ruleset via `args:`.

## Requirements

`unzip` must be on PATH (standard on Linux, macOS, and most CI images).
