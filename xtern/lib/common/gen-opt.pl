#!/usr/bin/perl -w

#
# Copyright (c) 2013,  Regents of the Columbia University 
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other 
# materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR 
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
# IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

# This script parses the input options file passed in as $ARGV[0] and
# generates an $options.h in directory $ARGV[1] and and $options.cpp file
# in directory $ARGV[2].  The input options file is a collection of "key =
# value" lines.  For each option key, this script creates a variable
# options::key.  Users call read_options(options_file) to set these
# variables according to options_file.  Users can also can
# read_env_options() to set threse variables according to environment
# variable TERN_OPTIONS in the form of key1=val1:key2=val2

eval 'exec perl -w -S $0 ${1+"$@"}'
    if 0;

use strict;
use File::Path qw(mkpath);

my $default_opt_file = shift @ARGV;
my $hfile_dir        = shift @ARGV;
my $cppfile_dir      = shift @ARGV;

my $note = 
    "// DO NOT EDIT -- automatically generated by $0\n".
    "// from $default_opt_file\n";
my %options = ();

sub main {

    mkpath($hfile_dir);
    mkpath($cppfile_dir);

    my $hfile = "$hfile_dir/options.h";
    my $cppfile = "$cppfile_dir/options.cpp";

    read_optf($default_opt_file, \%options);
    emit_if_diff(\%options, $hfile, \&emit_header);
    emit_if_diff(\%options, $cppfile, \&emit_cppfile);
}

sub read_optf($$)
{
    my ($file, $optref) = @_;
    return unless -f $file;

    open OPTF, $file || die $!;
    while (<OPTF>) {
        s/\#.*$//; # remove comments
	next if /^\s*$/; # skip empty lines

        # check for simple typo
	if(/^([^\s]+)\s*$/) {
	    die "No value specified for option $1::$2 at line $. in $file!\n";
	}
        if (/^([^\s=]+)\s+([^\s=]+)\s*$/) {
	    die "missing = between  $1 and $2 at line $. in $file!\n";
	}

        # get key, value
        if (!/^([^\s]+)\s*=\s*([^\s]+)\s*$/) {
            die "mal-formated option at line $. in $file: $_";
        }
        my ($key, $val) = ($1, $2);
        $val =~ s/^\"(.*)\"$/$1/; # strip quotes
	$optref->{$key} = $val;
    }
    close OPTF;
}

sub emit_if_diff($$$)
{
    my ($optref, $file, $emit_fn) = @_;
    my $tmp = $file.".tmp";

    &$emit_fn ($optref, $tmp);

    if(!-f $file || `diff $file $tmp`) {
	system ("mv $tmp $file");
    } else {
	unlink "$tmp";
    }    
}

sub emit_options($$)
{
    my ($optref, $file) = @_;
    open OPT, ">$file" || die $!;
    print OPT join("\n",
                   map {"_ = $optref->{$_};"}
                   sort keys %$optref), "\n";
    close OPT;
}

sub emit_header($$)
{
    my ($optref, $file) = @_;

    my $def = "__OPTIONS_H";

    # variable declarations
    my $opt_decl = "";
    $opt_decl .= join("\n",
                      map {my $type = opt_type ($optref->{$_});
                           "extern $type ${_};";}
                      sort keys %$optref);
    $opt_decl .= "\n";

    open HEADER, ">$file" || die $!;
    print HEADER<<CODE;
$note

#ifndef $def
#define $def

#include <string>

namespace options {

$opt_decl

bool read_options(const char *f);
bool read_env_options();
void print_options(void);
void print_options(const char *f);

}

#endif

CODE

    close HEADER;
}

sub emit_cppfile($$)
{
    my ($optref, $file) = @_;

    # read_option_inter function body
    my $read_option_body = "";
    $read_option_body .=
        join("\n",
             map {
                 my $type = opt_type ($optref->{$_});
                 my $res = "  if (key == \"$_\")\n";
                 if($type eq "std::string") {
                     $res .= "    { options::${_} = val; return 1; }";
                 } elsif ($type eq "float") {
                     $res .= "    { options::${_} = (float)atof(val.c_str()); return 1; }";
                 } else {
                     $res .= "    { options::${_} = (int)strtoul(val.c_str(), 0, 0); return 1; }";
                 }
                 $res;} sort keys %$optref);

    # print_options_to_stream function body
    my $print_options_body = "";
    $print_options_body .= 
        join("\n",
             map {"  o << \"${_} = \" << options::${_} << endl;";}
             sort keys %$optref);

    # print variable definitions
    my $opt_def = "";
    $opt_def .=
        join("\n",
             map {my $type = opt_type ($optref->{$_});
                  if ($type eq "std::string") {
                      "$type ${_} = \"$optref->{$_}\";\n";
                  } else {
                      "$type ${_} = $optref->{$_};\n";
                  }} sort keys %$optref);
    $opt_def .= "\n";

    open CFILE, ">$file" || die $!;
    print CFILE<<CODE;

$note
#include <iostream>
#include <fstream>
#include <string>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <assert.h>

#include "tern/options.h"

using namespace std;

namespace options {

$opt_def

static int read_option_inter (string &key, string &val);
static void print_options_to_stream (ostream &o);
static int parse_next_option(ifstream& f, string& key, string& val);
static int parse_next_env_option(string& env, string& key, string& val);

bool read_options(const char *f)
{
  ifstream fs(f);
  if (!fs)
    return false;

  string key, val;
  while (parse_next_option (fs, key, val))
    read_option_inter(key, val);
  return true;
}

bool read_env_options()
{
  const char* opts = getenv("TERN_OPTIONS");
  if (!opts)
    return false;
  string env(opts);
  string key, val;
  while (parse_next_env_option (env, key, val))
    read_option_inter(key, val);
  return true;
}

void print_options (void)
{
  print_options_to_stream (cout);
}

void print_options (const char *f)
{
  ofstream fs(f);
  if (!f) {
    cerr << "Unable to open " << f << endl;
    return;
  }
  print_options_to_stream (fs);
  fs << "\\n#DO NOT DELETE\\n";
}

static void print_options_to_stream (ostream &o)
{
$print_options_body
}

static void split_key_val(string& line, string& key, string& val)
{
  string::size_type sep = line.find('=');
  if(sep == string::npos){
    cerr << "Separator '=' not found in " << line << endl;
    assert(0 && \"invalid option\");
  }
  key = line.substr(0, sep);
  assert(key.size() && "empty key");
  val = line.substr(sep+1);
  assert(val.size() && "empty value");
}

static int parse_next_option(ifstream& f, string& key, string& val)
{
  string line;
  string::size_type sep;

  while(!f.eof()){
    getline(f, line);

    // remove comments
    sep = line.find('#');
    if(sep != string::npos)
        line.erase(sep);
    // remove spaces
    line.erase(remove_if(line.begin(), line.end(), ::isspace), line.end());

    if(line.size() > 0)
      break; // found a non-empty line
    // must be a comment line; try again
  }
  if(line.size() == 0) // cannot find a non-empty line; must be eof
    return 0;

  split_key_val(line, key, val);
  return 1;
}

static int parse_next_env_option(string& env, string& key, string& val)
{
  string::size_type sep;
  string line;

  sep = env.find(':');
  if(sep != string::npos) {
      line = env.substr(0, sep);
      env = env.substr(sep+1);
  } else
      line.swap(env);
  line.erase(remove_if(line.begin(), line.end(), ::isspace), line.end());
  if(line.size() == 0) // cannot find a non-empty line; must be eos
    return 0;

  split_key_val(line, key, val);
  return 1;
}

static int read_option_inter (string &key, string &val)
{
$read_option_body
  return 0;
}

}

CODE

    close CFILE;
}

sub opt_type($)
{
    my ($value) = @_;
    if ($value =~ /^[+-]?\d+$/) {return "int";}
    elsif($value =~ /^0x[\da-fA-F]+$/) { return "unsigned";}
    #elsif ($value =~ /^[+-]?\d*\.\d+$/) {return "float";}
    else {return "std::string";}
}

main;