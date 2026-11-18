#!/usr/bin/env perl
# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: perl -I PREFIX/share/autoconf tests/warnings-merge.pl
use strict;
use warnings;
use Autom4te::ChannelDefs qw(merge_WARNINGS);

sub check_merge
{
  my ($source, $options, $expected) = @_;
  local $ENV{WARNINGS} = $source;
  my $merged = merge_WARNINGS (@$options);
  die "warning merge: '$source' + ["
    . join (',', @$options) . "] -> '$merged', expected '$expected'\n"
    unless $merged eq $expected;
}

# An exception following -Wall must survive the autoreconf handoff.
check_merge ('all,no-obsolete,error', [],
             'all,no-obsolete,error');
check_merge ('all', ['no-obsolete', 'error'],
             'all,no-obsolete,error');
# Conversely, a later 'all' resets an earlier individual suppression.
check_merge ('no-obsolete,all', [],
             'all');
check_merge ('none', ['syntax', 'error'],
             'none,syntax,error');
check_merge ('syntax,none', [],
             'none');
# Warning switches cascade: sorting them changes the enabled channels.
check_merge ('no-portability,extra-portability,error', [],
             'no-portability,extra-portability,error');
check_merge ('extra-portability,no-portability', [],
             'extra-portability,no-portability');
# CLI categories retain precedence and the final -Wno-error is respected.
check_merge ('all,no-obsolete,error', ['obsolete', 'no-error'],
             'all,no-obsolete,obsolete,no-error');
check_merge ('all,error', ['none', 'syntax'],
             'none,syntax,error');
# Preserve unknown categories: autoreconf deliberately forwards them to
# older subsidiary programs via WARNINGS, where they can be ignored.
check_merge ('vendor-optional', ['all', 'no-obsolete'],
             'all,no-obsolete');

print "PASS: warning switches preserve order, exceptions and -Werror\n";
