package Plagger::Plugin::Filter::LinkEnclosure;
use strict;
use base qw( Plagger::Plugin );

use Cwd;
use File::Spec;
use File::Path;
use Text::Kakasi;
use URI::Escape ();
use URI::file;

sub register {
    my($self, $context) = @_;
    $context->register_hook(
        $self,
        'update.entry.fixup' => \&filter,
    );
}

sub init {
    my $self = shift;
    $self->SUPER::init(@_);

    defined $self->conf->{dir} or Plagger->context->error("config 'dir' is not set.");
    # XXX make it Plagger::Util function
    if ($self->conf->{dir} =~ /^[a-zA-Z]/ && $self->conf->{dir} !~ /:/) {
        $self->conf->{dir} = File::Spec->catfile( Cwd::cwd, $self->conf->{dir} );
    }
    
    unless (-e $self->conf->{dir} && -d _) {
        Plagger->context->log(warn => $self->conf->{dir} . " does not exist. Creating");
        mkpath $self->conf->{dir};
    }
}

sub filter {
    my($self, $context, $args) = @_;
    my $kakasi = Text::Kakasi->new('-Ka','-Ja','-Ha','-ka','-ja','-ga','-Ea','-iutf8','-outf8');
    my $ua = Plagger::UserAgent->new;

    for my $enclosure ($args->{entry}->enclosures) {
        my $feed_dir = File::Spec->catfile($self->conf->{dir}, $args->{feed}->id_safe);
        unless (-e $feed_dir && -d _) {
            $context->log(info => "mkdir $feed_dir");
            mkdir $feed_dir, 0777;
        }

        my $filename = $enclosure->filename;
        my $kakasi_filename = $kakasi->get($filename);
        $kakasi_filename =~ s/[^\w\.]//g;
        Encode::_utf8_off($filename);
        my $path = File::Spec->catfile($feed_dir, $kakasi_filename);
        $context->log(info => "Link " . $enclosure->url . " to " . $path);

        my $src_path = URI->new($enclosure->local_path)->file();

        if ( $^O eq 'MSWin32' )
        {
            my $ret = system "ln",$src_path,$path;
            $context->log(debug => "ln Return Code is " . $ret);
        } else {
            symlink($src_path,$path);
        }

        if (-e $path)
        {
            $enclosure->local_path(URI::file->new($path)->as_string); # set to be used in later plugins
        } else {
            $enclosure->local_path(URI::file->new($src_path)->as_string);
        }
    }
    $kakasi->close_kanwadict();
}

1;

__END__

=head1 NAME

Plagger::Plugin::Filter::LinkEnclosure - Symlink enclosure(s) in entry

=head1 SYNOPSIS

  - module: Filter::LinkEnclosure
    config:
      dir: /path/to/files

=head1 DESCRIPTION

This plugin symlink local enclosure files set for each entry.
(encrosure local_path)

=head1 CONFIG

=over 4

=item dir

Directory to store symlink enclosures. Required.

=back

=head1 AUTHOR

cha2maru(Ryo Suzuki)

=head1 SEE ALSO

L<Plagger>

=cut

