package Plagger::Plugin::Filter::EntryFullText::LDRFullFeed;
use strict;
use base qw( Plagger::Plugin::Filter::EntryFullText );

use Plagger::UserAgent;
use WebService::Wedata;

sub class_id { 
    my $self = shift;
    return ($self->conf->{impersonate})
        ? "Filter-EntryFullText"
        : $self->SUPER::class_id;
}

sub load_plugins {
    my $self = shift;
    $self->SUPER::load_plugins(@_);
    $self->load_plugin_siteinfo;
}

sub load_plugin_siteinfo {
    my $self = shift;
    
    my $siteinfo = $self->_siteinfo;
    
    if ($siteinfo) {
        Plagger->context->log(debug => "Loaded siteinfo");
    }
    else {
        Plagger->context->log(warn => "No siteinfo");
        return;
    }
    
    push @{ $self->{plugins} },
        map { Plagger::Plugin::Filter::EntryFullText::YAML->new($_) } 
        @{$siteinfo};
}

sub _siteinfo {
    my $self = shift;
   
    my $ua = Plagger::UserAgent->new;
    my $wedata = WebService::Wedata->new;
    $wedata->{ua} = $ua;
    
    my $i = 0;
    my %priority = qw/
        SBM 1000
        INDIVIDUAL 100
        IND 100
        SUBGENERAL 10
        SUB 10
        GENERAL 1
        GEN 1
    /;
    
    my @rules;
    my $db = $wedata->get_database('LDRFullFeed');
    for my $item (
        sort {
            $b->{data}->{priority} <=> $a->{data}->{priority}
        }
        grep {
            $_->{data}->{priority}
        }
        map {
            $_->{data}->{priority} ||= ($_->{data}->{type})
                ? $priority{$_->{data}->{type}}
                : 0; $_;
        } @{$db->get_items}
    ) {
        Plagger->context->log(
            debug => sprintf(
                'siteinfo: %s %s %s',
                $item->{data}->{url},
                $item->{data}->{xpath},
                $item->{data}->{type}
            )
        );
        push @rules, {
            handle => $item->{data}->{url},
            extract_xpath => {
                body => $item->{data}->{xpath}
            },
        };
    }

    return \@rules;
}


1;

__END__

=head1 NAME

Plagger::Plugin::Filter::EntryFullText::LDRFullFeed - Upgrade feeds to fulltext class by using LDRFullFeed siteinfo

=head1 SYNOPSIS

  - module: Filter::EntryFullText::LDRFullFeed
    config:
      force_upgrade: 1

=head1 DESCRIPTION

=head1 CONFIG

=over 4

=item impersonate

=item store_html_on_failure

=item force_upgrade

=back

=head1 AUTHOR

fuba

=head1 SEE ALSO

L<Plagger>, L<Plagger::Plugin::Filter::EntryFullText>

