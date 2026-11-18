#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Validate an independently installed Autoconf as a downstream consumer.
set -eu

if test "$#" -ne 1; then
    printf '%s\n' 'usage: installed-suite-smoke.sh ABSOLUTE_PREFIX' >&2
    exit 2
fi

prefix=$1
case $prefix in
    /*) ;;
    *) printf '%s\n' "error: prefix must be absolute: $prefix" >&2; exit 2 ;;
esac

for program in autoconf autom4te autoheader autoreconf autoscan autoupdate ifnames
do
    executable=$prefix/bin/$program
    if test ! -x "$executable"; then
        printf '%s\n' "error: missing installed tool: $executable" >&2
        exit 1
    fi
    if ! version=$("$executable" --version 2>&1); then
        printf '%s\n' "error: $program --version failed: $version" >&2
        exit 1
    fi
    case $version in
        *'GNU Autoconf'*) ;;
        *) printf '%s\n' "error: $program is not the installed Autoconf: $version" >&2
           exit 1 ;;
    esac
done

work=$(mktemp -d "${TMPDIR:-/tmp}/autoconf-consumer.XXXXXXXX") || exit 1
trap 'rm -rf "$work"' 0
trap 'exit 129' 1
trap 'exit 130' 2
trap 'exit 131' 3
trap 'exit 143' 15
mkdir -p "$work/consumer"

cat > "$work/consumer/configure.ac" <<'EOF'
AC_INIT([installed-autoconf-consumer], [1.0])
AC_CONFIG_HEADERS([config.h])
AC_PROG_CC
AC_OUTPUT
EOF

(
    cd "$work/consumer"
    # Ensure that the installed suite, not the tool that bootstrapped it,
    # handles a completely separate source package.
    unset AUTOCONF AUTOM4TE AUTOHEADER AUTORECONF
    PATH="$prefix/bin:$PATH"
    export PATH
    "$prefix/bin/autoreconf" --force --install
    test -f configure
    test -f config.h.in
    /bin/sh ./configure
    test -f config.h
) || {
    printf '%s\n' 'error: installed Autoconf cannot configure a consumer' >&2
    exit 1
}
printf '%s\n' 'Autoconf installed-suite and standalone consumer: verified'
