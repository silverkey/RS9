#!/usr/bin/perl
package Biosub::Ranges;

use strict;
use warnings;
use Bio::Range;

=head2 disconnected_ranges

 Title   : disconnected_ranges

 Usage   : my $ranges = Range::Utils->disconnected_ranges($dbh,$ranges,'1');

 Function: disconnected_ranges using mysql

 Returns : listref of [Bio::Range from bioperl]

 Args    : -1 dbh
           -2 array_ref of Bio::Range
           -3 '1' if you want to drop the table created for calculations

 Note    : 

=cut

sub disconnected_ranges {

  my $class = shift;
  my $dbh = shift;
  my $features = shift;
  my $drop = shift;
  
  my $table = _create_table($dbh);
  my $nrows  = _populate_table($dbh,$table,$features);
  my $disconnected_ranges = _range($dbh,$table,$nrows);
  _drop_table($dbh,$table) if $drop;

  return $disconnected_ranges;
}

sub _create_table {
  
  my $dbh = shift;
  my $table = _generate_random_string('10');

  my $sth = $dbh->prepare("CREATE TABLE $table (".
                          'disconnected_ranges_id int(10) unsigned NOT NULL auto_increment,'.
                          'start int(10) unsigned not NULL,'.
                          'end int(10) unsigned not NULL,'.
                          'checked int(1) default NULL,'.
                          'PRIMARY KEY (disconnected_ranges_id),'.
                          'KEY start(start),'.
                          'KEY end(end),'.
                          'KEY checked(checked))');
  $sth->execute;
  return($table);
}

sub _populate_table {
  
  my $dbh = shift;
  my $table = shift;
  my $features = shift;
  
  foreach my $feature(@$features) {
    my $insert = $dbh->prepare("INSERT INTO $table SET ".
                               'start = '.$dbh->quote($feature->start).
                               ',end = '.$dbh->quote($feature->end));
    $insert->execute;
  }
  my $nrows = _get_num_rows($dbh,$table);
  return($nrows);
}

sub _get_num_rows {

  my $dbh = shift;
  my $table = shift;

  my $sth = $dbh->prepare('SELECT COUNT(*) count FROM '.$table);
  $sth->execute;
  my $row = $sth->fetchrow_hashref;
  return($row->{'count'});
}

sub _range {
  
  my $dbh = shift;
  my $table = shift;
  my $nrows = shift;
  
  my $sth = $dbh->prepare("SELECT * FROM $table ".
                          'WHERE checked IS NULL '.
                          'ORDER BY start LIMIT 1');
  $sth->execute;

  my $pre_range = $sth->fetchrow_hashref;
  
  unless($pre_range) {
    my $final_nrows = _decide($dbh,$table,$nrows);
    my $disconnected_ranges = _get_disconnected_ranges($dbh,$table);
    return $disconnected_ranges;
  }

  my $range = Bio::Range->new(-start => $pre_range->{'start'},
                              -end => $pre_range->{'end'});

  my $new_range = _new_range($dbh,$table,$range,$nrows);
}

sub _new_range {
  
  my $dbh = shift;
  my $table = shift;
  my $range = shift;
  my $nrows = shift;
      
  my $sth = $dbh->prepare("SELECT min(start) min_start, max(end) max_end FROM $table".
                          ' WHERE start <= '.$range->end.
                          ' AND end >= '.$range->start);
  $sth->execute;
  my $pre_range = $sth->fetchrow_hashref;
      
  my $new_range = Bio::Range->new(-start => $pre_range->{'min_start'},
                                  -end => $pre_range->{'max_end'});
                                  
  _test($dbh,$table,$range,$new_range,$nrows);
}
                                  
sub _test {
  
  my $dbh = shift;
  my $table = shift;
  my $range = shift;
  my $new_range = shift;
  my $nrows = shift;
  
  if($range->equals($new_range)) {
    _insert($dbh,$table,$range);
    _range($dbh,$table,$nrows);
  }
  else {
    $range = ();
    $range = Bio::Range->new(-start => $new_range->start,
                             -end => $new_range->end);
    $new_range = ();
    _new_range($dbh,$table,$range,$nrows);
  }
}

sub _insert {

  my $dbh = shift;
  my $table = shift;
  my $range = shift;

  my $delete = $dbh->prepare("DELETE from $table WHERE ".
                             'start <= '.$range->end.
                             ' AND end >= '.$range->start);
  $delete->execute;

  my $insert = $dbh->prepare("INSERT INTO $table SET ".
                             'start = '.$range->start.
                             ',end = '.$range->end.
                             ',checked = 1');
  $insert->execute;
}  

sub _decide {

  my $dbh = shift;
  my $table = shift;
  my $nrows = shift;  
  my $new_nrows = _get_num_rows($dbh,$table);
  if($nrows == $new_nrows) {
    return $nrows;
  }
  else {
    my $update = $dbh->prepare("UPDATE $table SET checked = NULL");
    $update->execute;
    _range($dbh,$table,$new_nrows);    
  }
}

sub _get_disconnected_ranges {

  my $dbh = shift;
  my $table = shift;
  my @disconnected_ranges;

  my $sth = $dbh->prepare("SELECT DISTINCT start, end FROM $table ORDER BY start");
  $sth->execute;

  while(my $row = $sth->fetchrow_hashref) {

    my $range = Bio::Range->new(-start => $row->{'start'},
                                -end => $row->{'end'});

    push(@disconnected_ranges,$range);
  }
  return(\@disconnected_ranges);
}

sub _drop_table {

  my $dbh = shift;
  my $table = shift;

  my $sth = $dbh->prepare("DROP TABLE $table");
  $sth->execute
}

=head2 curtained_ranges

 Title   : curtained_ranges

 Usage   : my $ranges = Range::Utils->curtained_ranges($ranges);

 Function: curtained_ranges are ranges created from a disconnected range
           containing all the ranges divided regarding the positions of
           intersections between ranges forming the disconnected
           For example the next disconnected ranges:

           |------------------------------------|  } disconnected range


           |------------|          |------------|  } ranges forming
                                                   } the disconnected
                    |------------------|           } range


           |-------||---||--------||---||-------|  } curtained ranges

 Returns : listref of Bio::Range from bioperl determining a single 
           disconnected range

 Args    : -1 array_ref of Bio::Range

 Note    : THE FUNCTION EXPECTS ALL THE RANGES FORMING A UNIQUE DISCONNECTED RANGES

=cut

sub curtained_ranges {

  my $class = shift;
  my $ranges = shift;
  my $curtain;
  my $c;
  my @start;
  my @end;
  
  foreach my $range(@$ranges) {
    
    $curtain->{$range->start} = 1;
    $curtain->{$range->end} = 1;
    push(@start,$range->start);
    push(@end,$range->end);
  }
  
  my @ranges;
  
  my @limit = sort {$a <=> $b} keys(%{$curtain});
  
  for($c=0;$c<=($#limit-1);$c++) {
    my $start = $limit[$c];
    my $end = (($limit[$c+1])-1);
    $end++ if ($c == ($#limit-1) || grep(/^$limit[$c+1]$/,@end));
    $start ++ if (grep(/^$limit[$c]$/,@end));
    my $range = Bio::Range->new(-start => $start,
                                 -end => $end);
    push(@ranges,$range);
  }
  return(\@ranges);
}

sub _generate_random_string {

  my $length_of_randomstring = shift;
  
  my @chars=('a'..'z','A'..'Z','_');
  my $random_string;
  foreach (1..$length_of_randomstring) {
    # rand @chars will generate a random 
    # number between 0 and scalar @chars
    $random_string .= $chars[rand @chars];
  }
  return $random_string;
}

1;
