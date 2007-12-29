package Devel::FindRef;

use strict;

use XSLoader;
use Scalar::Util;

BEGIN {
   our $VERSION = '1.1';
   XSLoader::load __PACKAGE__, $VERSION;
}

=head1 NAME

Devel::FindRef - where is that reference to my scalar hiding?

=head1 SYNOPSIS

  use Devel::FindRef;

=head1 DESCRIPTION

Tracking down reference problems (e.g. you expect some object to be
destroyed, but there are still references to it that keep it alive) can be
very hard. Fortunately, perl keeps track of all its values, so tracking
references "backwards" is usually possible.

The C<track> function can help track down some of those references back to
the variables containing them.

For example, for this fragment:

   package Test;           
                         
   our $var = "hi\n";
   my $x = \$var;      
   our %hash = (ukukey => \$var);
   our $hash2 = {ukukey2 => \$var};
                           
   sub testsub {             
      my $local = $hash2;      
      print Devel::FindRef::track \$var;
   }                             
                                   
   testsub;                        

The output is as follows (or similar to this, in case I forget to update
the manpage after some changes):

   SCALAR(0x676fa0) is
      referenced by REF(0x676fb0), which is
         in the lexical '$x' in CODE(0x676370), which is
            not found anywhere I looked :(
      referenced by REF(0x676360), which is
         in the member 'ukukey' of HASH(0x756660), which is
            in the global %Test::hash.
      in the global $Test::var.
      referenced by REF(0x6760e0), which is
         in the member 'ukukey2' of HASH(0x676f30), which is
            referenced by REF(0x77bcf0), which is
               in the lexical '$local' in CODE(0x77bcb0), which is
                  in the global &Test::testsub.
            referenced by REF(0x77bc80), which is
               in the global $Test::hash2.


It is a bit convoluted to read, but basically it says that the value
stored in C<$var> can be found:

=over 4

=item - in some variable C<$x> whose origin is not known (I frankly have no
idea why, hints accepted).

=item - in the hash element with key C<ukukey> in the hash stored in C<%Test::hash>.

=item - in the global variable named C<$Test::var>.

=item - in the hash element C<ukukey2>, in the hash in the my variable
C<$local> in the sub C<Test::testsub> and also in the hash referenced by
C<$Test::hash2>.

=back

=head1 EXPORTS

None.

=head1 FUNCTIONS

=over 4

=item $string = Devel::FindRef::track $ref[, $depth]

Track the perl value pointed to by C<$ref> up to a depth of C<$depth> and
return a descriptive string. C<$ref> can point at any perl value, be it
anonymous sub, hash, array, scalar etc.

This is the function you most often use.

=cut

sub find($);

sub track {
   my ($ref, $depth) = @_;
   @_ = ();

   my $buf = "";

   Scalar::Util::weaken $ref;

   my $track; $track = sub {
      my ($refref, $depth, $indent) = @_;

      if ($depth) {
         my (@about) = find $$refref;
         if (@about) {
            for my $about (@about) {
               $buf .= ("   ") x $indent;
               $buf .= $about->[0];
               if (@$about > 1) {
                  $buf .= " $about->[1], which is\n";
                  $track->(\$about->[1], $depth - 1, $indent + 1);
               } else {
                  $buf .= ".\n";
               }
            }
         } else {
            $buf .= ("   ") x $indent;
            $buf .= "not found anywhere I looked :(\n";
         }
      } else {
         $buf .= ("   ") x $indent;
         $buf .= "not referenced within the search depth.\n";
      }
   };

   $buf .= "$ref is\n";
   $track->(\$ref, $depth || 10, 1);
   $buf
}

=item @references = Devel::FindRef::find $ref

Return arrayrefs that contain [$message, $ref] pairs. The message
describes what kind of reference was found and the C<$ref> is the
reference itself, which can be omitted if C<find> decided to end the
search. The returned references are all weak references.

The C<track> function uses this to find references to the value you are
interested in and recurses on the returned references.

=cut

sub find($) {
   my ($about, $excl) = &find_;
   my %excl = map +($_ => undef), @$excl;
   grep !exists $excl{$_->[1] + 0}, @$about
}

=item $ref = Devel::FindRef::ptr2ref $integer

Sometimes you know (from debugging output) the address of a perl scalar
you are interested in (e.g. C<HASH(0x176ff70)>). This function can be used
to turn the address into a reference to that scalar. It is quite safe to
call on valid addresses, but extremely dangerous to call on invalid ones.

   # we know that HASH(0x176ff70) exists, so turn it into a hashref:
   my $ref_to_hash = Devel::FindRef::ptr2ref 0x176ff70;

=back

=head1 AUTHOR

Marc Lehmann <pcg@goof.com>.

=head1 BUGS

Only code values, arrays, hashes, scalars and magic are being looked at.

This is a quick hack only.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Marc Lehmann.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

1

