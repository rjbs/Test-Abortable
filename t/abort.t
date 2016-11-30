use strict;
use warnings;

use Test2::API qw(intercept);

use Test::Abortable;
use Test::More;

{
  package Abort::Test;

  use Data::Dumper;

  use overload '""' => sub { Dumper($_[0]) };

  sub throw {
    my $self = bless $_[1], $_[0];
    die $self;
  }

  sub as_test_abort_events {
    my @diag = @{ $_[0]{diagnostics} || [] };
    return [
      [ Ok => (pass => $_[0]{pass} || 0, name => $_[0]{description}) ],
      map {; [ Diag => (message => $_) ] } @diag,
    ];
  }
}

my $events = intercept {
  Test::Abortable::subtest "this test will abort" => sub {
    pass("one");
    pass("two");

    Abort::Test->throw({
      description => "just give up",
    });

    pass("three");
    pass("four");
    pass("five");
  };

  Test::Abortable::subtest "this will run just fine" => sub {
    pass("everything is just fine");
  };

  Test::Abortable::subtest "I like fine wines and cheeses" => sub {
    pass("wine wine wine wine cheese");

    Abort::Test->throw({
      pass => 1,
      description => "that was enough wine and cheese",
      diagnostics => [ "Fine wine", "Fine cheese" ],
    });

    fail("feeling gross");
  };
};

my @subtests = grep {; $_->isa('Test2::Event::Subtest') } @$events;

is(@subtests, 3, "we ran three subtests (the three test methods)");

subtest "first subtest" => sub {
  my @oks = grep {; $_->isa('Test2::Event::Ok') } @{ $subtests[0]->subevents };
  is(@oks, 3, "three pass/fail events");
  ok($oks[0]->pass, "first passed");
  ok($oks[1]->pass, "second passed");
  ok(! $oks[2]->pass, "third failed");
  is($oks[2]->name, "just give up", "the final Ok test looks like our abort");
  isa_ok($oks[2]->get_meta('test_abort_object'), 'Abort::Test', 'test_abort_object');
};

subtest "third subtest" => sub {
  my @oks = grep {; $_->isa('Test2::Event::Ok') } @{ $subtests[2]->subevents };
  is(@oks, 2, "two pass/fail events");
  ok($oks[0]->pass, "first passed");
  ok($oks[1]->pass, "second passed");
  is(
    $oks[1]->name,
    "that was enough wine and cheese",
    "the final Ok test looks like our abort"
  );
  isa_ok($oks[1]->get_meta('test_abort_object'), 'Abort::Test', 'test_abort_object');

  my @diags = grep {; $_->isa('Test2::Event::Diag') } @{ $subtests[2]->subevents };
  is(@diags, 2, "we have two diagnostics");
  is_deeply(
    [ map {; $_->message } @diags ],
    [
      "Fine wine",
      "Fine cheese",
    ],
    "...which we expected",
  );
};


done_testing;
