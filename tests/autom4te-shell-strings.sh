#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Verify shell-safe M4 execution and literal config.status substitution.
# Usage: script AUTOM4TE M4 AUTOCONF. No package installation is performed.
set -eu

if [ "$#" -ne 3 ]; then
    printf '%s\n' 'usage: autom4te-shell-strings.sh AUTOM4TE M4 AUTOCONF' >&2
    exit 2
fi
autom4te=$1
m4=$2
autoconf=$3
for executable in "$autom4te" "$m4" "$autoconf"; do
    [ -f "$executable" ] && [ -x "$executable" ] || {
        printf 'error: required source bootstrap executable is missing: %s\n' \
            "$executable" >&2
        exit 1
    }
done

fixture=$(mktemp -d "${TMPDIR:-/tmp}/autoconf-string-probe.XXXXXXXX") || exit 1
trap 'rm -rf "$fixture"' 0
trap 'exit 129' 1
trap 'exit 130' 2
trap 'exit 131' 3
trap 'exit 143' 15

# A quoted executable path must survive all autom4te M4 invocations,
# including --help, builtin introspection, and macro expansion.
m4_dir="$fixture/m4's tools with spaces"
mkdir -p "$m4_dir" "$fixture/project"
ln -s "$m4" "$m4_dir/m4"
# M4sugar starts with output diverted; enable diversion 0 explicitly so
# the test checks the expanded contents rather than an empty output file.
printf '%s\n' \
    'm4_divert_push([0])' \
    'm4_define([WHP_AUTOM4TE_STRING], [literal\c-string])' \
    'WHP_AUTOM4TE_STRING' \
    'm4_divert_pop([0])' > "$fixture/m4-input.m4"
M4="$m4_dir/m4" "$autom4te" \
    --no-cache --language=M4sugar --output="$fixture/m4-output" \
    "$fixture/m4-input.m4"
grep -Fx 'literal\c-string' "$fixture/m4-output" >/dev/null || {
    printf '%s\n' 'error: autom4te M4 output lost a literal backslash' >&2
    exit 1
}

# Autoconf-generated config.status must preserve the literal user value.
cat > "$fixture/project/configure.ac" <<'EOF'
AC_INIT([whp-shell-strings], [1])
WHP_LITERAL='left\c-right -n'
AC_SUBST([WHP_LITERAL])
AC_CONFIG_FILES([value.txt])
AC_OUTPUT
EOF
printf '%s\n' 'value=@WHP_LITERAL@' > "$fixture/project/value.txt.in"
(
    cd "$fixture/project"
    M4="$m4_dir/m4" "$autoconf"
    /bin/sh ./configure > configure.log 2>&1 || {
        cat configure.log >&2
        exit 1
    }
    grep -Fx 'value=left\c-right -n' value.txt >/dev/null || {
        printf '%s\n' 'error: config.status changed a literal backslash' >&2
        exit 1
    }
)
printf '%s\n' 'PASS: autom4te M4 shell quoting and config.status strings'
