#!/usr/bin/perl
use utf8;

#--------------------------------------------------------------------
# precedence-dump.pl
#
# Standalone JSON serializer for precedence()/occurrence() (horascommon.pl).
# Given a date + hour + rubrical version, prints the winning office, its
# rank, and any commemoration as JSON on stdout, so the computation can be
# differentially tested against ports of the same logic (see traditional-
# prayer-app's precedence.ts).
#
# Usage: precedence-dump.pl --date=YYYY-MM-DD --hour=Laudes --version="Rubrics 1960 - 1960"

use POSIX;
use FindBin qw($Bin);
use CGI;
use CGI::Cookie;
use File::Basename;
use Time::Local;
use locale;
use Getopt::Long qw(GetOptions);
use JSON::PP qw(encode_json);

use lib "$Bin/..";
use DivinumOfficium::RunTimeOptions qw(check_version check_horas check_language);

# Globals written by occurrence()/concurrence()/precedence() (horascommon.pl).
our @dayname;
our $winner;
our $commemoratio;
our $scriptura;
our $commune;
our $communetype;
our $rank;
our $vespera;

our %winner;
our %commemoratio;
our %scriptura;
our %commune;
our $rule;
our $communerule;
our $duplex;

our $initia;
our $dayofweek;

# Globals read by precedence()/occurrence()/rankname() that we must supply,
# since there is no live CGI request to derive them from.
our ($hora, $version, $lang1, $lang2, $langfb, $dioecesis, $missa, $missanumber, $votive);
our ($datafolder, $htmlurl, $link, $visitedlink, $dialogbackground, $dialogfont, $border, $cookieexpire, $savefiles);

# Minimal require set proven to work standalone (outside a CGI request) by
# web/cgi-bin/admin/createTransferTables.pl, which calls precedence()
# exactly this way. Deliberately skips the rendering-only libraries
# (horas.pl, horasscripts.pl, specials.pl, altovadum.pl, horasjs.pl,
# officium_html.pl) that createTransferTables.pl also omits.
require "$Bin/../DivinumOfficium/SetupString.pl";
require "$Bin/../horas/horascommon.pl";    # precedence(), occurrence(), rankname()
require "$Bin/../DivinumOfficium/dialogcommon.pl";
require "$Bin/../horas/webdia.pl";
require "$Bin/../DivinumOfficium/setup.pl";
require "$Bin/../horas/specmatins.pl";
require "$Bin/../horas/monastic.pl";

our $q = new CGI;

my $USAGE = <<"USAGE";
Dump precedence()/occurrence() results as JSON for a given date/hour/version.

Usage: $0 --date=YYYY-MM-DD --hour=<HourName> --version="<Version String>" [options]

Required:
  --date=YYYY-MM-DD      ISO date (converted internally to M-D-YYYY for precedence())
  --hour=HOUR             One of: Matutinum, Laudes, Prima, Tertia, Sexta, Nona, Vesperae, Completorium
  --version=VERSION       Exact rubrics version string, e.g. "Rubrics 1960 - 1960"

Options:
  --dioecesis=NAME        Default: Generale
  --lang=LANG             Language for rankname()/office text lookups. Default: Latin
  --help                  Show this message
USAGE

my ($opt_date, $opt_hour, $opt_version);
my $opt_dioecesis = 'Generale';
my $opt_lang = 'Latin';
my $help = 0;

GetOptions(
  'date=s'      => \$opt_date,
  'hour=s'      => \$opt_hour,
  'version=s'   => \$opt_version,
  'dioecesis=s' => \$opt_dioecesis,
  'lang=s'      => \$opt_lang,
  'help'        => \$help,
) or die $USAGE;

die $USAGE if $help;
die $USAGE unless $opt_date && $opt_hour && $opt_version;

my ($y, $m, $d) = $opt_date =~ /^(\d{4})-(\d{2})-(\d{2})$/
  or die "Invalid --date, expected YYYY-MM-DD: $opt_date\n";
my $internal_date = "$m-$d-$y";

# Minimal context precedence()/occurrence() need outside a CGI request,
# mirroring createTransferTables.pl's proven setup (but $Bin-relative, so
# this script works from any working directory).
$datafolder = "$Bin/../../www/horas";
$htmlurl = '../../www/horas';
$link = 'blue';
$visitedlink = 'blue';
$dialogbackground = '#eeeeee';
$dialogfont = 'maroon';
$border = '1';
$cookieexpire = '+1y';
$savefiles = '0';

$dioecesis = $opt_dioecesis;
$missa = 0;
$missanumber = 0;
$votive = 'Hodie';    # no votive override: compute the ordinary office of the day

# check_horas() returns a list (it maps over the input), so it must be
# called in list context even for a single hour name.
($hora) = check_horas($opt_hour);
die "Unknown hour: $opt_hour\n" unless $hora;

$version = check_version($opt_version);
die "Unknown version: $opt_version\n" unless $version;

$lang1 = check_language($opt_lang);
die "Unknown language: $opt_lang\n" unless $lang1;
$lang2 = 'English';
$langfb = 'English';

precedence($internal_date);
my $rankname = rankname($lang1);

# Extracts the structural fields worth surfacing from a winner/commemoratio
# hash (populated by officestring()) without dumping the dozens of rendered
# prayer-text keys (Ant *, Lectio*, Responsory*, ...) that aren't relevant
# to a precedence/rank differential test.
sub office_summary {
  my ($file, %hash) = @_;
  (my $rank_str = $hash{Rank} // '') =~ s/\s+$//;
  (my $rule_str = $hash{Rule} // '') =~ s/\s+$//;

  # Same extraction setheadline() uses to get the office's display name.
  my $officium = ($rank_str =~ /^(?<officium>.*?);/) ? $+{officium} : '';

  return {
    file     => $file // '',
    officium => $officium,
    rank     => $rank_str,
    rule     => $rule_str,
  };
}

my %out = (
  date         => $opt_date,
  hour         => $hora,
  version      => $version,
  dioecesis    => $dioecesis,
  lang         => $lang1,
  winner       => office_summary($winner, %winner),
  rankname     => $rankname,
  numericRank  => $rank + 0,
  duplex       => $duplex + 0,
  commemoratio => office_summary($commemoratio, %commemoratio),
  commune      => $commune // '',
  communetype  => $communetype // '',
);

# encode_json already returns UTF-8-encoded bytes; keep STDOUT free of any
# encoding layer to avoid double-encoding diacritics (e.g. "Sanctæ").
binmode(STDOUT, ':raw');
print encode_json(\%out), "\n";
