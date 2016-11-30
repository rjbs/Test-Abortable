use strict;
use warnings;
package Test::Abortable;
# ABSTRACT: subtests that you can die your way out of ... but still live

use Test2::API 1.302045 ();
use Sub::Exporter -setup => {
  exports => [ qw(subtest testeval) ],
  groups  => { default => [ qw(subtest testeval) ] },
};

sub subtest {
  my ($name, $code) = @_;

  my $ctx = Test2::API::context();

  my $pass = Test2::API::run_subtest($name, sub {
    my $ctx = Test2::API::context();

    my $ok = eval { $code->(); 1 };

    if (! $ok) {
      my $error = $@;
      if (ref $error and my $events = eval { $error->as_test_abort_events }) {
        for (@$events) {
          my $e = $ctx->send_event(@$_);
          $e->set_meta(test_abort_object => $error)
        }
      } else {
        die $error;
      }
    }

    $ctx->release;

    return;
  });

  $ctx->release;

  return $pass;
}

sub testeval (&) {
  my ($code) = @_;
  my $ctx = Test2::API::context();
  my @result;

  my $wa = wantarray;
  my $ok = eval {
    if    (not defined $wa) { $code->() }
    elsif (not         $wa) { @result = scalar $code->() }
    else                    { @result = $code->() }

    1;
  };

  if (! $ok) {
    my $error = $@;
    if (ref $error and my $events = eval { $error->as_test_abort_events }) {
      for (@$events) {
        my $e = $ctx->send_event(@$_);
        $e->set_meta(test_abort_object => $error)
      }

      $ctx->release;
      $@ = $error;
      return;
    } else {
      # XXX Should I release context here? -- rjbs, 2016-11-30
      die $error;
    }
  }

  $ctx->release;
  return $wa ? @result : $result[0];
}

1;
