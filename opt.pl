#!/usr/bin/perl -w

use strict;
use Fcntl qw/SEEK_SET/;

sub SCOOP_SIZE() { 64 };
sub PLOTSIZE() { 262144 };

$| = 1;

my $in_filename = shift || die '';

die 'Wrong file name format' unless $in_filename =~ m!^(.+/)?(\d+)_(\d+)_(\d+)_(\d+)$!;
my ($dir, $key, $startnonce, $nonces, $stagger) = ($1, $2, $3, $4, $5);
print "dir=$dir key=$key, startnonce=$startnonce, nonces=$nonces, stagger=$stagger\n";

my $out_dir = shift || $dir;
die "Not a directory: '$out_dir'" unless -d $out_dir;
$out_dir .= '/' unless $out_dir =~ m!/$!;

my $out_filename = $out_dir . $key . '_' . $startnonce . '_' . $nonces . '_' . $nonces;

my $in_file_size = -s $in_filename;
die sprintf('File size mismatch (have %d, expected %d)', $in_file_size, $nonces * PLOTSIZE) unless $in_file_size == $nonces * PLOTSIZE;

die "Nonces not a multiple of stagger" if ($nonces % $stagger);

my $blocks = $nonces / $stagger;
if ($blocks == 1) {
    print "File is already organized\n";
    exit 1;
} else {
    print "blocks = $blocks\n";
}

open I, $in_filename or die "Cannot open $in_filename: " . $!;
binmode(I) || die "binmode failed ($in_filename)" . $!;

my $ssize = 4096;   # PLOTSIZE / SCOOP_SIZE ?
my $memory = (`free | grep Mem | awk '{print \$4}'` * 1024 * 0.7) || 0;
$memory = 250000000;
print "memory = $memory\n";
my $memused = 0;

while ($ssize > 1) {
    $memused = $blocks * $stagger * SCOOP_SIZE() * $ssize;
    last if $memused < $memory;
    $ssize = $ssize >> 1;
}

die "File $out_filename already exists" if -f $out_filename;

printf "Reorganizing file %s to file %s:\n", $in_filename, $out_filename;
printf "Processing %i scoops at once (uses %u MB memory)\n", $ssize, int($memused / 1000000);

open O, '>' . $out_filename or die "Cannot open $out_filename: " . $!;
binmode(O) || die "binmode failed ($out_filename)" . $!;

my @buf = ();
$buf[$_] = 0x00 x ($stagger * SCOOP_SIZE * $ssize) for (0..$blocks-1);
my $tempbuf = '';

my $bytes;

my $i=0;
while ($i < PLOTSIZE / SCOOP_SIZE) {
    printf "processing Scoop %i of %i\n", $i+1, PLOTSIZE / SCOOP_SIZE;

    for my $j (0..$blocks-1) {
        $bytes = 0;
        while ($bytes < $stagger * SCOOP_SIZE * $ssize) {
            seek I, ($j * $stagger * PLOTSIZE) + ($i * $stagger * SCOOP_SIZE) + $bytes, SEEK_SET;
            my $found = read I, $tempbuf, $stagger * SCOOP_SIZE * $ssize - $bytes;
            die 'Cannot read from file: ' . $! unless defined $found;
            substr($buf[$j], $bytes, $found) = $tempbuf;
            $bytes += $found;
        }
    }

    for my $k (0..$ssize-1) {
        for my $j (0..$blocks-1) {
            print O substr($buf[$j], $stagger * SCOOP_SIZE * $k, $stagger * SCOOP_SIZE) or die "Cannot print (k=$k, j=$j)" . $!;
        }
    }
    $i += $ssize;
}

close O;
close I;
