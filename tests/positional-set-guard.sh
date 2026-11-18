#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# The obsolete AC_LINK_FILES macro is still expanded by autoupdate.
# Ensure a leading '-' in a filename does not become a shell 'set' option.
set -eu

if [ "$#" -ne 2 ]; then
    printf '%s\n' 'usage: positional-set-guard.sh AUTOUPDATE AUTOCONF' >&2
    exit 2
fi
update=$1
conf=$2
for tool in "$update" "$conf"; do
    [ -f "$tool" ] && [ -x "$tool" ] || {
        printf 'error: executable unavailable: %s\n' "$tool" >&2
        exit 1
    }
done

fixture=$(mktemp -d "${TMPDIR:-/tmp}/autoconf-set.XXXXXXXX") || exit 1
trap 'rm -rf "$fixture"' 0
trap 'exit 129' 1
trap 'exit 130' 2
trap 'exit 131' 3
trap 'exit 143' 15
mkdir -p "$fixture/project"

# With the original implementation, 'set $ac_dests' interprets
# '-dest' as -d and fails under dash/bash; '-source' is similarly unsafe.
cat > "$fixture/project/configure.ac" <<'EOF'
AC_INIT([shell-set-smoke], [1])
AC_LINK_FILES([-source sourceB], [-dest destB])
AC_OUTPUT
EOF
(
    cd "$fixture/project" || exit 1
    "$update" --force > update.log 2>&1 || {
        cat update.log >&2
        exit 1
    }
    "$conf" > autoconf.log 2>&1 || {
        cat autoconf.log >&2
        exit 1
    }
    # Do not instantiate the links: this test isolates positional-parameter
    # handling rather than ln(1)'s separate leading-dash path semantics.
    /bin/sh ./configure --no-create > configure.log 2>&1 || {
        cat configure.log >&2
        exit 1
    }
    ./config.status --help > status-help.log 2>&1 || {
        cat status-help.log >&2
        exit 1
    }
    grep -F '  -dest:-source destB:sourceB' status-help.log >/dev/null || {
        printf '%s\n' 'error: positional parameters were misinterpreted' >&2
        cat status-help.log >&2
        exit 1
    }
)
printf '%s\n' 'PASS: obsolete AC_LINK_FILES preserves option-like filenames'
