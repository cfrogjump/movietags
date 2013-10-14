#!/usr/bin/env perl

#use strict;
use warnings;
use Data::Dumper;
use WWW::TheMovieDB;
use JSON -support_by_pp;
use File::Basename;
use File::Path;
use File::Fetch;
use Cwd;

if ($#ARGV != 0) {
	print "Usage: movietags.pl <movie file>\n";
	print "Movie files must be named <movie name> (release year).<ext>\n";
	print "ex. Aladdin (1992).m4v\n";
	exit;
}
######################################################################
# Edit these variables if needed.
######################################################################
my $HD = "yes"; # Assumption that the file you're tagging is HD, set to no if it is not. 
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
my ($filename, $directories) = fileparse("$file");
my ($name,$date) = split('\s+\(', $filename);
if (!$date) {
	($name,$date) = split('\(', $filename);
}

if ($name =~ m/[A-Z0-9a-z]\s+-\s+[A-Z0-9a-z]/) {
	$name =~ s/\s+-\s+/\ /g;
} elsif ($name =~ m/[A-Z0-9a-z]\s+-\s+\./) {
	$name =~ s/[A-Z0-9a-z]\s+-\s+\.//g;
}

$name =~ s/[Uu]nrated//g;

if (!$date) {
	print "Movie files must be named <movie name> (<release year>).<ext>\n";
	print "Please rename the file to match the naming convention.\n";
	print "Filename: $file\n";
	exit;
}
my ($release) = split('\)', $date);
my @command;
my $tmdb_id;
my %title_hash = ();
my @titles;
my $index = 0;
my $movie;
my $releases;

my $api = new WWW::TheMovieDB({
	'key'		=>	$api_key,
	'language'	=>	'en',
	'version'	=>	'3',
	'type'		=>	'json',
	'uri'		=>	'http://api.themoviedb.org'
});

# Search for the movie in TMDB.org
my $list = $api->Search::movie({
	'query' => "$name",
	'year' => "$release"
});

my $json = new JSON;
my $json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($list);

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
	}
#	print "Title: " . lc($title->{title}) . "\n";
#	print "Name: " . lc($name) . "\n";
	if (lc($title->{title}) eq lc($name) && $title->{release_date} =~ "$release") {
		$tmdb_id = $title->{id};
		$match++;
	}

}

print "Match: $match\n";
if (!$automate) {
	if (!$tmdb_id || $match > "1") {
		$min_year = ($release - 2);
		$max_year = ($release + 2);
		foreach my $cleanup (@titles) {
			if ($cleanup->{release_date} ge "$min_year" && $cleanup->{release_date} le "$max_year") {
				push @closeTitles, {title => $cleanup->{title}, release_date => $cleanup->{release_date}, tmdb_id => $cleanup->{tmdb_id}};
			}
		}
#		print Dumper(@titles);
		if (scalar @closeTitles eq "1") {
#			print Dumper(@closeTitles);
			$tmdb_id = $closeTitles[0]->{tmdb_id};
		} else {
		
#		print Dumper(@closeTitles);
			print "\nFilename: $file\n\n";
			print "Please select a number from the list below:\n\n";
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
} elsif ($automate) {
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
} else {
	print "Unable to lookup the movie, no TMDB ID was found.\n";
	exit(1);
}

# Begin parsing out the movie tagging information.
my $movie_info = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($movie);
my $genre = $movie_info->{genres};
#my $genres = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($genre);
my $imdb_id = $movie_info->{imdb_id};
my $title = $movie_info->{title};
my $release_date = $movie_info->{release_date};
my $tagline = $movie_info->{tagline};

#print Dumper($genre);
#foreach my $g (@genre) {
#	print $g->{name} . "\n";
#}

#print Dumper(@genre);
#for my $genres ( $genre->{name} ) {
#	print $genres . "\n";
##	$Genre .= $genres . ",";
#}
#$Genre =~ s/,$//g;
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

# Output on screen the values that will be tagged. 
if ($verbose) {
	print "\n************************************************************************\n";
	print "\n";
#	print "Genre:\t\t$Genre\n";
	print "Title:\t\t$title\n";
	print "IMDB ID:\t$imdb_id\n";
	print "Release Date:\t$release_date\n";
	print "Tagline:\t$tagline\n";
	print "Overview:\t$overview\n";
	print "Artwork:\t" . $artwork . "\n";
	print "Runtime:\t$runtime mins.\n";
	print "Kind:\t\t$kind\n";
	print "Rating:\t\t$mpaa_rating\n";
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