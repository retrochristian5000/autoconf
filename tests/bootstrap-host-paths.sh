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
# The wrapper has a non-GNU identity, but offers compatible M4 behavior.
# This tests vendor-neutral selection, not native BSD M4 compatibility.
HOST_M4=$(command -v m4)
export HOST_M4
cat > "$tmp/tools/gm4" <<'EOF'
#!/bin/sh
case "$1" in
    --version) printf '%s\n' 'Compatible M4 9.0'; exit 0 ;;
    --help) printf '%s\n' '--debugfile --error-output'; exit 0 ;;
    --gnu) exit 1 ;;
esac
exec "$HOST_M4" "$@"
EOF
cat > "$tmp/tools/aclocal" <<'EOF'
#!/bin/sh
base=${AUTOCONF%/bin/autoconf}
test -d "$base/lib/Autom4te" || exit 2
printf '%s\n' "$base" >> "$TEST_DIRS"
echo aclocal >> "$TEST_LOG"
printf '%s\n' "$M4" >> "$TEST_M4_CHOICES"
test "${TEST_FAIL:-0}" != 1
EOF
printf '#!/bin/sh\necho automake >> "$TEST_LOG"\n' > "$tmp/tools/automake"
chmod +x "$base/bootstrap" "$base/build-aux/git-version-gen" "$tmp/tools/"*
export TEST_LOG="$tmp/log" TEST_DIRS="$tmp/dirs" TEST_M4_CHOICES="$tmp/m4-choices"
mkdir -p "$tmp/tmp dir with spaces"
(
    cd "$base"
    unset M4
    PATH="$tmp/tools:$PATH" TMPDIR="$tmp/tmp dir with spaces" \
        ACLOCAL="$tmp/tools/aclocal" AUTOMAKE="$tmp/tools/automake" \
        /bin/sh ./bootstrap
)
test "$(cat "$TEST_LOG")" = "$(printf 'aclocal\nautoconf\nautomake')"
test "$(head -n 1 "$TEST_M4_CHOICES")" = "$tmp/tools/gm4"
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
# An obsolete GNU gm4 must not eclipse a working newer GNU m4.
cp "$tmp/tools/gm4" "$tmp/tools/m4"
cat > "$tmp/tools/gm4" <<'EOF'
#!/bin/sh
case "$1" in
    --version) printf '%s\n' 'GNU M4 1.4.15'; exit 0 ;;
esac
exec "$HOST_M4" "$@"
EOF
chmod +x "$tmp/tools/gm4"
(
    cd "$base"
    unset M4
    PATH="$tmp/tools:$PATH" ACLOCAL="$tmp/tools/aclocal" \
        AUTOMAKE="$tmp/tools/automake" /bin/sh ./bootstrap
)
test "$(tail -n 1 "$TEST_M4_CHOICES")" = "$tmp/tools/m4" ||
    { echo 'old GNU gm4 eclipsed working GNU m4' >&2; exit 1; }

# An explicitly selected unusable M4 must fail instead of falling back.
printf '#!/bin/sh\nexit 0\n' > "$tmp/tools/broken-m4"
chmod +x "$tmp/tools/broken-m4"
if (
    cd "$base"
    M4="$tmp/tools/broken-m4" PATH="$tmp/tools:$PATH" \
        ACLOCAL="$tmp/tools/aclocal" AUTOMAKE="$tmp/tools/automake" \
        /bin/sh ./bootstrap
) > "$tmp/invalid-m4.log" 2>&1; then
    printf '%s\n' 'invalid explicit M4 unexpectedly passed' >&2
    exit 1
fi
grep -F 'lacks required Autoconf features' "$tmp/invalid-m4.log" >/dev/null

echo 'PASS: bootstrap feature-based M4 selection, rejected overrides, and cleanup'
