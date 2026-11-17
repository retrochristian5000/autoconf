#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise shipped Makefile recipes with failing generators and GNU Make."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MAKE = shutil.which("gmake") or shutil.which("make")


class MakeRuleTests(unittest.TestCase):
    def setUp(self):
        if not MAKE:
            self.skipTest("no Make implementation")
        tmp = tempfile.TemporaryDirectory(prefix="autoconf-make-")
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.src = self.root / "source"
        self.src.mkdir()
        (self.root / "Makefile").write_text("# configured\n")
        self.harness = self.root / "fixture.mk"
        self.harness.write_text(
            "srcdir = source\n"
            "top_srcdir = .\n"
            "MKDIR_P = mkdir -p\n"
            "edit = sed -e 's/@TOKEN@/ready/g'\n"
            "edit_wrapper = sed -e 's/@wrap_program@/$(@F)/g'\n"
            "MY_AUTOM4TE = python3 mock-autom4te.py\n"
            "SED = sed\n"
            "MAKEINFO = /bin/sh mock-makeinfo.sh\n"
            "OMIT_TRAILING_EMPTY_LINES = '/^$$/d'\n"
            ".SUFFIXES: .m4 .m4f\n"
        )
        self.file("mock-autom4te.py",
                  "import os, pathlib, sys\n"
                  "outs=[v.split('=',1)[1] for v in sys.argv[1:] "
                  "if v.startswith('--output=')]\n"
                  "if outs: pathlib.Path(outs[0]).write_text('frozen\\n')\n"
                  "else: print('AN_OUTPUT:good: value')\n"
                  "sys.exit(int(os.environ.get('FAIL_AUTOM4TE','0')))\n")

    def file(self, name, value, src=False):
        p = (self.src if src else self.root) / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(value)
        return p

    def make(self, part, goal, fail=None, extra=()):
        env = dict(os.environ)
        if fail:
            env.update(fail)
        p = Path(part)
        if not p.is_absolute():
            p = ROOT / part
        return subprocess.run(
            [MAKE, "--no-print-directory", "-f", str(self.harness),
             "-f", str(p), *extra, goal], cwd=self.root, env=env,
            text=True, capture_output=True, check=False, timeout=35,
        )

    def success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def failure(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_script_preserves_old_output(self):
        self.file("bin/autoconf.in", "#!/bin/sh\n@TOKEN@\n", src=True)
        self.success(self.make("bin/local.mk", "bin/autoconf"))
        target = self.root / "bin/autoconf"
        old = target.read_bytes()
        self.assertIn(b"ready", old)
        self.failure(self.make("bin/local.mk", "bin/autoconf",
                               extra=("-B", "edit=false")))
        self.assertEqual(target.read_bytes(), old)
        self.assertFalse((self.root / "bin/autoconf.tmp").exists())

    def test_autom4te_cfg_preserves_old_output(self):
        self.file("lib/autom4te.in", "M4=@TOKEN@\n", src=True)
        self.success(self.make("lib/local.mk", "lib/autom4te.cfg"))
        output = self.root / "lib/autom4te.cfg"
        old = output.read_bytes()
        self.assertIn(b"ready", old)
        self.failure(self.make("lib/local.mk", "lib/autom4te.cfg",
                               extra=("-B", "edit=false")))
        self.assertEqual(output.read_bytes(), old)
        self.assertFalse((self.root / "lib/autom4te.cfg-t").exists())

    def test_autoscan_propagates_autom4te_failure(self):
        self.file("lib/autoscan/autoscan.pre",
                  "# initial comment\nentry\n", src=True)
        self.file("lib/autoconf/autoconf.m4f", "freeze\n")
        name = "lib/autoscan/autoscan.list"
        self.success(self.make("lib/local.mk", name))
        output = self.root / name
        old = output.read_bytes()
        self.assertIn(b"AN_OUTPUT:good", old)
        self.failure(self.make("lib/local.mk", name,
                               fail={"FAIL_AUTOM4TE": "4"}, extra=("-B",)))
        self.assertEqual(output.read_bytes(), old)
        self.assertFalse((self.root / (name + "-t")).exists())
        self.assertFalse((self.root / (name + "-unsorted")).exists())

    def test_m4_freeze_preserves_old_state(self):
        self.file("lib/m4sugar/probe.m4", "define([A],[B])\n")
        name = "lib/m4sugar/probe.m4f"
        self.success(self.make("lib/freeze.mk", name))
        output = self.root / name
        old = output.read_bytes()
        self.failure(self.make("lib/freeze.mk", name,
                               fail={"FAIL_AUTOM4TE": "4"}, extra=("-B",)))
        self.assertEqual(output.read_bytes(), old)
        self.assertFalse((self.root / (name + ".tmp")).exists())

    def test_wrapper_preserves_old_script(self):
        self.file("tests/wrapper.in", "#!/bin/sh\n@wrap_program@\n")
        self.success(self.make("tests/local.mk", "tests/autoconf"))
        output = self.root / "tests/autoconf"
        old = output.read_bytes()
        self.failure(self.make("tests/local.mk", "tests/autoconf",
                               extra=("-B", "edit_wrapper=false")))
        self.assertEqual(output.read_bytes(), old)
        self.assertFalse((self.root / "tests/autoconf.tmp").exists())

    def test_install_rule_reports_makeinfo_failure(self):
        text = (ROOT / "Makefile.am").read_text()
        start = text.index("$(srcdir)/INSTALL: $(top_srcdir)/doc/install.texi")
        end = text.index("\nendif", start)
        recipe = self.file("install-fragment.mk", text[start:end] + "\n")
        self.file("doc/install.texi", "Help text\n")
        self.file("mock-makeinfo.sh",
                  "#!/bin/sh\nprintf 'updated INSTALL\\n'\n"
                  'if [ "$FAIL_MAKEINFO" = "1" ]; then exit 9; fi\n')
        output = self.file("INSTALL", "original\n", src=True)
        self.success(self.make(recipe, "source/INSTALL", extra=("-B",)))
        old = output.read_bytes()
        self.assertIn(b"updated INSTALL", old)
        self.failure(self.make(recipe, "source/INSTALL",
                               fail={"FAIL_MAKEINFO": "1"}, extra=("-B",)))
        self.assertEqual(output.read_bytes(), old)
        for path in ("INSTALL-texi.tmp", "INSTALL-raw.tmp", "source/INSTALL-t"):
            self.assertFalse((self.root / path).exists(), path)

    def test_man_pages_retain_shared_dependencies(self):
        text = (ROOT / "man/local.mk").read_text()
        self.assertEqual(text.count("$(man_common_dep)"), 7)
        self.assertNotIn("$(common_dep)", text)
        self.assertIn("$(top_srcdir)/.version", text)


if __name__ == "__main__":
    unittest.main()
