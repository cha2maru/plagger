package Plagger::Plugin::CustomFeed::Folder;
use strict;
use base qw( Plagger::Plugin );

our $VERSION = 0.03;

use Plagger::Date;
use URI::Escape ();
use URI::file;
use File::Glob ':glob';
use File::stat;
use Fcntl ':mode';
use Encode;

sub register {
	my ($self, $context) = @_;
	$context->register_hook(
		$self,
		'subscription.load' => \&load,
	);  
}   

sub load {
	my ($self, $context) = @_;
	
	my $feed = Plagger::Feed->new;

	$feed->aggregator(sub { $self->aggregate(@_) });
	$context->subscription->add($feed);
}

sub aggregate {
	my ($self, $context, $args) = @_;

	my $feed = $self->conf->{feed};
	$feed = [ $feed ] unless ref $feed;
#	my $encoding = $self->conf->{encoding};
	$self->conf->{encoding} = 'cp932' undef $self->conf->{encoding};

	for my $config (@{ $feed }) {
		if (!ref($config)) {
 		$config = { url => $config };
		}

		Encode::_utf8_off($config->{url});

		my $title = $config->{url} || $config->{dir} || $config->{file};
		$context->log( info => 'Getting folder ' . $title );

		my $path;
		if (my $url = $config->{url}) {
			$path = URI->new($url)->file();
			$path =~ s/\/\z/\/\*/;
		} elsif ($path = ($config->{dir} || $config->{file})) {
			if ($config->{dir} || $path =~ /\/\z/) {
				$path =~ s/\/\z//;
				$path .= "/*";
			}
		} else {
			$context->error("path is missing");
		}

		my ($volume, $directories, $file) = File::Spec->splitpath($path);
		my $link = URI::file->new(File::Spec->catdir($volume, $directories) . "/")->as_string;

		my @files = bsd_glob($path);

		unless (@files) {
			$context->log(warn => "Can't list $path .");
			next;
		}

		my $file_infos = $self->file_infos($context, @files);

		my $feed = Plagger::Feed->new;

		$feed->title($title);
		$feed->link($link);

		for my $file_info (@$file_infos) {
			next if ($config->{dir_only} && !$file_info->{is_dir});
			next if ($config->{skip_hidden} && $file_info->{name} =~ /\A\./);

			my $entry = Plagger::Entry->new;
			$entry->title($self->convert($file_info->{name}));
#			$entry->id($self->convert($file_info->{path}));
			$entry->link($file_info->{uri});
			$entry->date(Plagger::Date->from_epoch($file_info->{mtime}));
			$entry->author($self->convert($file_info->{author}));
#			$entry->body($self->convert($file_info->{path}));

			$feed->add_entry($entry);
		}

		$context->update->add($feed);
	}
}

sub file_infos {
	my ($self, $context, @files) = @_;

	my $file_infos;

	for my $path (@files) {
		next unless (-e $path);
		my ($volume, $directories, $file) = File::Spec->splitpath($path);
		my $debuglog = $self->convert($file);
		$context->log(debug => "Processing $debuglog.");
		$debuglog = $self->{conf}->{encoding};
		$context->log(debug => "Encode $debuglog.");

		my $file_info = {
			name  => $file,
			path  => $path,
			uri   => URI::file->new($path)->as_string,
		};

		my $stat = stat($path);
		$file_info->{mtime} = $stat->mtime || 0;
		$file_info->{author} = eval{getpwuid($stat->uid)} || "";

		if (-d $path) {
			$file_info->{is_dir} = 1;
			$file_info->{uri} .= "/";
		}else{
			$file_info->{is_dir} = 0;
		}

		push @$file_infos, $file_info;
	}

	return $file_infos;
}

sub convert {
  my ($self, $str) = @_;
#  my $encoded = $self->{config}->{encoding} || 'cp932';
  Encode::from_to($str, $self->{config}->{encoding} , 'utf8') unless utf8::is_utf8($str);
  return $str;
}


1;

__END__

=head1 NAME

Plagger::Plugin::CustomFeed::Folder - Feed Folder

=head1 SYNOPSIS

plugins:
  - module: CustomFeed::Folder
    config:
      feed:
        - dir: C:/xanalog/dailydata/
        - file: C:/xanalog/dailydata/*.dat
        - url: file:///C:/xanalog/dailydata/*.dat
        - url: file:///C:/xanalog/dailydata/
        - file:///C:/xanalog/dailydata/
      - encoding: cp932

=head1 AUTHOR

Hidehiko Kawauchi

=head1 SEE ALSO

L<Plagger>

=cut
