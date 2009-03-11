package Plagger::Plugin::Subscription::GoogleReader;
use strict;
use base qw( Plagger::Plugin );

use WebService::Google::Reader;

sub plugin_id {
    my $self = shift;
    $self->class_id . '-' . $self->conf->{username};
}

sub register {
    my($self, $context) = @_;

    $self->init_reader;
    $context->register_hook(
        $self,
        'subscription.load' => \&notifier,
    );
}

sub init_reader {
    my $self = shift;

    unless (defined($self->conf->{username}) && defined($self->conf->{password})) {
        Plagger->context->error("username and/or password is missing");
    }
}

sub notifier {
    my($self, $context) = @_;

    $context->log(debug => "notifier");

    my $feed = Plagger::Feed->new;
    $feed->aggregator(sub { $self->sync(@_) });
    $context->subscription->add($feed);
}

sub sync {
    my($self, $context, $args) = @_;

    $context->log(debug => "sync");

    my $mark_read = $self->conf->{mark_read};
       $mark_read = 1 unless defined $mark_read;

    my $read_count = $self->conf->{read_count};
       $read_count = 10 unless defined $read_count;

    my $reader = WebService::Google::Reader->new(
        username => $self->conf->{username},
        password => $self->conf->{password},
    );
	unless ($reader) {
	    $context->log(error => "cannot login google reader: $!");
	    return;
	}

    my $unread = $reader->unread( count => $read_count );
    
    my $feed = Plagger::Feed->new;
    $feed->type('googleReader');
    $feed->title('googleReader');
    $feed->url('http://google.com/reader/');

    my @items = $unread->entries;
    for my $item (@items) {
        my $entry = Plagger::Entry->new;
        $context->log(debug => "title:" . $item->title);
        $context->log(debug => "href:" . $item->link()->href);

        $entry->title($item->title);
        $entry->author(defined $item->author ? $item->author : 'nobody');
        $entry->link($item->link()->href);
        # TODO support enclosure
        $entry->tags([ $item->{category} ]) if $item->{category};
        $entry->date( Plagger::Date->from_epoch($item->{modified_on}) )
            if $item->{modified_on};
        $entry->feed_link($feed->link);
        my $content = $item->content();
        if (defined $content) {
            $entry->body($content->body);
        } elsif (defined $item->summary) {
            $entry->body($item->summary);
        }
        $reader->state_entry($item, 'read') if ($mark_read);
        $feed->add_entry($entry);
    }
    $context->update->add($feed);
}

1;
__END__

=head1 NAME

Plagger::Plugin::Subscription::GoogleReader - Synchronize Google Reader with WebService::Google::Reader

=head1 SYNOPSIS

  - module: Subscription::GoogleReader
    config:
      username: your-google-id
      password: your-password
      read_count: 30
      mark_read: 1

=head1 DESCRIPTION

This plugin allows you to synchronize your subscription using Google Reader

=head1 CONFIGURATION

=over 4

=item username, password

Your username & password to use with Google Reader.

=item read_count

=item mark_read

C<mark_read> specifies whether this plugin I<marks as read> the items
you synchronize. With this option set to 0, you will get the
duplicated updates everytime you run Plagger, until you mark them
unread using Google Reader web interface.

=back

=head1 AUTHOR

Yasuyuki Hashimoto

=head1 SEE ALSO

L<Plagger>, L<Plagger::Plugin::Subscription::LivedoorReader>, L<WebService::Google::Reader>

=cut

