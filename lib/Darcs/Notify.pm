#!/usr/bin/perl
# Copyright (c) 2007-2009 David Caldwell,  All Rights Reserved. -*- perl -*-

package Darcs::Notify; use strict; use warnings;
our $VERSION = '1.0';
our @EXPORT = qw(darcs_notify);

use IPC::Run qw(run);
use Darcs::Inventory;
use Darcs::Inventory::Diff;
use Cwd;
use File::Basename;

sub darcs_notify(%) {
    my %option = @_;
    $option{repo}      ||= '.';
    $option{repo_name} ||= basename $option{repo} eq '.' ? cwd : $option{repo};
    $option{unpull}    ||= \&darcs_notify_unpull;
    $option{new}       ||= \&darcs_notify_new;

    mkdir "$option{repo}/_darcs/third-party";
    mkdir "$option{repo}/_darcs/third-party/darcs-notify";

    my $old_inventory = "$option{repo}/_darcs/third-party/darcs-notify-old-inventory";
    # http://www.mail-archive.com/darcs-users@darcs.net/msg01347.html
    $old_inventory = "$option{repo}/_darcs/third-party/darcs-notify/old-inventory" unless -f $old_inventory;

    my $pre  = Darcs::Inventory->load($old_inventory);
    my $post = Darcs::Inventory->new($option{repo}) or die "Couldn't get inventory from $option{repo}";

    my ($new, $unpull) = Darcs::Inventory::Diff::diff($pre, $post);

    system(qw"cp -f", $post->file, $old_inventory);
    if (!$pre) {
        warn "Not sending any patch notifications on first run.\n".
            "'echo > \"$old_inventory\"' and re-run darcs-notify if you want notifications for your current ".
            scalar $post->patches, " patches.\n";
        return;
    }

    $option{unpull}->(\%option, $unpull) if scalar @$unpull;
    $option{new}   ->(\%option, $new)    if scalar @$new;
}

use Mail::Send;
sub darcs_notify_unpull(\%$) {
    my ($option, $unpull) = @_;
    my @group = @{$option->{email}};
    my $msg = new Mail::Send Subject=>"[Unpulled patches]";
    $msg->to(@group);
    #$ENV{MAILADDRESS} = $p->author;
    $msg->set("Reply-To", @group);
    $msg->set("Content-Type", ' text/plain; charset="utf-8"');
    $msg->set("X-Darcs-Notify", $option->{repo_name});
    my $fh = $msg->open('smtp', Server=>$option->{smtp_server} || 'localhost') or die "$!";
    #my $fh = $msg->open('testfile') or die "$!";
    print $fh "Unpulled:\n\n";
    print $fh join "\n", map { $_->as_string } @$unpull;
    $fh->close or die "no mail!";
    print "Sent unpull mail to @group\n";
}

sub darcs_notify_new(\%$) {
    my ($option, $new) = @_;
    my @group = @{$option->{email}};
    # New patches each get their own email:
    foreach my $p (@$new) {
        my $blurb = $p->as_string;
        my ($diff, $diffstat, $error);
        run([qw(darcs diff -u --match), "hash ".$p->hash], '>', \$diff, '2>', \$error) or die "$error\n";
        run([qw(diffstat)], '<', \$diff, '>', \$diffstat, '2>', \$error) or die "$error\n";

        my $name = ($p->undo?"UNDO: ":"").$p->name;
        my $msg = new Mail::Send Subject=>$name;
        $msg->to(@group);
        $ENV{MAILADDRESS} = $p->author;
        $msg->set("Reply-To", @group);
        $msg->set("Content-Type", ' text/plain; charset="utf-8"');
        $msg->set("X-Darcs-Notify", $option->{repo_name});
        my $fh = $msg->open('smtp', Server=>$option->{smtp_server} || 'localhost') or die "$!";
        #my $fh = $msg->open('testfile') or die "$!";
        print $fh "$blurb\n";
        print $fh "$diffstat\n";
        print $fh "$diff\n";
        $fh->close or die "no mail!";
        print "Sent $name to @group\n";
    }
}

1;
__END__

=head1 NAME

Darcs::Notify - Send emails when a Darcs repository has patches added or removed

=head1 SYNOPSIS

 darcs_notify(smtp_server => "smtp.example.com",
              email => ["user1@example.com", "user2@example.com"],
              repo => "/path/to/my/repo");

=head1 DESCRIPTION

B<Darcs::Notify> compares the list of patches in a darcs repository
against a saved backup copy and sends emails about the changes. The
backup copy is stored in the file
F<_darcs/third-party/darcs-notify/old-inventory>.

=head1 FUNCTIONS

The following functions are exported from the B<Darcs::Notify>
module by default.

=over 4

=item B<C<darcs_notify(options)>>

This implements the B<Darcs::Notify> functionality. It accepts a
number of hash style options:

=over 4

=item B<repo> => "/path/to/my/repo"

Path to the base of the target darcs repository. Don't point to the
F<_darcs> directory, that will be added for you.

=item B<repo_name> => "my_repo"

By default C<&darcs_notify> will guess the name of the repo from the
path name. If you'd like to override its guess, pass in the repo_name
parameter.

=item B<new> => sub { ... }

=item B<unpull> => sub { ... }

You can override the standard email notification by passing a
subroutine ref to unpull or new. They both have the same interface:

 sub darcs_notify_unpull($$) {
     my ($option, $patches) = @_;
     ...
 }

$option is a reference to the option hash passed to L<darcs_notify>.

$patches is a reference to an array of L<Darcs::Inventory::Patch> objects.

=item B<email> => ["email@example.com", email2@example.com]

This is reference to an array of email addresses. This is used by the
default unpull and new patch notification routines.

=item B<smtp_server> => "localhost"

This is reference to an array of email addresses. This is used by the
default unpull and new patch notification routines. It defaults to
localhost if you do not pass the option.

=back

=back

=head1 SEE ALSO

L<darcs-notify>, L<Darcs::Inventory::Patch>, L<Darcs::Inventory>

=head1 COPYRIGHT

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

Copyright (C) 2007-2009 David Caldwell

=head1 AUTHOR

David Caldwell <david@porkrind.org>

=cut
