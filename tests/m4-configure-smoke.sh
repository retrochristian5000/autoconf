#!/bin/sh
# Regression: generate and execute configure with both M4 selector spellings.
set -eu
src=$(CDPATH= cd -P -- "$(dirname -- "$0")/.." && pwd -P) || exit 1
tmp=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/autoconf-m4-probe.XXXXXXXX") || exit 1
trap 'rm -rf "$tmp"' 0
trap 'exit 1' 1 2 3 15
mkdir -p "$tmp/m4"
cp "$src/m4/m4.m4" "$tmp/m4/m4.m4"
for macro in AC_PROG_M4 AC_PROG_GNU_M4; do
    printf 'AC_INIT([whp-m4-probe],[1])\nm4_include([m4/m4.m4])\n%s\nAC_OUTPUT\n' \
        "$macro" > "$tmp/configure.ac"
    (
        cd "$tmp"
        autoconf -o configure
        # A configure script must parse before any runtime probe can run.
        /bin/sh -n ./configure
        M4=$(command -v m4) || exit 1
        export M4
        /bin/sh ./configure > "$tmp/configure.log" 2>&1 || {
            cat "$tmp/configure.log" >&2
            exit 1
        }
    )
    grep -F 'provides required M4 features... yes' "$tmp/configure.log" >/dev/null
    grep -F 'how M4 writes trace files...' "$tmp/configure.log" >/dev/null
done
printf '%s\n' 'PASS: configure-time M4 feature checks and legacy alias'
