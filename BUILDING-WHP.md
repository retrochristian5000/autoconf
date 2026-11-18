# WHP Autoconf: standalone and dependency builds

This fork is an independent Autoconf source repository. It must not require
the QEMU repository, its `seeds/` directory, or its Python bootstrap helper.

## Standalone source checkout

A source checkout requires a POSIX shell, a feature-compatible M4 (GNU M4 is
the standard tested backend), Perl, a paired Automake/aclocal installation,
and GNU Make. Full builds that generate manuals also need Texinfo
(`makeinfo`) and `help2man`. A working C compiler is needed by the
consumer smoke test below.

```sh
./bootstrap
mkdir -p build
cd build
../configure --prefix="$HOME/.local/whp-autoconf"
make -j2
make install
/bin/sh ../tests/installed-suite-smoke.sh "$HOME/.local/whp-autoconf"
```

These commands are intentionally independent of QEMU. Building in a separate
directory avoids mixing configured artifacts with tracked Autoconf sources.
The smoke test checks all seven installed commands and uses the installed
`autoreconf` to generate and run `configure` for an unrelated package.
It checks installed behavior, not merely whether bootstrap exited zero.

Git checkouts without usable release tags may report `UNKNOWN` as a version.
CI provides a temporary `.tarball-version` based on the tracked
`.prev-version`; it must not be committed as a guessed release.
Distribution tarballs carry their own version metadata.

## Embedded dependency: QEMU

QEMU pins this repository at `toolchains/autoconf`. Its
`scripts/ensure-autoconf.py` owns integration concerns: prerequisite
selection, architecture/SDK isolation, source pin reconciliation,
documentation-free host-tool installation, caching, rollback, diagnostics,
and runtime validation.

Autoconf owns `./bootstrap`, `configure`, its generated Makefile rules,
installation layout, and standalone CI. A consumer supplies tools through
its environment and a private `--prefix`; it must not rewrite this
repository's sources to satisfy parent-specific paths.

The dependency's pinned commit, rather than the latest branch tip, is the
source of truth for a QEMU build. Updating the Autoconf fork does not silently
update the QEMU gitlink. Both repositories continue to use their existing
`master` branches.
