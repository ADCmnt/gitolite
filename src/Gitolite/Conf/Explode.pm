package Gitolite::Conf::Explode;

# include/subconf processor
# ----------------------------------------------------------------------

@EXPORT = qw(
  explode
);

use Exporter 'import';

use Gitolite::Common;

use strict;
use warnings;

# ----------------------------------------------------------------------

# 'seen' for include/subconf files
my %included = ();
# 'seen' for group names on LHS
my %prefixed_groupname = ();

sub explode {
    trace( 3, @_ );
    my ( $file, $subconf, $out ) = @_;

    # seed the 'seen' list if it's empty
    $included{ device_inode("conf/gitolite.conf") }++ unless %included;

    my $fh = _open( "<", $file );
    while (<$fh>) {
        my $line = cleanup_conf_line($_);
        next unless $line =~ /\S/;

        $line = prefix_groupnames( $line, $subconf ) if $subconf ne 'master';

        if ( $line =~ /^(include|subconf) (\S.+)$/ ) {
            incsub( $1, $2, $subconf, $out );
        } else {
            # normal line, send it to the callback function
            push @{$out}, $line;
        }
    }
}

sub incsub {
    my $is_subconf = ( +shift eq 'subconf' );
    my ( $include_glob, $subconf, $out ) = @_;

    _die "subconf $subconf attempting to run 'subconf'\n" if $is_subconf and $subconf ne 'master';

    _die "invalid include/subconf file/glob '$include_glob'"
      unless $include_glob =~ /^"(.+)"$/
          or $include_glob =~ /^'(.+)'$/;
    $include_glob = $1;

    trace( 2, $is_subconf, $include_glob );

    for my $file ( glob($include_glob) ) {
        _warn("included file not found: '$file'"), next unless -f $file;
        _die "invalid include/subconf filename $file" unless $file =~ m(([^/]+).conf$);
        my $basename = $1;

        next if already_included($file);

        if ($is_subconf) {
            push @{$out}, "subconf $basename";
            explode( $file, $basename, $out );
            push @{$out}, "subconf $subconf";
        } else {
            explode( $file, $subconf, $out );
        }
    }
}

sub prefix_groupnames {
    my ( $line, $subconf ) = @_;

    my $lhs = '';
    # save 'foo' if it's an '@foo = list' line
    $lhs = $1 if $line =~ /^@(\S+) = /;
    # prefix all @groups in the line
    $line =~ s/(^| )(@\S+)(?= |$)/ $1 . ($prefixed_groupname{$subconf}{$2} || $2) /ge;
    # now prefix the LHS and store it if needed
    if ($lhs) {
        $line =~ s/^@\S+ = /"\@$subconf.$lhs = "/e;
        $prefixed_groupname{$subconf}{"\@$lhs"} = "\@$subconf.$lhs";
        trace( 2, "prefixed_groupname.$subconf.\@$lhs = \@$subconf.$lhs" );
    }

    return $line;
}

sub already_included {
    my $file = shift;

    my $file_id = device_inode($file);
    return 0 unless $included{$file_id}++;

    _warn("$file already included");
    trace( 2, "$file already included" );
    return 1;
}

sub device_inode {
    my $file = shift;
    trace( 2, $file, ( stat $file )[ 0, 1 ] );
    return join( "/", ( stat $file )[ 0, 1 ] );
}

1;
