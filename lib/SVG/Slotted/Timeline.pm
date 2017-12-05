package SVG::Slotted::Timeline;
use Moose;
use SVG::Slotted::Event;
use SVG;
use DateTime;
use Data::Printer;
use v5.10;
use namespace::clean;

has _events =>(is=>'ro',isa =>'ArrayRef[SVG::Slotted::Event]',traits=>['Array'],handles=>{ev_push=>'push',ev_all=>'elements'});
has _min=>(is=>'rw',isa =>'DateTime');
has _max=>(is=>'rw',isa =>'DateTime');
has _resolution=>(is=>'rw',isa=>'Str',default=>"days");
has min_width=>(is=>'ro',isa=>'Int',default=>50);
has units=>(is=>'ro',isa=>'Int',default=>800);
1;

sub add_event {
	my ($self,%hsh)=@_;
	if (not defined $self->_min or DateTime->compare($self->_min,$hsh{start})>0 ) {$self->_min($hsh{start});}
	if (not defined $self->_max or DateTime->compare($self->_min,$hsh{start})<0 ) {$self->_max($hsh{start});}
	$hsh{min_width}=$self->min_width;
	my $ev=SVG::Slotted::Event->new( %hsh);
	$self->ev_push($ev);
}

sub layout {
	my $self=shift;
	my @slot;
	$self->_set_resolution();
	foreach my $event (sort _byStart $self->ev_all){
		my $found=0;
		$event->resolution($self->_resolution);
		$event->origin($self->_min);
		for my $slot(0..$#slot){
			my $evslot=$slot[$slot];
			my $head=pop @{$evslot};if ($head){push @{$evslot}, $head;}
			if ($head->x0+$head->width <$event->x0){
				push @{$evslot},$event;
				$found=1;
				last;

			}
		}

		if ($found==0){
			my $newslot=[$event];
			unshift @slot,$newslot;
		}
	}
	return @slot;
}

sub to_ds {
	my $self=shift;
	my @slot=$self->layout;
	my @ds;
	my ($y0,$y1,$x0,$maxX)=(0,1.5,0,0);
	my $fmt="yyyy-MM-dd hh:mm";
	foreach my $slot (@slot){
		foreach my $ev (@{$slot}){
			push @ds,{idchangeset=>$ev->id,count=>$ev->name,name=>$ev->tooltip,created=>$ev->start->format_cldr($fmt),
				x=>$ev->x0,y=>$y0,width=>$ev->width,height=>$y1, status=>$ev->color};
			$maxX=$ev->x0+$ev->width	if ($maxX<$ev->x0+$ev->width);
		}
		$y0+=1.5*$y1;
	}
	return {resolution=>$self->_resolution,start=>$self->_min->format_cldr($fmt),end=>$self->_max->format_cldr($fmt),maxX=>$maxX,maxY=>$y0,ds=>\@ds}
}
sub to_svg{
	my $self=shift;
	my @slot=$self->layout;

	my $svg=SVG->new();
	my $bbox=$svg->group(id=>"bbox");
	my $bars=$svg->group(id=>"bars");
        my $def=$svg->defs(id=>"arrow","stroke-linecap"=>"round","stroke-width"=>"1");
        $def->line(x1=>"-8",y1=>"-4",x2=>"1",y2=>"0");
        $def->line(x1=>"1",y1=>"0",x2=>"-8",y2=>"4");
	my ($y0,$y1,$x0,$maxX)=(0,12,0,0);
	foreach my $slot (@slot){
		foreach my $ev (@{$slot}){
			$x0=$ev->x0;
			my $width=$ev->width;
			my $color=$ev->color;
			my $rect=$bars->rect(x=>$x0."px",y=>$y0."px",width=>$width."px",height=>$y1."px", fill=>$color);
			$rect->title->cdata($ev->name);
			$maxX=$x0+$width	if ($maxX<$x0+$width);
		}
		$y0+=$y1*1.5;

	}
	$y0+=$y1*1.5;
        $maxX=800 if($maxX<800);
	my $border=$bbox->rect(x=>0,"fill-opacity"=>"0.1",y=>0,width=>$maxX."px",height=>$y0."px");
	my $x=0 ;
        my$dim=$bbox->group(id=>"dim");
	$dim->line(x1=>0,y1=>($y0+12),x2=>800,y2=>($y0+12));
	$dim->use("xlink:href"=>"#arrow",x=>0,y=>($y0+12));
	$dim->use("xlink:href"=>"#arrow",x=>800,y=>($y0+12));
	$dim->text(x=>$maxX/2,y=>($y0+12),"text-anchor"=>"middle")->cdata("<-------------- ". $self->_resolution. " --------------->");
        #<use stroke="#000000" xlink:href="#ah" transform="translate(354.4 119.4)rotate(90)"/>
	$bbox->text(x=>$maxX,y=>12)->cdata("Min:\t".$self->_min->format_cldr("yy/mm/d h:m"));
	$bbox->text(x=>$maxX,y=>30)->cdata("Max:\t".$self->_max->format_cldr("yy/mm/d h:m"));
	$bbox->text(x=>$maxX,y=>50)->cdata("Scale:\t10 ".$self->_resolution);
	while($x<=$maxX){
		$bbox->line(x1=>$x,x2=>$x,y1=>$y0,y2=>0 ,style=>"stroke:#fff;stroke-width:1px" );
		$x=$x+10;

	}
	return $svg->xmlify;
}
sub _set_resolution{
	my $self=shift;
	my $duration=$self->_max->delta_days($self->_min);
	my $minutes=$self->_max->delta_ms($self->_min)->{minutes};
	#say "Duration is ",np $duration;
	my $resolution="days";
	my $days=$duration->{days};
	#say "Days is ",np $days;
	$resolution="years"   if ($days<$self->units*365);
	$resolution="months"  if ($days<$self->units*30);
	$resolution="weeks"   if ($days<$self->units*7);
	$resolution="days"    if ($days<$self->units);
	$resolution="hours"   if ($minutes<60* $self->units);
	$resolution="minutes" if ($minutes<$self->units);
	$self->_resolution($resolution);
}
sub _byStart {
	return DateTime->compare($a->start,$b->start);
}