#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use WWW::TheMovieDB;
use Mediainfo;
use JSON -support_by_pp;
use File::Basename;
use File::Path;
use File::Fetch;
use Cwd;

if ($#ARGV != 0) {
	print "Usage: movietags.pl <movie file>\n";
	exit;
}

######################################################################
# Edit these variables if needed.
######################################################################
my $api_key = "6746566f020dc17b63a1f7e9bd7843e8"; # TMDB api key, register an account on www.themoviedb.org to get your own.
my $mp4tagger = "MP4Tagger"; # Define the location of the MP4Tagger binary
my $debug = 0; # Set to 1 if you want to enable debugging in the script output.
my $verbose = 1; # Set to 1 if you want to enable script output, 0 to disable.
my $automate = 0; # Set to 1 if you want to disable interactivity in the script.
my $logfile = "/Users/cade/movietags.log"; # Define location of log file for error capture.
######################################################################
# DO NOT EDIT ANYTHING BLEOW THIS LINE.
######################################################################

# Determine the Title of the movie from the filename. 
my $file = $ARGV[0];
my $name;
my $date;
my ($filename, $directories) = fileparse("$file");
if ($filename =~ m/\([0-9]{4,}\)/) {
	($name,$date) = split('\s+\(', $filename);
	if (!$date) {
		($name,$date) = split('\(', $filename);
	}
} else {
	$name = $filename;
	$name =~ s/.m4v//g;
}
if ($name =~ m/[A-Z0-9a-z]\s+-\s+[A-Z0-9a-z]/) {
	$name =~ s/\s+-\s+/\ /g;
} elsif ($name =~ m/[A-Z0-9a-z]\s+-\s+\./) {
	$name =~ s/[A-Z0-9a-z]\s+-\s+\.//g;
}
$name =~ s/[Uu]nrated//g;

my $release;
if ($date) {
	($release) = split('\)', $date);
}
my @command;
my $tmdb_id;
my %title_hash = ();
my @titles;
my $index = 0;
my $movie;
my $releases;
my $casts;
my @closeTitles;
my @cast;
my @director;
my @writers;
my @composer;
my @producer;
my @genres;
my $mpaa_rating;
my $list;
my $json;
my $json_text;
my $HD;
my $mediainfo_url = "http://mediaarea.net/en/MediaInfo/Download/Mac_OS";

if (!`which mediainfo`) {
	print "Mediainfo binary isn't installed. Please download and install the mediainfo cli binary.\n";
	print "Mediainfo is required to determine if the file is HD or SD.\n";
	`open $mediainfo_url`;
	exit;
}

my $api = new WWW::TheMovieDB({
	'key'		=>	$api_key,
	'language'	=>	'en',
	'version'	=>	'3',
	'type'		=>	'json',
	'uri'		=>	'http://api.themoviedb.org'
});

# Search for the movie in TMDB.org
if ($release) {
	$list = $api->Search::movie({
		'query' => "$name",
		'year' => "$release"
	});
	$json = new JSON;
	$json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($list);
} else {
	$list = $api->Search::movie({
		'query' => "$name"
	});
	$json = new JSON;
	$json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($list);
}

if (!@{$json_text->{results}}) {
	$list = $api->Search::movie({
		'query' => "$name"
	});
	$json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($list);
}

if (!@{$json_text->{results}}) {
	print "No title found by that name.\n";
	print "Filename: " . $file . "\n";
	exit(1);
}

# Process through the list of movies returned in the search and try to match based on file Title and Year. If no match is found
# then revert to user input. 
my $match = "0";
foreach my $title (@{$json_text->{results}}) {
	if ($debug) {
		print $name . "\n";
		print $title->{title} . "\n";
	}
	push @titles, {title => $title->{title}, release_date => $title->{release_date}, tmdb_id => $title->{id}};
	if ($title->{title} =~ m/\//) {
		$title->{title} =~ s/[#\-%\$*+():\/]/\ /g;
	} else {
		$title->{title} =~ s/[#\-%\$*+():]./\ /g;	
	}
	$name =~ s/[#\-%\$*+():]./\ /g;
	if ($title->{title} =~ m/[ \t]{2,}/) {
		$title->{title} =~ s/[ \t]{2,}/ /g;
	}
	if ($debug) {
		print $title->{title} . "\n";
		print $name . "\n";
		print $release . "\n";
		print $title->{release_date} . "\n";
	}
	if ($title->{title} =~ "&" && $name !~ "&") {
		$title->{title} =~ s/\&/and/g;
	} elsif ($name =~ "&" && $title->{title} !~ "&") {
		$name =~ s/\&/and/g;
	}
	if ($release) {
		if (lc($title->{title}) eq lc($name) && $title->{release_date} =~ "$release") {
			$tmdb_id = $title->{id};
			$match++;
		}
	} else {
		if (lc($title->{title}) eq lc($name)) {
			$tmdb_id = $title->{id};
			$match++;
		}
	}
}

if (!$automate) {
	if (!$tmdb_id || $match > "1") {
		if ($release) {
			my $min_year = ($release - 2);
			my $max_year = ($release + 2);
			foreach my $cleanup (@titles) {
				if ($cleanup->{release_date} ge "$min_year" && $cleanup->{release_date} le "$max_year") {
					push @closeTitles, {title => $cleanup->{title}, release_date => $cleanup->{release_date}, tmdb_id => $cleanup->{tmdb_id}};
				}
			}
		} else {
			foreach my $cleanup (@titles) {
				push @closeTitles, {title => $cleanup->{title}, release_date => $cleanup->{release_date}, tmdb_id => $cleanup->{tmdb_id}};
			}
		}
		
		# If there is only 1 result just assume that it is the one we want.
		if (scalar @closeTitles eq "1") {
			$tmdb_id = $closeTitles[0]->{tmdb_id};
		} else {
			print "\nFilename: $file\n\n";
			print "Please select a match from the list below:\n\n";
			foreach my $title (@closeTitles) {
				print "$index) " . $title->{title} . " released on " . $title->{release_date} . "\n";
				$index++;
			}
			print "\n";
			print "Which would you like to select? ";
			my $input = <STDIN>;
			$tmdb_id = $titles[$input]->{tmdb_id};
		}
	}
} 

if ($match gt "1" && $automate eq "1") {
	print "Unable to tag $file\n";
	open (FILE, ">>$logfile") or die "Cannot open $logfile";
	print FILE "Unable to automatically tag file $file\n";
	close(FILE);
	exit(1);
}

# Lookup the movie information on TMDB.org based on the tmdb_id number.
if ($tmdb_id) {
	$movie = $api->Movies::info({
		'movie_id' => $tmdb_id
	});
	$releases = $api->Movies::releases({
		'movie_id' => $tmdb_id
	});
	$casts = $api->Movies::casts({
		'movie_id' => $tmdb_id
	});
} else {
	print "Unable to lookup the movie, no TMDB ID was found.\n";
	exit(1);
}

# Begin parsing out the movie tagging information.
my $movie_info = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($movie);
my $genre = $movie_info->{genres};
my $imdb_id = $movie_info->{imdb_id};
my $title = $movie_info->{title};
my $release_date = $movie_info->{release_date};
my $tagline = $movie_info->{tagline};

# Populate the cast and crew information
my $cast_info = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($casts);
foreach my $c (@{$cast_info->{cast}}) {
	push (@cast, $c->{name});
}
my $cast_list = join(',', @cast);
foreach my $crew (@{$cast_info->{crew}}) {
	if ($crew->{job} eq "Director") {
		push (@director, $crew->{name});
	} elsif ($crew->{job} eq "Screenplay") {
		push (@writers, $crew->{name});
	} elsif ($crew->{job} eq "Original Music Composer") {
		push (@composer, $crew->{name});
	} elsif ($crew->{job} eq "Producer") {
		push (@producer, $crew->{name});
	}
}
my $director = join(',', @director);
my $writer = join(',', @writers);
my $composer = join(',', @composer);
my $producer = join(',', @producer);

foreach my $g (@{$genre}) {
	push(@genres, $g->{name});
}
my $genres = join(",", @genres);

# Manipulate the movie description to enable proper tagging.
$movie_info->{overview} =~ s/\"/\\\"/g;
$movie_info->{overview} =~ s/\&amp\;/\&/g;
$movie_info->{overview} =~ s/\;/\\\;/g;

my $overview = $movie_info->{overview};
my $art = 'http://d3gtl9l2a4fn1j.cloudfront.net/t/p/original' . $movie_info->{poster_path};
my $ff = File::Fetch->new(uri => "$art");
my $where = $ff->fetch() or die $ff->error;
my $artwork = $ff->output_file;
my $runtime = $movie_info->{runtime};
my $movie_releases = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($releases);
foreach my $country (@{$movie_releases->{countries}}) {
	if ($country->{iso_3166_1} eq "US") {
		$mpaa_rating = $country->{certification};
	}	
}

my $kind = "Movie";
# If the mpaa_rating comes back null then assign an Unrated tag to the movie. 
# Not ideal but works for now. 
if (!$mpaa_rating || $mpaa_rating eq "NR") {
	$mpaa_rating = "Unrated";
}

# Determine if the file your tagging is HD or SD.
my $media_info = new Mediainfo("filename" => "$file");

if ($media_info->{width} < "960") {
	$HD = "no";
} else {
	$HD = "yes";
}

# Output on screen the values that will be tagged. 
if ($verbose && $automate != "1") {
	print "\n************************************************************************\n";
	print "\n";
	print "Title:\t\t$title\n";
	print "IMDB ID:\t$imdb_id\n";
	print "Release Date:\t$release_date\n";
	print "Genre:\t\t$genres\n";
	print "Tagline:\t$tagline\n";
	print "Overview:\t$overview\n";
	print "Artwork:\t" . $artwork . "\n";
	print "Runtime:\t$runtime mins.\n";
	print "High Def:\t$HD\n";
	print "Kind:\t\t$kind\n";
	print "Rating:\t\t$mpaa_rating\n";
	print "Cast:\t\t$cast_list\n";
	print "Director:\t$director\n";
	print "Writer:\t\t$writer\n";
	print "Composer:\t$composer\n";
	print "Producer:\t$producer\n";
	print "\n";
	print "************************************************************************\n";
}

# Generate the actual MP4Tagger command. 
$file =~ s/\ /\\\ /g;
$file =~ s/\'/\\\'/g;
$file =~ s/\(/\\\(/g;
$file =~ s/\)/\\\)/g;
$file =~ s/\,/\\\,/g;
$file =~ s/\:/\\\:/g;
$file =~ s/\;/\\\;/g;
$file =~ s/\&/\\\&/g;
push(@command, "$mp4tagger");
push(@command, "-i $file");
push(@command, "--media_kind \"$kind\"");
if ($artwork) {
	push(@command, "--artwork \"$artwork\"");
} else {
	print "\n\n\tWARNING: THIS FILE WILL NOT CONTAIN ANY COVER ART, NO IMAGE FILE WAS FOUND!\n\n";
}
push(@command, "--is_hd_video $HD");
push(@command, "--name \"$title\"");
push(@command, "--release_date \"$release_date\"");
if ($mpaa_rating) {
	push(@command, "--rating \"$mpaa_rating\"");
}
push(@command, "--description \"$overview\"");
if ($cast_list) {
	push(@command, "--cast \"$cast_list\"");
}
if ($director) {
	push(@command, "--director \"$director\"");
}
if ($writer) {
	push(@command, "--screenwriters \"$writer\"");
}
if ($composer) {
	push(@command, "--composer \"$composer\"");
}
if ($producer) {
	push(@command, "--producer \"$producer\"");
}
if ($genres) {
	push(@command, "--genre \"$genres\"");
}

system("@command") == 0
	or die "system @command failed: $?";

# Cleanup after ourselves, removing downloaded artwork.	
system("rm -f $artwork") == 0
	or die "system rm failed: $?";

# Set the files modification date to match the release date for sorting purposes. 
$release_date =~ s/-//g;
$release_date = $release_date . "1200";
system ("touch -t $release_date $file") == 0
	or die "touch failed: $?";