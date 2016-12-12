use strict;
use warnings;
package Test::Abortable;
# ABSTRACT: subtests that you can die your way out of ... but survive

=head1 OVERVIEW

Test::Abortable provides a simple system for catching some exceptions and
turning them into test events.  For example, consider the code below:

  use Test::More;
  use Test::Abortable;

  use My::API; # code under test

  my $API = My::API->client;

  subtest "collection distinction" => sub {
    my $result = $API->do_first_thing;

    is($result->documents->first->title,  "The Best Thing");
    isnt($result->documents->last->title, "The Best Thing");
  };

  subtest "document transcendence"   => sub { ... };
  subtest "semiotic multiplexing"    => sub { ... };
  subtest "homoiousios type vectors" => sub { ... };

  done_testing;

In this code, C<< $result->documents >> is a collection.  It has a C<first>
method that will throw an exception if the collection is empty.  If that
happens in our code, our test program will die and most of the other subtests
won't run.  We'd rather that we only abort the I<subtest>.  We could do that 
in a bunch of ways, like adding:

  return fail("no documents in response") if $result->documents->is_empty;

...but this becomes less practical as the number of places that might throw
these kinds of exceptions grows.  To minimize code that boils down to "and then
stop unless it makes sense to go on," Test::Abortable provides a means to
communicate, via exceptions, that the running subtest should be aborted,
possibly with some test output, and that the program should then continue.

Test::Abortable exports a C<L</subtest>> routine that behaves like L<the one in
Test::More|Test::More/subtest> but will handle and recover from abortable
exceptions (defined below).  It also exports C<L</testeval>>, which behaves
like a block eval that only catches abortable exceptions.

For an exception to be "abortable," in this sense, it must respond to a
C<as_test_abort_events> method.  This method must return an arrayref of
arrayrefs that describe the Test2 events to emit when the exception is caught.
For example, the exception thrown by our sample code above might have a
C<as_test_abort_events> method that returns:

  [
    [ Ok => (pass => 0, name => "->first called on empty collection") ],
  ]

It's permissible to have passing Ok events, or only Diag events, or multiple
events, or none — although providing none might lead to some serious confusion.

Right now, any exception that provides this method will be honored.  In the
future, a facility for only allowing abortable exceptions of a given class may
be added.

=cut

use Test2::API 1.302045 ();
use Sub::Exporter -setup => {
  exports => [ qw(subtest testeval) ],
  groups  => { default => [ qw(subtest testeval) ] },
};

=func subtest

  subtest "do some stuff" => sub {
    do_things;
    do_stuff;
    do_actions;
  };

This routine looks just like Test::More's C<subtest> and acts just like it,
too, with one difference: the code item passed in is executed in a block
C<eval> and any exception thrown is checked for C<as_test_abort_events>.  If
there's no exception, it returns normally.  If there's an abortable exception,
the events are sent to the test hub and the subtest finishes normally.  If
there's a non-abortable exception, it is rethrown.

=cut

sub subtest {
  my ($name, $code) = @_;

  my $ctx = Test2::API::context();

  my $pass = Test2::API::run_subtest($name, sub {
    my $ok = eval { $code->(); 1 };

    my $ctx = Test2::API::context();

    if (! $ok) {
      my $error = $@;
      if (ref $error and my $events = eval { $error->as_test_abort_events }) {
        for (@$events) {
          my $e = $ctx->send_event(@$_);
          $e->set_meta(test_abort_object => $error)
        }
      } else {
        $ctx->release;
        die $error;
      }
    }

    $ctx->release;

    return;
  });

  $ctx->release;

  return $pass;
}

=func testeval

  my $result = testeval {
    my $x = get_the_x;
    my $y = acquire_y;
    return $x * $y;
  };

C<testeval> behaves like C<eval>, but only catches abortable exceptions.  If
the code passed to C<testeval> throws an abortable exception C<testeval> will
return false and put the exception into C<$@>.  Other exceptions are
propagated.

=cut

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
      die $error;
    }
  }

  $ctx->release;
  return $wa ? @result : $result[0];
}

=head1 EXCEPTION IMPLEMENTATIONS

You don't need to use an exception class provided by Test::Abortable to build
abortable exceptions.  This is by design.  In fact, Test::Abortable doesn't
ship with any abortable exception classes at all.  You should just add a
C<as_test_abort_events> where it's useful and appropriate.

Here are two possible simple implementations of trivial abortable exception
classes.  First, using plain old vanilla objects:

  package Abort::Test {
    sub as_test_abort_events ($self) {
      return [ [ Ok => (pass => 0, name => $self->{message}) ] ];
    }
  }
  sub abort ($message) { die bless { message => $message }, 'Abort::Test' }

This works, but if those exceptions ever get caught somewhere else, you'll be
in a bunch of pain because they've got no stack trace, no stringification
behavior, and so on.  For a more robust but still tiny implementation, you
might consider L<failures>:

  use failures 'testabort';
  sub failure::testabort::as_test_abort_events ($self) {
    return [ [ Ok => (pass => 0, name => $self->msg) ] ];
  }

For whatever it's worth, the author's intent is to add C<as_test_abort_events>
methods to his code through the use of application-specific Moose roles,

=cut

1;
