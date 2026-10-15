#!/bin/sh
# Bootstrap fixture: no system Autoconf required.
set -eu
src=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d "/tmp/autoconf-bootstrap-guard.XXXXXXXX") || exit 1
trap 'rm -rf "$tmp"' 0
trap 'exit 1' 1 2 3 15
base="$tmp/source with spaces"
mkdir -p "$base/bin" "$base/lib/Autom4te" "$base/lib/autoconf" "$base/lib/m4sugar" "$base/build-aux" "$tmp/tools"
cp "$src/bootstrap" "$base/bootstrap"
printf '%s\n' 'RELEASE_YEAR=2026' 'm4_define([autoconf_PACKAGE_NAME], [GNU Autoconf])' 'm4_define([autoconf_PACKAGE_BUGREPORT], [bug-autoconf@gnu.org])' > "$base/configure.ac"
printf '#!/bin/sh\nprintf 2.72\n' > "$base/build-aux/git-version-gen"
printf '#!/bin/sh\nprintf "autoconf\\n" >> "$TEST_LOG"\n' > "$base/bin/autoconf.in"
printf '#!/bin/sh\nexit 0\n' > "$base/bin/autom4te.in"
printf 'mock\n' > "$base/lib/autom4te.in"
printf 'version @VERSION@\n' > "$base/lib/autoconf_version.in"
cat > "$tmp/tools/gm4" <<'EOF'
#!/bin/sh
case "$1" in
    --gnu) [ "${2:-}" = --version ] && { echo 'GNU M4 1.4.19'; exit 0; } ;;
    --help) echo '--gnu --debugfile'; exit 0 ;;
esac
exit 1
EOF
cat > "$tmp/tools/aclocal" <<'EOF'
#!/bin/sh
base=${AUTOCONF%/bin/autoconf}
test -d "$base/lib/Autom4te" || exit 2
printf '%s\n' "$base" >> "$TEST_DIRS"
echo aclocal >> "$TEST_LOG"
test "${TEST_FAIL:-0}" != 1
EOF
printf '#!/bin/sh\necho automake >> "$TEST_LOG"\n' > "$tmp/tools/automake"
chmod +x "$base/bootstrap" "$base/build-aux/git-version-gen" "$tmp/tools/"*
export TEST_LOG="$tmp/log" TEST_DIRS="$tmp/dirs"
mkdir -p "$tmp/tmp dir with spaces"
(
    cd "$base"
    unset M4
    PATH="$tmp/tools:$PATH" TMPDIR="$tmp/tmp dir with spaces" \
        ACLOCAL="$tmp/tools/aclocal" AUTOMAKE="$tmp/tools/automake" \
        /bin/sh ./bootstrap
)
test "$(cat "$TEST_LOG")" = "$(printf 'aclocal\nautoconf\nautomake')"
while IFS= read -r path; do
    test ! -e "$path"
done < "$TEST_DIRS"
: > "$TEST_DIRS"
if (
    cd "$base"
    unset M4
    PATH="$tmp/tools:$PATH" TEST_FAIL=1 ACLOCAL="$tmp/tools/aclocal" \
        AUTOMAKE="$tmp/tools/automake" /bin/sh ./bootstrap
) > "$tmp/failure.log" 2>&1; then
    echo 'failing aclocal unexpectedly passed' >&2
    exit 1
fi
while IFS= read -r path; do
    test ! -e "$path"
done < "$TEST_DIRS"
echo 'PASS: bootstrap source paths, GNU M4, and cleanup'
