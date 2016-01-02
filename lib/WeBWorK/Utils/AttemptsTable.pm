#!/usr/bin/perl -w
use 5.010;

################################################################################
# WeBWorK Online Homework Delivery System
# Copyright © 2000-2007 The WeBWorK Project, http://openwebwork.sf.net/
# $CVSHeader: webwork2/lib/WebworkClient.pm,v 1.1 2010/06/08 11:46:38 gage Exp $
# 
# This program is free software; you can redistribute it and/or modify it under
# the terms of either: (a) the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version, or (b) the "Artistic License" which comes with this package.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See either the GNU General Public License or the
# Artistic License for more details.
################################################################################

=head1 NAME

lib/WeBWorK/Utils/AttemptsTable.pm

This file contains subroutines for formatting the table which reports the 
results of a student's attempt on a WeBWorK question.

=cut

use strict;
use warnings;
package WeBWorK::Utils::AttemptsTable;
use Class::Accessor 'antlers';
use Scalar::Util 'blessed';
use WeBWorK::Utils 'wwRound';
use CGI;

# has answers     => (is => 'ro');
# has displayMode => (is =>'ro');
# has imgGen      => (is =>'ro');

# Object contains hash of answer results
# Object contains display mode
# Object contains or creates Image generator
# object returns table
# object returns color map for answer blanks
# object returns javaScript for handling the color map


sub new {
	my $class = shift;
	$class = (ref($class))? ref($class) : $class; # create a new object of the same class
	my $rh_answers = shift;
	ref($rh_answers) =~/HASH/ or die "The first entry to AttemptsTable must be a hash of answers";
	my %options = @_; # optional:  displayMode=>, submitted=>, imgGen=>, ce=> 
	my $self = {
		answers      		=> $rh_answers,
		answerOrder         => $options{answerOrder}//(),
		answersSubmitted    => $options{answersSubmitted}//0,
		summary             => $options{summary}//'', # summary provided by problem grader
	    displayMode 		=> $options{displayMode} || "MathJax",
	    showAnswerNumbers    => $options{showAnswerNumbers}//1,
	    showAttemptAnswers =>  $options{showAttemptAnswers}//1,    # show student answer as entered and simplified 
	                                                               #  (e.g numerical formulas are calculated to produce numbers)
	    showAttemptPreviews => $options{showAttemptPreviews}//1,   # show preview of student answer
	    showAttemptResults 	=> $options{showAttemptResults}//1,    # show whether student answer is correct
	    showMessages 		=> $options{showMessages}//1,          # show any messages generated by evaluation
	    showCorrectAnswers  => $options{showCorrectAnswers}//1,    # show the correct answers
	    showSummary         => $options{showSummary}//1,           # show summary to students
	    maketext            => $options{maketext}//sub {return @_},  # pointer to the maketext subroutine
	    imgGen              => undef,                              # created in _init method
	};
	bless $self, $class;
	# create read only accessors/mutators
	$self->mk_ro_accessors(qw(answers answerOrder answersSubmitted displayMode imgGen maketext));
	$self->mk_ro_accessors(qw(showAnswerNumbers showAttemptAnswers 
	                          showAttemptPreviews showAttemptResults 
	                          showCorrectAnswers showSummary));
	$self->mk_accessors(qw(correct_ids incorrect_ids showMessages  summary));
	# sanity check and initialize imgGenerator.
	_init($self, %options);
	return $self;
}

sub _init {
	# verify display mode
	# build imgGen if it is not supplied 
	my $self = shift;
	my %options = @_;
	$self->{submitted}=$options{submitted}//0;
	$self->{displayMode} = $options{displayMode} || "MathJax";
	# only show message column if there is at least one message:
	my @reallyShowMessages =  grep { $self->answers->{$_}->{ans_message} } @{$self->answerOrder};
	$self->showMessages( $self->showMessages && !!@reallyShowMessages );  
	                               #           (!! forces boolean scalar environment on list)
	# only used internally -- don't need accessors.
	$self->{numCorrect}=0;
	$self->{numBlanks}=0;
	$self->{numEssay}=0;

	if ( $self->displayMode eq 'images') {
		if ( blessed( $options{imgGen} ) ) {
			$self->{imgGen} = $options{imgGen};
		} elsif ( blessed( $options{ce} ) ) {
			warn "building imgGen"; 
			my $ce = $options{ce};
			my $site_url = $ce->{server_root_url};	
			my %imagesModeOptions = %{$ce->{pg}->{displayModeOptions}->{images}};
	
			my $imgGen = WeBWorK::PG::ImageGenerator->new(
				tempDir         => $ce->{webworkDirs}->{tmp},
				latex	        => $ce->{externalPrograms}->{latex},
				dvipng          => $ce->{externalPrograms}->{dvipng},
				useCache        => 1,
				cacheDir        => $ce->{webworkDirs}->{equationCache},
				cacheURL        => $site_url.$ce->{webworkURLs}->{equationCache},
				cacheDB         => $ce->{webworkFiles}->{equationCacheDB},
				dvipng_align    => $imagesModeOptions{dvipng_align},
				dvipng_depth_db => $imagesModeOptions{dvipng_depth_db},
			);
	        $self->{imgGen} = $imgGen;
		} else {
			warn "Must provide image Generator (imgGen) or a course environment (ce) to build attempts table.";
		}
	}
}

sub maketext {
	my $self = shift;
	return &{$self->{maketext}}(@_);
}
sub formatAnswerRow {
	my $self          = shift;
	my $rh_answer     = shift;
	my $ans_id        = shift;
	my $answerNumber  = shift;
	my $answerString         = $rh_answer->{student_ans}//''; 
	# use student_ans and not original_student_ans above.  student_ans has had HTML entities translated to prevent XSS.
	my $answerPreview        = $self->previewAnswer($rh_answer)//'&nbsp;';
	my $correctAnswer        = $rh_answer->{correct_ans}//'';
	my $correctAnswerPreview = $self->previewCorrectAnswer($rh_answer)//'&nbsp;';
	
	my $answerMessage   = $rh_answer->{ans_message}//'';
	$answerMessage =~ s/\n/<BR>/g;
	my $answerScore      = $rh_answer->{score}//0;
	$self->{numCorrect}  += $answerScore >=1;
	$self->{numEssay}    += ($rh_answer->{type}//'') eq 'essay';
	$self->{numBlanks}++ unless $answerString =~/\S/ || $answerScore >= 1; 
	
	my $feedbackMessageClass = ($answerMessage eq "") ? "" : $self->maketext("FeedbackMessage");
	
	my (@correct_ids, @incorrect_ids);
	my $resultString;
	my $resultStringClass;
	if ($answerScore >= 1) {
		$resultString = CGI::span({class=>"ResultsWithoutError"}, $self->maketext("correct"));
		$resultStringClass = "ResultsWithoutError";  
		# push @correct_ids,   $name if $answerScore == 1;
	} elsif (($rh_answer->{type}//'') eq 'essay') {
		$resultString =  $self->maketext("Ungraded"); 
		# $self->{essayFlag} = 1;
	} elsif ( defined($answerScore) and $answerScore == 0) { # MEG: I think $answerScore ==0 is clearer than "not $answerScore"
		# push @incorrect_ids, $name if $answerScore < 1;
		$resultStringClass = "ResultsWithError";
		$resultString = CGI::span({class=>"ResultsWithError ResultsWithErrorInResultsTable"}, $self->maketext("incorrect")); # If the latter class is defined, override the older red-on-white 
	} else {
		$resultString =  $self->maketext("[_1]% correct", wwRound($answerScore*100));
		#push @incorrect_ids, $ans_id if $answerScore < 1;
	}
	my $attemptResults = CGI::td({class=>$resultStringClass},
	               CGI::a({href=>"javascript:document.getElementById(\"$ans_id\").focus()"},
	               $self->nbsp($resultString)));

	my $row = join('',
			  ($self->showAnswerNumbers) ? CGI::td({},$answerNumber):'',
			  ($self->showAttemptAnswers) ? CGI::td({},$self->nbsp($answerString)):'' ,   # student original answer
			  ($self->showAttemptPreviews)?  $self->formatToolTip($answerString, $answerPreview):"" ,
			  ($self->showAttemptResults)?   $attemptResults : '' ,
			  ($self->showCorrectAnswers)?  $self->formatToolTip($correctAnswer,$correctAnswerPreview):"" ,
			  ($self->showMessages)?        CGI::td({class=>$feedbackMessageClass},$self->nbsp($answerMessage)):"",
			  "\n"
			  );
	$row;
}

#####################################################
# determine whether any answers were submitted
# and create answer template if they have been
#####################################################

sub answerTemplate {
	my $self = shift;
	my $rh_answers = $self->{answers};
	my @tableRows;
	my @correct_ids;
	my @incorrect_ids;

	push @tableRows,CGI::Tr(
			($self->showAnswerNumbers) ? CGI::th("#"):'',
			($self->showAttemptAnswers)? CGI::th($self->maketext("Entered")):'',  # student original answer
			($self->showAttemptPreviews)? CGI::th($self->maketext("Answer Preview")):'',
			($self->showAttemptResults)?  CGI::th($self->maketext("Result")):'',
			($self->showCorrectAnswers)?  CGI::th($self->maketext("Correct Answer")):'',
			($self->showMessages)?        CGI::th($self->maketext("Message")):'',
		);

	my $answerNumber     = 1;
    foreach my $ans_id (@{ $self->answerOrder() }) {  
    	push @tableRows, CGI::Tr($self->formatAnswerRow($rh_answers->{$ans_id}, $ans_id, $answerNumber++));
    	push @correct_ids,   $ans_id if $rh_answers->{$ans_id}->{score} >= 1;
    	push @incorrect_ids,   $ans_id if $rh_answers->{$ans_id}->{score} < 1;
    	$self->{essayFlag} = 1;
    }
	my $answerTemplate = CGI::h3($self->maketext("Results for this submission")) .
    	CGI::table({class=>"attemptResults"},@tableRows);
    ### "results for this submission" is better than "attempt results" for a headline
    $answerTemplate .= ($self->showSummary)? $self->createSummary() : '';
    $answerTemplate = "" unless $self->answersSubmitted; # only print if there is at least one non-blank answer
    $self->correct_ids(\@correct_ids);
    $self->incorrect_ids(\@incorrect_ids);
    $answerTemplate;
}
#################################################

sub previewAnswer {
	my $self =shift;
	my $answerResult = shift;
	my $displayMode = $self->displayMode;
	my $imgGen      = $self->imgGen;
	
	# note: right now, we have to do things completely differently when we are
	# rendering math from INSIDE the translator and from OUTSIDE the translator.
	# so we'll just deal with each case explicitly here. there's some code
	# duplication that can be dealt with later by abstracting out dvipng/etc.
	
	my $tex = $answerResult->{preview_latex_string};
	
	return "" unless defined $tex and $tex ne "";
	
	if ($displayMode eq "plainText") {
		return $tex;
	} elsif (($answerResult->{type}//'') eq 'essay') {
	    return $tex;
	} elsif ($displayMode eq "images") {
		$imgGen->add($tex);
	} elsif ($displayMode eq "MathJax") {
		return '<span class="MathJax_Preview">[math]</span><script type="math/tex; mode=display">'.$tex.'</script>';
	}
}

sub previewCorrectAnswer {
	my $self =shift;
	my $answerResult = shift;
	my $displayMode = $self->displayMode;
	my $imgGen      = $self->imgGen;
	
	my $tex = $answerResult->{correct_ans_latex_string};
	return $answerResult->{correct_ans} unless defined $tex and $tex=~/\S/;   # some answers don't have latex strings defined
	# return "" unless defined $tex and $tex ne "";
	
	if ($displayMode eq "plainText") {
		return $tex;
	} elsif ($displayMode eq "images") {
		$imgGen->add($tex);
		# warn "adding $tex";
	} elsif ($displayMode eq "MathJax") {
		return '<span class="MathJax_Preview">[math]</span><script type="math/tex; mode=display">'.$tex.'</script>';
	}
}

###########################################
# Create summary
###########################################
sub createSummary {
	my $self = shift;
	my $summary = ""; 
	my $numCorrect = $self->{numCorrect};
	my $numBlanks  = $self->{numBlanks};
	my $numEssay   = $self->{numEssay};
	my $fully = '';    #FIXME -- find out what this is used for in maketext.
	unless (defined($self->summary) and $self->summary =~ /\S/) {
		my @answerNames = @{$self->answerOrder()};
		if (scalar @answerNames == 1) {  #default messages
				if ($numCorrect == scalar @answerNames) {
					$summary .= CGI::div({class=>"ResultsWithoutError"},$self->maketext("The answer above is correct."));
				} elsif ($self->{essayFlag}) {
				    $summary .= CGI::div($self->maketext("The some answers will be graded later.", $fully));
				 } else {
					 $summary .= CGI::div({class=>"ResultsWithError"},$self->maketext("The answer above is NOT [_1]correct.", $fully));
				 }
		} else {
				if ($numCorrect + $numEssay == scalar @answerNames) {
					$summary .= CGI::div({class=>"ResultsWithoutError"},$self->maketext("All of the [_1] answers above are correct.",  $numEssay ? "gradeable":""));
				 } 
				 #unless ($numCorrect + $numBlanks == scalar( @answerNames)) { # this allowed you to figure out if you got one answer right.
				 elsif ($numBlanks + $numEssay != scalar( @answerNames)) {
					$summary .= CGI::div({class=>"ResultsWithError"},$self->maketext("At least one of the answers above is NOT [_1]correct.", $fully));
				 }
				 if ($numBlanks > $numEssay) {
					my $s = ($numBlanks>1)?'':'s';
					$summary .= CGI::div({class=>"ResultsAlert"},$self->maketext("[quant,_1,of the questions remains,of the questions remain] unanswered.", $numBlanks));
				 }
		}
	} else {
		$summary = $self->summary;   # summary has been defined by grader
	}
	$summary = CGI::div({role=>"alert", class=>"attemptResultsSummary"},
			  $summary);
	$self->summary($summary);
	return $summary;   # return formatted version of summary in class "attemptResultsSummary" div
}
################################################


sub color_answer_blanks {
	 my $self = shift;
	 my $out = join('', 
	 		  CGI::start_script({type=>"text/javascript"}),
	            "addOnLoadEvent(function () {color_inputs([\n  ",
		      join(",\n  ",map {"'$_'"} @{$self->{correct_ids}||[]}),
	            "\n],[\n  ",
		      join(",\n  ",map {"'$_'"} @{$self->{incorrect_ids}||[]}),
	            "]\n)});",
	          CGI::end_script()
	);
	return $out;
}

############################################
# utility subroutine -- prevents unwanted line breaks
############################################
sub nbsp {
	my ($self, $str) = @_;
	return (defined $str && $str =~/\S/) ? $str : "&nbsp;";
}

sub formatToolTip {  # note that formatToolTip output includes CGI::td wrapper
	my $self = shift;
	my $answer = shift;
	my $formattedAnswer = shift;
	return CGI::td({onmouseover=>qq!Tip('$answer',SHADOW, true, 
		                    DELAY, 1000, FADEIN, 300, FADEOUT, 300, STICKY, 1, OFFSETX, -20, CLOSEBTN, true, CLICKCLOSE, false, 
		                    BGCOLOR, '#F4FF91', TITLE, 'Entered:',TITLEBGCOLOR, '#F4FF91', TITLEFONTCOLOR, '#000000')!},
		                    $self->nbsp($formattedAnswer));
}




1;
