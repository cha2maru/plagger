package Plagger::Plugin::Store::Fastladder;
use strict;
use warnings;
use base qw/Plagger::Plugin/;

our $VERSION = '0.01';

__PACKAGE__->mk_accessors(qw/schema me/);

use Plagger::UserAgent;
use Plagger::Plugin::Store::Fastladder::Schema::Loader;

sub register {
    my ($self, $c) = @_;

    $self->{schema} = Plagger::Plugin::Store::Fastladder::Schema::Loader->new(
        $self->conf->{connect_info},
        { time_zone => $self->conf->{timezone} || $c->conf->{timezone} || 'local' },
    );

    $self->{me} = $self->rs('Members')->find($self->conf->{member_id})
        or $c->error(qq|can't find fastladder user member_id: "@{[ $self->conf->{member_id} ]}"|);

    if ($self->conf->{fetch_favicon}) {
        eval q{
            use HTML::TreeBuilder;
            use Imager 0.60;
        };
        if ($@) {
            $c->log(debug => $@);
            $c->log(warn => 'turn off fetch_favicon feature: it requires Imager 0.60');
            $self->conf->{fetch_favicon} = 0;
        }
    }

    $c->register_hook( $self, 'publish.feed' => \&store );
}

sub rs {
    my $self = shift;
    $self->schema->resultset(@_);
}

sub store {
    my ($self, $c, $args) = @_;

    my $me   = $self->me;
    my $now  = Plagger::Date->now;

    # truncate feedlink to fit database varchar(255)
    # FIXME: but this may cause some problems on crawler
    my $feedlink = substr($args->{feed}->url || $args->{feed}->id, 0, 255);
    my $feed = $self->rs('Feeds')->find_or_new({ feedlink => $feedlink });

    # update feed
    $feed->set_columns({
        link        => $args->{feed}->link || $args->{feed}->id,
        title       => $args->{feed}->title || '',
        description => $args->{feed}->description || '',
    });
    $feed->updated_on( $args->{feed}->updated || $now );
    $feed->created_on( $now ) unless $feed->in_storage;
    $feed->insert_or_update;

    # fetch favicon
    if ($self->conf->{fetch_favicon} and my $icon = $self->fetch_favicon($c, $feed->link)) {
        my $favicon = $self->rs('Favicons')->find_or_new({ feed_id => $feed->id });
        $favicon->image( $icon );
        $favicon->insert_or_update;
    }

    # subscribe
    my $subs = $me->subscriptions({ feed_id => $feed->id });
    if ($subs->count == 0) {
        $me->add_to_subscriptions({
            feed_id    => $feed->id,
            created_on => $now,
            updated_on => $now,
        });
    }

    # setting rate
    if ($self->conf->{sync_rate}) {
        my $sub  = $subs->first;
        my $rate = $args->{feed}->meta->{rate};
        if (defined $rate) {
            $c->log( debug => "Setting rate $rate to " . $feed->link);
            $sub->update({ rate => $rate }) unless $sub->rate == $rate;
        }
    }

    # update items
    for my $entry (@{ $args->{feed}->entries }) {
        
        my $item = $self->rs('Items')->find_or_new({
            feed_id => $feed->id,
            link    => $entry->permalink || $entry->link,
        });

        $item->set_columns({
            title          => $entry->title || '',
            body           => $entry->body,
            author         => $entry->author,
            category       => join(', ', @{$entry->tags}) || undef,
            digest         => $entry->digest,
            enclosure      => $entry->has_enclosure ? $entry->enclosure->url : undef,
            enclosure_type => $entry->has_enclosure ? $entry->enclosure->type : undef,
        });
#        $item->created_on( $entry->date || $now );
#        $item->modified_on( $entry->date || $now );
#        $item->stored_on( $now );
#        $item->updated_on( $now ) if $item->is_changed;
#        if ($item->is_column_changed('digest')) {
        if (!$item->in_storage || $item->is_column_changed('digest')) {
            $item->created_on( $entry->date || $now ) if !$item->in_storage;
            $item->modified_on( $entry->date || $item->created_on );
            $item->stored_on( $now );
            $item->updated_on( $now );
            my $subs = $me->subscriptions({ feed_id => $feed->id })->first;
            $subs->update({ has_unread => ref($self->schema->storage) =~ /SQLite/ ? 'true' : \'true' }); # XXX
            $item->insert_or_update;
         }
#        $item->insert_or_update;
    }

    # update status
    my $status = $self->rs('CrawlStatuses')->find_or_new({ feed_id => $feed->id });
    $status->http_status(200);
    $status->crawled_on( $now );
    $status->created_on( $now ) unless $status->in_storage;
    $status->updated_on( $now ) if $status->is_changed;
    $status->insert_or_update;
}

sub fetch_favicon {
    my ($self, $c, $url) = @_;

    $c->log( debug => "fetching favicon on $url" );

    my $ua  = Plagger::UserAgent->new;
    my $res = $ua->fetch($url);

    my $icon;
    if ($res->is_success) {
        my $tree = HTML::TreeBuilder->new;
        $tree->parse($res->content);
        $tree->eof;

        my @icons = $tree->look_down(
            _tag => 'link',
            rel  => qr/shortcut icon/i,
        );

        for my $icon_link (map { $_->attr('href') } @icons) {
            my $res = $ua->fetch($icon_link);
            if ($res->is_success) {
                $icon = $res->content;
                last;
            }
        }

        $tree->delete;
    }

    unless ($icon) {
        my $icon_link = URI->new($url);
        $icon_link->path('/favicon.ico');

        my $res = $ua->fetch($icon_link);
        $icon = $res->content if $res->is_success;
    }

    if ($icon) {
        my $imager = Imager->new;
        $imager->read( data => $icon ) or return;

        unless ($imager->getwidth == 16 and $imager->getheight == 16) {
            $imager = $imager->scale( xpixels => 16, ypixels => 16, type => 'nonprop' );
        }

        $imager->write( data => \my $png, type => 'png' )
            or $c->log( debug => 'image write error: ' . Imager->errstr );

        return $png;
    }

    return;
}

=head1 NAME

Plagger::Plugin::Store::Fastladder - Store feeds in Fastladder DB

=head1 SYNOPSIS

SQLite:

  - module: Store::Fastladder
    config:
      connect_info:
        - dbi:SQLite:/home/typester/dev/fastladder/fastladder/db/development.sqlite3
        - on_connect_do:
            - PRAGMA default_synchronous = OFF
      member_id: 1


MySQL:

  - module: Store::Fastladder
    config:
      connect_info:
        - dbi:mysql:fastladder
        - root
        - on_connect_do:
            - SET NAMES utf8
      member_id: 1

=head1 CONFIGURATION

=head2 connect_info

DBIx::Class connect_info.

=head2 member_id

your fastladder id: primary key of fastladder members table

=head2 fetch_favicon

if set this to true value, crawler fetch favicon. (default: 0)

=head2 sync_rate

if set this to true value, crawler automatically sync feed's rate from its meta info.

You might want to use this with Subscription::Livedoor.

=head1 AUTHOR

Daisuke Murase <typester@cpan.org>

=cut

1;


