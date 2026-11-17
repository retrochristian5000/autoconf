# m4.m4 serial 13

# Copyright (C) 2000, 2006-2017, 2020-2026 Free Software Foundation,
# Inc.

# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without warranty of any kind.

# AC_PROG_M4
# ----------
# Select a feature-compatible M4 implementation, including non-GNU
# implementations that support the M4sugar and autom4te interfaces.
# GNU M4 versions before 1.4.8 had bugs in trace and regexp support:
# https://lists.gnu.org/archive/html/bug-gnu-utils/2006-11/msg00096.html
# https://lists.gnu.org/archive/html/bug-autoconf/2009-07/msg00023.html
# Also, check whether --error-output (through 1.4.x) or --debugfile (2.0)
# is supported, and AC_SUBST M4_DEBUGFILE accordingly.
# Also avoid versions of m4 that trigger strstr bugs.
AC_DEFUN([AC_PROG_M4],
  [AC_ARG_VAR([M4], [Path to a feature-compatible M4 implementation.  Defaults
    to the first 'm4', 'gm4', or 'gnum4' on PATH meeting Autoconf needs.])
  AC_CACHE_CHECK([for M4 with accurate tracing and GNU-style macros], [ac_cv_path_M4],
    [rm -f conftest.m4f
ac_had_posixly_correct=${POSIXLY_CORRECT:+yes}
AS_UNSET([POSIXLY_CORRECT])
AC_PATH_PROGS_FEATURE_CHECK([M4], [m4 gm4 gnum4],
      [dnl Creative quoting here to avoid raw dnl and ifdef in configure.
      # Reject implementations that ignore required tracing and freeze flags.
      # Root out GNU M4 1.4.15 with buggy false negative replacement strstr.
      # Root out Glibc 2.9 - 2.12 and GNU M4 1.4.11 - 1.4.15 with buggy
      # false positive strstr.
      ac_snippet=change'quote(<,>)in''dir(<if''def>,mac,bug)'
      ac_snippet=${ac_snippet}pat'subst(a,\(b\)\|\(a\),\1)d'nl
      ac_snippet=${ac_snippet}${as_nl}if'else(in''dex(..wi.d.,.d.),-1,bug)'
      ac_snippet=${ac_snippet}${as_nl}if'else(in''dex(dnl
;:11-:12-:12-:12-:12-:12-:12-:12-:12.:12.:12.:12.:12.:12.:12.:12.:12-,dnl
:12-:12-:12-:12-:12-:12-:12-:12-),-1,,strstr-bug2)'
      # Root out M4 1.4.6 and 1.4.7, which do not implement --debug=aflq
      # correctly for macros invoked from m4wrap.
      ac_snip2=change'quote(<,>)def''ine(<T>,<>)d'nl
      ac_snip2=${ac_snip2}${as_nl}def'ine(<F>,<T(<traced>)>)d'nl
      ac_snip2=${ac_snip2}${as_nl}m4'wrap(<F>)d'nl
      # Keep executable paths quoted: a host may install GNU M4 beneath a
      # prefix containing spaces, even if the selected tool is otherwise valid.
      AS_ECHO(["$as_me:${as_lineno-$LINENO}: trying $ac_path_M4"]) \
          >&AS_MESSAGE_LOG_FD
      test -z "`"$ac_path_M4" -F conftest.m4f </dev/null 2>&1`" \
      && test -z "`AS_ECHO(["$ac_snippet"]) | "$ac_path_M4" --trace=mac 2>&1`" \
      && test -f conftest.m4f \
      && test x"`AS_ECHO([frozen-ok]) | \
                "$ac_path_M4" --reload-state=conftest.m4f --fatal-warning 2>/dev/null`" = xfrozen-ok \
      && test x"`AS_ECHO(["$ac_snip2"]) | \
                "$ac_path_M4" --trace=T --debug=aflq --fatal-warning 2>&1`" = \
              x'm4trace:stdin:3: -1- T(<traced>)' \
      && ac_cv_path_M4=$ac_path_M4 ac_path_M4_found=:
      rm -f conftest.m4f],
      [AC_MSG_ERROR([no M4 with the required macro expansion, freeze and trace
features could be found.  GNU M4 1.4.8+ is supported, and 1.4.16+ is
recommended; other implementations must pass the same capability probes.
GNU M4 1.4.15 and some GNU M4/glibc combinations have strstr bugs.])])])
  M4=$ac_cv_path_M4
  AC_CACHE_CHECK([whether $ac_cv_path_M4 accepts --gnu],
    [ac_cv_prog_gnu_m4_gnu],
    [if "$M4" --gnu </dev/null >/dev/null 2>&1; then
      ac_cv_prog_gnu_m4_gnu=yes
    else
      ac_cv_prog_gnu_m4_gnu=no
    fi])
  if test "$ac_cv_prog_gnu_m4_gnu" = yes; then
    M4_GNU=--gnu
  else
    M4_GNU=
  fi
  AC_SUBST([M4_GNU])
  if test x$ac_had_posixly_correct = xyes; then
    POSIXLY_CORRECT=:
    if test "$ac_cv_prog_gnu_m4_gnu" = no; then
      AC_MSG_WARN([the selected M4 does not accept --gnu])
      AC_MSG_WARN([using it with POSIXLY_CORRECT set may cause problems])
    fi
  fi
  AC_CACHE_CHECK([how M4 writes trace files], [ac_cv_prog_gnu_m4_debugfile],
    [ac_cv_prog_gnu_m4_debugfile=none
    for ac_m4_debug_opt in --debugfile --error-output; do
      rm -f conftest.m4t
      if printf '%s\\n' \
           'changequote(<,>)define(<T>,<>)' \
           'define(<F>,<T(<traced>)>)' \
           'm4wrap(<F>)' \
           | "$M4" --trace=T --debug=aflq --fatal-warning \
             "$ac_m4_debug_opt=conftest.m4t" >/dev/null 2>&1 \
         && test -s conftest.m4t \
         && grep -F 'T(<traced>)' conftest.m4t >/dev/null 2>&1; then
        ac_cv_prog_gnu_m4_debugfile=$ac_m4_debug_opt
        break
      fi
    done
    rm -f conftest.m4t])
  AS_IF([test "$ac_cv_prog_gnu_m4_debugfile" = none],
    [AC_MSG_ERROR([selected M4 cannot write required trace files])])
  AC_SUBST([M4_DEBUGFILE], [$ac_cv_prog_gnu_m4_debugfile])
])

# Backward-compatible macro name for existing Autoconf consumers.
AC_DEFUN([AC_PROG_GNU_M4], [AC_REQUIRE([AC_PROG_M4])])
