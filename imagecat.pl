#!/usr/bin/perl -w

use strict;
use warnings;
use autodie;
use Image::ExifTool ':Public';
use DateTime::Format::Strptime;
use File::Path qw(make_path);
use File::Copy;
use File::Spec;
use File::Basename;
use File::Find;
use Getopt::Long;
use Pod::Usage;
use Digest::MD5::File qw(file_md5_hex);
use Term::ProgressBar;


my $parser = DateTime::Format::Strptime->new(pattern => '%Y:%m:%d %H:%M:%S', strict => 1);
my @parsers = (DateTime::Format::Strptime->new(pattern => 'IMG-%Y%m%d', strict => 1),
	       DateTime::Format::Strptime->new(pattern => 'PANO_%Y%m%d_%H%M%S', strict => 1),
	       DateTime::Format::Strptime->new(pattern => 'IMG_%Y%m%d_%H%M%S', strict => 1),
	       DateTime::Format::Strptime->new(pattern => '%Y%m%d_%H%M%S', strict => 1),
	       DateTime::Format::Strptime->new(pattern => 'VID-%Y%m%d', strict => 1),
	       DateTime::Format::Strptime->new(pattern => '%Y%m%d', strict => 1));

# options
my $from_dir;
my $to_dir;
my $copy = 0;
my $dry_run = 0;
my $recursive;
my $max_depth;
my $verbose = 0;
my $man = 0;
my $help = 0;

# stats
my $tot = 0;
my $copied = 0;
my $moved = 0;
my $renamed = 0;
my $exist = 0;
my $skipped = 0;

# global var
my $num_files = 0;
my $progress_bar;
my $start_depth;

sub extract_date {
	my $info = ImageInfo($_[0], 'CreateDate');
	my $size = keys %$info;
	my $dt;

	if ($size > 0) {
		print "Creation date: $info->{'CreateDate'}\n" if $verbose;

		$dt = $parser->parse_datetime($info->{'CreateDate'});
		return $dt if ($dt);
	}

	foreach (@parsers) {
		$dt = $_->parse_datetime($_[1]);
		return $dt if ($dt);
	}
	return;
}

sub catalog_file {
	my $name;
	my $ext;

	return if !-f $_;

	$tot++;
	$progress_bar->update($tot) if !$verbose;

	my $filename = File::Spec->catfile($File::Find::dir, $_);
	($name,undef,$ext) = fileparse($filename,'\..*');

	print "($tot/$num_files) Filename: $filename\n" if $verbose;
	my $date = extract_date($filename, $name);
	if (!$date) {
		print "Skipping $filename because cannot extract creation date\n";
		$skipped++;
		return;
	}

	my $new_dir = File::Spec->catdir($to_dir, $date->strftime('%Y'), $date->strftime('%Y_%m_%d'));
	if (!-d $new_dir) {
		print "Make new directory $new_dir\n" if $verbose;
		if (!$dry_run) {
			make_path $new_dir or die "Unable to create $new_dir\n";
		}
	}

	my $counter = 0;
	my $new_filename;
	while (1) {
		if ($counter > 0) {
			$new_filename = File::Spec->catfile($new_dir, "${name}_${counter}${ext}");
		}
		else {
			$new_filename = File::Spec->catfile($new_dir, $_);
		}
		if (-e $new_filename) {
			print "File $new_filename already exists\n" if $verbose;
			my $new_md5 = file_md5_hex($new_filename);
			my $md5 = file_md5_hex($filename);
			if ($md5 eq $new_md5) {
				print "The two files are equal\n" if $verbose;
				if (!$copy) {
					print "Deleting $filename\n" if $verbose;
					if (!$dry_run) {
						unlink($filename) or die "Can't delete $filename: $!\n";
					}
				}
				$exist++;
				last;
			}
			else {
				print "The two files are different\n" if $verbose;
				$counter++;
			}
		}
		else {
			print "Renaming file from $filename to $new_filename\n" if $counter > 0 and $verbose;
			$renamed++ if ($counter > 0);
			if ($copy) {
				print "Copy $filename to $new_filename\n" if $verbose;
				if (!$dry_run) {
					copy($filename, $new_filename) or die "The copy operation failed: $!\n";
					$copied++;
				}
			}
			else {
				print "Move $filename to $new_filename\n" if $verbose;
				if (!$dry_run) {
					move($filename, $new_filename) or die "The move operation failed: $!\n";
					$moved++;
				}
			}
			last;
		}
	}
	print "\n" if $verbose;
}

GetOptions('from=s' => \$from_dir,
           'to=s' => \$to_dir,
           'copy' => \$copy,
           'dry-run' => \$dry_run,
           'recursive' => \$recursive,
           'max-depth=i' => \$max_depth,
           'verbose' => \$verbose,
           'help|?' => \$help,
           man => \$man) or pod2usage(2);

pod2usage(-exitval => 0, -verbose => 0) if $help;
pod2usage(-exitval => 0, -verbose => 1) if $man;

pod2usage(-msg  => "-from_dir option is mandatory.", -exitval => 2, -verbose => 0) unless $from_dir;
pod2usage(-msg  => "-to_dir option is mandatory.", -exitval => 2, -verbose => 0) unless $to_dir;

if (defined($max_depth)) {
	$recursive = 0;
}
else {
	$recursive = 0 if !defined($recursive);
	$max_depth = 0;
}

$from_dir = Cwd::realpath($from_dir);
$start_depth = 1 + grep { length } File::Spec->splitdir($from_dir);

find (
  {
    preprocess => sub
      { @_ if (scalar File::Spec->splitdir($File::Find::dir) - $start_depth) <= $max_depth or $recursive },
    wanted => sub
      { $num_files++ if -f },
  },
  $from_dir
);

$progress_bar = Term::ProgressBar->new($num_files) if !$verbose;
find (
  {
    preprocess => sub
      { @_ if (scalar File::Spec->splitdir($File::Find::dir) - $start_depth) <= $max_depth or $recursive },
    wanted => \&catalog_file
  },
  $from_dir
);

# print stats
print "\n\nTotal number of files: $tot\n";
print "Skipped files: $skipped\n";
print "Already present files: $exist\n";
print "Copied files: $copied\n";
print "Moved files: $moved\n";
print "Requiring renaming: $renamed\n";

# help and manual

__END__

=head1 NAME

imagecat - Organize and distribute photos to directories

=head1 SYNOPSIS

imagecat [options] [file ...]

 Options:
   -help            brief help message
   -man             full documentation
   -verbose         increase verbosity
   -from            directory from where to get images
   -to              directory to catalog images
   -copy            copy instead of moving images
   -dry-run         dry run without touching anything
   -recursive       recursively visit subdirectories
   -max-depth       visit maximum -max-depth level in recursion


=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-verbose>

Increase verbosity.

=item B<-from>

Directory from where to get images.

=item B<-to>

Directory to catalog images.

=item B<-copy>

Copy instead of moving images.

=item B<-dry-run>

Dry run without touching anything.

=item B<-recursive>

Recursively visit subdirectories.

=item B<-max-depth>

Visit maximum -max-depth level in recursion. Enable implicitly recursion.

=back

=head1 DESCRIPTION

B<This program> will read all images from -from directory
and catalog them to -to directory based on creation date.

=cut

