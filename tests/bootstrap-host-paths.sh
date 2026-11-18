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
printf 'M4=@M4@\nPERL=@PERL@\n' > "$base/lib/autom4te.in"
printf 'version @VERSION@\n' > "$base/lib/autoconf_version.in"
# The wrapper has a non-GNU identity, but offers compatible M4 behavior.
# This tests vendor-neutral selection, not native BSD M4 compatibility.
# Tests use a real compatible M4 engine beneath the vendor-neutral
# wrapper.  On macOS the default /usr/bin/m4 may be BSD M4 and insufficient.
# An explicit HOST_M4 is authoritative; otherwise try available candidates.
if test -n "${HOST_M4-}"; then
    command -v "$HOST_M4" >/dev/null 2>&1 || {
        printf '%s\n' "HOST_M4 executable not found: $HOST_M4" >&2
        exit 1
    }
else
    HOST_M4=
    for m4_candidate in gm4 gnum4 m4; do
        m4_path=$(command -v "$m4_candidate") || continue
        if "$m4_path" --debug=aflq --fatal-warning </dev/null >/dev/null 2>&1; then
            HOST_M4=$m4_path
            break
        fi
    done
    if test -z "$HOST_M4"; then
        printf '%s\n' 'SKIP: no M4 backend with the required extensions for fixture tests'
        exit 77
    fi
fi
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
if [ -n "${TEST_EXPECT_M4:-}" ]; then
    cfg="${AUTOCONF%/bin/autoconf}/lib/autom4te.cfg"
    grep -Fqx "M4=$TEST_EXPECT_M4" "$cfg" || exit 3
    grep -Fqx "PERL=$TEST_EXPECT_PERL" "$cfg" || exit 3
fi
if test "${TEST_INTERRUPT:-0}" = 1; then
    kill -TERM "$TEST_BOOTSTRAP_PID" || exit 4
    exit 0
fi
if test "${TEST_FAIL:-0}" = 1; then
    exit "${TEST_FAIL_STATUS:-1}"
fi
exit 0
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
# The bootstrap must not replace a failing tool's exit code with the exit
# trap's rm status. Every created temporary installation must be removed.
: > "$TEST_DIRS"
failure_status=0
(
    cd "$base"
    unset M4
    PATH="$tmp/tools:$PATH" TEST_FAIL=1 TEST_FAIL_STATUS=17 \
        ACLOCAL="$tmp/tools/aclocal" AUTOMAKE="$tmp/tools/automake" \
        /bin/sh ./bootstrap
) > "$tmp/failure-status.log" 2>&1 || failure_status=$?
test "$failure_status" -eq 17 || {
    printf 'bootstrap lost command failure status: %s\n' "$failure_status" >&2
    exit 1
}
grep -F 'aclocal failed (status 17; warning policy: -Wall -Werror)' \
    "$tmp/failure-status.log" >/dev/null || {
    printf '%s\n' 'bootstrap did not identify the failed warning-gated stage' >&2
    exit 1
}
while IFS= read -r path; do
    test ! -e "$path"
done < "$TEST_DIRS"

# Inject TERM after aclocal has observed the temporary installation. The
# extra sh process records its own PID and execs bootstrap with that PID.
: > "$TEST_DIRS"
signal_status=0
(
    cd "$base"
    unset M4
    PATH="$tmp/tools:$PATH" TEST_INTERRUPT=1 \
        ACLOCAL="$tmp/tools/aclocal" AUTOMAKE="$tmp/tools/automake" \
        /bin/sh -c 'TEST_BOOTSTRAP_PID=$$; export TEST_BOOTSTRAP_PID; exec /bin/sh ./bootstrap'
) > "$tmp/signal.log" 2>&1 || signal_status=$?
test "$signal_status" -eq 143 || {
    printf 'bootstrap lost SIGTERM status: %s\n' "$signal_status" >&2
    cat "$tmp/signal.log" >&2
    exit 1
}
while IFS= read -r path; do
    test ! -e "$path"
done < "$TEST_DIRS"

# Simulate a mktemp success followed by a non-traversable directory. The
# cleanup trap must already be installed when the canonicalization fails.
TEST_REAL_MKTEMP=$(command -v mktemp)
export TEST_REAL_MKTEMP
cat > "$tmp/tools/mktemp" <<'EOF'
#!/bin/sh
case "${TEST_FAIL_CANONICAL:-0}:$2" in
    1:*/acboot.*)
        created=$("$TEST_REAL_MKTEMP" "$@") || exit 1
        chmod 000 "$created" || exit 1
        printf '%s\n' "$created" >> "$TEST_CREATED_DIRS"
        printf '%s\n' "$created"
        exit 0 ;;
esac
exec "$TEST_REAL_MKTEMP" "$@"
EOF
chmod +x "$tmp/tools/mktemp"
: > "$tmp/canonical-created"
canonical_status=0
(
    cd "$base"
    unset M4
    PATH="$tmp/tools:$PATH" TEST_FAIL_CANONICAL=1 \
        TEST_CREATED_DIRS="$tmp/canonical-created" \
        ACLOCAL="$tmp/tools/aclocal" AUTOMAKE="$tmp/tools/automake" \
        /bin/sh ./bootstrap
) > "$tmp/canonical.log" 2>&1 || canonical_status=$?
test "$canonical_status" -ne 0 || {
    printf '%s\n' 'bootstrap accepted an inaccessible temp directory' >&2
    exit 1
}
test -s "$tmp/canonical-created" || exit 1
while IFS= read -r path; do
    test ! -e "$path" || {
        printf 'bootstrap leaked temp directory after canonicalization failure: %s\n' "$path" >&2
        exit 1
    }
done < "$tmp/canonical-created"

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

# Exercising M4sugar without GNU's __gnu__ marker catches identity guards.
# The wrapper delegates to an M4 engine with the required GNU extensions.
"$tmp/tools/m4" --undefine=__gnu__ -I "$src/lib" \
    "$src/lib/m4sugar/m4sugar.m4" > "$tmp/m4sugar.out"
test ! -s "$tmp/m4sugar.out"

# Paths containing sed replacement metacharacters must be preserved exactly
# inside generated bootstrap config, then the temporary install cleaned up.
special_dir="$tmp/special &%\\bin"
mkdir -p "$special_dir"
cp "$tmp/tools/m4" "$special_dir/m4"
chmod +x "$special_dir/m4"
# A path containing spaces is legitimate for M4, but Perl paths used as
# shebang interpreters must remain whitespace-free.
perl_dir="$tmp/perl&%\\bin"
mkdir -p "$perl_dir"
printf '#!/bin/sh\nexit 0\n' > "$perl_dir/perl"
chmod +x "$perl_dir/perl"
: > "$TEST_DIRS"
(
    cd "$base"
    TEST_EXPECT_M4="$special_dir/m4" TEST_EXPECT_PERL="$perl_dir/perl" \
        M4="$special_dir/m4" PERL="$perl_dir/perl" \
        ACLOCAL="$tmp/tools/aclocal" AUTOMAKE="$tmp/tools/automake" \
        PATH="$tmp/tools:$PATH" /bin/sh ./bootstrap
)
while IFS= read -r path; do
    test ! -e "$path"
done < "$TEST_DIRS"

printf '%s\n' 'PASS: bootstrap M4 selection, escaped substitutions, and cleanup'
