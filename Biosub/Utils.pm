#!/usr/bin/perl

package Biosub::Utils;

use strict;
use warnings;
use Data::Dumper;

=head2 get_conf

 Title   : get_conf

 Usage   : my $conf = Biosub::Utils->get_conf($file);

 Function: read a simple configuration file and return an hasref with keys/values

 Returns : an hashref with keys as param names and values as param values

 Args    : -1 name with the path of the simple config file

 Note    :  the configuration file is very simple - Pay attention in what it needs:

            - The key on the left and the value on the rigth of the = symbol.
            - Comment lines start with # as usual........
            - Empty lines are not taken in consideration........
            - All the spaces are removed before to parse each line so DO NOT USE spaces inside the key/value.
            - Do not use " or ' or other strange symbols in the key/value they are not parsed and create problems.

=cut

sub get_conf {
  my $class = shift;
  my $conf = shift;
  my $href = {};
  die "\nFile $conf do not exists\n" unless -e $conf;
  open(IN,$conf);
  while(my $row = <IN>) {
    $row =~ s/^\s//g;
    $row =~ s/\s$//g;
    next if $row =~ /^\#/;
    next unless $row =~ /\=/;
    chomp($row);
    $row =~ s/\s+//g;
    my($key,$val) = split(/\=/,$row);
    $href->{$key} = $val;
  }
  return $href;
}


=head2 start_log

 Title   : start_log

 Usage   : Biosub::Utils->start_log($href);

 Function: create a directory and a file in containing the couples key/value of the config

 Returns : -1 the name and path of the directory created
           -2 the name and path of the file created

 Args    : -1 the hashref returned by the function Biosub::Utils->get_conf()
           -2 a true value (1) if you need to create the folder in which to write the results
              IF YOU DO NOT CREATE IT WHAT IS EXISTING WILL BE CANCELLED!!!

 Note    : It uses the configuration variables:
           - $href->{OUT_DIR}
           - $href->{INPUT_FILE}

=cut

sub start_log {
  my $class = shift;
  my $href = shift;
  my $create = shift;

  my $name;
  $name .= $href->{OUT_DIR}.'/' if exists $href->{OUT_DIR};
  $name .= $0;
  $name =~ s/\.pl$//;
  $name .= '_'.$href->{INPUT_FILE} if exists $href->{INPUT_FILE};
  $name =~ s/\.fa$//;
  $name =~ s/\.fasta$//;
  my $dir = "$name";
  mkdir($dir) or die "\nCannot create directory $dir\: $!\n\n" if $create;
  $name .= '/'.$0;
  $name =~ s/\.pl$/.log/;

  open(OUT,">",$name) or die "\nCannot open file $name: $!\n\n";
  foreach my $key(keys %$href) {
    my $value = $href->{$key};
    print OUT "$key = $value\n";
  }
  print OUT "\n\n";
  close(OUT);
  return ($dir,$name);
}

=head2 check_conf_files_folders

 Title   : check_conf_files_folders

 Usage   : Biosub::Utils->check_conf_files_folders($href);

 Function: Check the configuration based on the assumptions that in the config file:
           - keys referring to a directory end with _DIR
           - keys referring to a file end with _FILE

 Returns : 1 or dies if some file or directory is missing

 Args    : -1 the hashref by the function Biosub::Utils->get_conf($CONF)

 Note    : 

=cut

sub check_conf_files_folders {
  my $class = shift;
  my $href = shift;
  foreach my $key(%$href) {
    if($key =~ /\_FILE$/) {
      die "\nCannot find file ".$href->{$key}.": $!\n\n" unless -e $href->{$key};
    }
    elsif($key =~ /_DIR$/) {
      die "\nCannot find directory ".$href->{$key}.": $!\n\n" unless -d $href->{$key};
    }
  }
  return 1;
}

=head2 strip_id

 Title   : strip_id

 Usage   : Biosub::Utils->strip_id($id);

 Function: Return only the accession number from the id coming from a blast
           search.
           For example from tr|C4WUT7|C4WUT7_ACYPI you will get C4WUT7

 Returns : only the accession number

 Args    : the accession returned from a blast search ($result->accession)

 Note    : 

=cut

sub strip_id {
  my $class = shift;
  my $id = shift;
  my ($acc, $version);
  if ($id =~ /(gb|emb|dbj|sp|tr|pdb|bbs|ref|lcl|tpg)\|(.*)\|(.*)/) {
    ($acc, $version) = split /\./, $2;
  }
  elsif ($id =~ /(pir|prf|pat|gnl)\|(.*)\|(.*)/) {
    ($acc, $version) = split /\./, $3;
  }
  return $acc if $acc;
  return $id;
}

1;
