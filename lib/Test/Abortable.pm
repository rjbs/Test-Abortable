use strict;
use warnings;
package Test::Abortable;
# ABSTRACT: subtests that you can die your way out of ... but still live

use Test2::API 1.302045 ();
use Sub::Exporter -setup => {
  exports => [ qw(subtest testeval) ],
  groups  => { default => [ qw(subtest testeval) ] },
  # TODO: use a custom installer that will silently clobber *iff* it's
  # replacing stock Test::More subtest with our subtest
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

1;
