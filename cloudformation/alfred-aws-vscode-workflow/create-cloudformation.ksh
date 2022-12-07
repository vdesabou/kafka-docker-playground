#!/bin/ksh

set -e

if [ ! -f $aws_cli ]
then
    print "<?xml version=\"1.0\"?>"
    print "<items>"
        print "<item arg=\"\" valid=\"no\">"
        print "<title>⚠️ aws cli $aws_cli is not installed !</title>"
        print "<subtitle>Make sure to install it</subtitle>"
        print "</item>"
    print "</items>"
    return
fi

ARG="$1"
length=${#ARG}
print "<?xml version=\"1.0\"?>"
print "<items>"
username=$(whoami)
nb_results=0
if [ "x$ARG" != "x" ] && [ $length -gt 1 ]
then
    arg_kebab="${ARG// /-}"
    arg_kebab=$(echo "$arg_kebab" | tr '[:upper:]' '[:lower:]')

    print "<item  arg=\"$arg_kebab\" valid=\"yes\">"
    print "<title>Create EC2 instance with name kafka-docker-playground-$username-${arg_kebab}</title>"
    print "<subtitle>This will use AWS CloudFormation to create EC2 instance</subtitle>"
    print "</item>"
    (( nb_results++ ))
else
    today=$(date +%F)
    print "<item  arg=\"$today\" valid=\"yes\">"
    print "<title>Create EC2 instance with name kafka-docker-playground-$username-${today}</title>"
    print "<subtitle>This will use AWS CloudFormation to create EC2 instance</subtitle>"
    print "</item>"
    (( nb_results++ ))
fi

if [ $nb_results -eq 0 ]
then
    print "<item uid=\"\" valid=\"no\">"
    print "<title>Something wrong happened !</title>"
    print "<subtitle>No results found... </subtitle>"
    print "<icon>error.png</icon>"
    print "</item>"
fi
print "</items>"

exit 0