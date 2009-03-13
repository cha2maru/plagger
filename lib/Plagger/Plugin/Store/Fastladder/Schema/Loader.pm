package Plagger::Plugin::Store::Fastladder::Schema::Loader;
use strict;
use warnings;
use Carp;

{
    package # hide from PAUSE
        Plagger::Plugin::Store::Fastladder::Schema;
    require DBIx::Class::Schema::Loader;
    use base qw/DBIx::Class::Schema::Loader/;

    __PACKAGE__->loader_options(
        exclude => qr/^schema_info$/,
    );
}

sub new {
    my ($class, $connect_info, $options) = @_;

    my $schema = Plagger::Plugin::Store::Fastladder::Schema->connect(@$connect_info);
    croak "cannot load schema info" unless $schema->sources;

    # setup relationships
    my $members        = 'Plagger::Plugin::Store::Fastladder::Schema::Members';
    my $feeds          = 'Plagger::Plugin::Store::Fastladder::Schema::Feeds';
    my $folders        = 'Plagger::Plugin::Store::Fastladder::Schema::Folders';
    my $subscriptions  = 'Plagger::Plugin::Store::Fastladder::Schema::Subscriptions';
    my $crawl_statuses = 'Plagger::Plugin::Store::Fastladder::Schema::CrawlStatuses';
    my $items          = 'Plagger::Plugin::Store::Fastladder::Schema::Items';
    my $pins           = 'Plagger::Plugin::Store::Fastladder::Schema::Pins';
    my $favicons       = 'Plagger::Plugin::Store::Fastladder::Schema::Favicons';

    $members->has_many( folders => $folders, 'member_id' );
    $members->has_many( subscriptions => $subscriptions, 'member_id' );
    $members->has_many( pins => $pins, 'member_id' );

    $feeds->has_many( subscriptions => $subscriptions, 'feed_id' );
    $feeds->has_many( crawl_statuses => $crawl_statuses, 'feed_id' );
    $feeds->has_many( items => $items, 'feed_id' );
    $feeds->has_many( favicons => $favicons, 'feed_id' );

    $folders->belongs_to( member => $members, 'member_id');
    $folders->has_many( subscriptions => $subscriptions, 'folder_id' );

    $subscriptions->belongs_to( member => $members, 'member_id');
    $subscriptions->belongs_to( folder => $folders, 'folder_id');
    $subscriptions->belongs_to( feed => $feeds, 'feed_id');

    $crawl_statuses->belongs_to( feed => $feeds, 'feed_id' );

    $items->belongs_to( feed => $feeds, 'feed_id' );

    $pins->belongs_to( member => $members, 'member_id' );

    $favicons->belongs_to( feed => $feeds, 'feed_id' );

    # XXX: setup datetime inflate manually
    # InflateColumn::DateTime doesn't treat time_zone when it used with Schema::Loader?
    my $time_zone    = $options->{time_zone};
    my $parser_class = $schema->storage->datetime_parser;

    for my $source (map { $schema->source($_) } $schema->sources) {
        my $class = $schema->class($source->source_name);

        for my $column ($source->columns) {
            my $info = $source->column_info($column);
            next unless defined $info->{data_type};

            my $type = lc $info->{data_type};
            $type = 'datetime' if $type =~ /^timestamp/;
            next unless $type eq 'datetime' || $type eq 'date';

            my ($parse, $format) = ("parse_$type", "format_$type");
            $class->inflate_column(
                $column => {
                    inflate => sub {
                        my $dt = $parser_class->$parse(shift);
                        $dt->set_time_zone($time_zone) if $time_zone;
                        $dt;
                    },
                    deflate => sub {
                        my $dt = shift;
                        $dt->set_time_zone($time_zone) if $time_zone;
                        $parser_class->$format($dt);
                    },
                },
            );
        }
    }

    $schema;
}

1;
