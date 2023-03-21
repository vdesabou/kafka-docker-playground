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

if [ ! -f /usr/local/bin/code ]
then
    print "<?xml version=\"1.0\"?>"
    print "<items>"
        print "<item arg=\"\" valid=\"no\">"
        print "<title>⚠️ Vs Code cli /usr/local/bin/code is not installed !</title>"
        print "<subtitle>Make sure to have Visual Studio Code installed </subtitle>"
        print "</item>"
    print "</items>"
    return
fi

if [ ! -f /usr/local/bin/jq ]
then
    print "<?xml version=\"1.0\"?>"
    print "<items>"
        print "<item arg=\"\" valid=\"no\">"
        print "<title>⚠️ jq /usr/local/bin/jq is not installed !</title>"
        print "<subtitle>Make sure to have Visual Studio Code installed </subtitle>"
        print "</item>"
    print "</items>"
    return
fi

username=$(whoami)
name="kafka-docker-playground-${username}"

nb_results=0
print "<?xml version=\"1.0\"?>"
print "<items>"
for row in $($aws_cli ec2 describe-instances | /usr/local/bin/jq '[.Reservations | .[] | .Instances | .[] | select(.State.Name!="terminated") | {KeyName: .KeyName, LaunchTime: .LaunchTime, PublicDnsName: .PublicDnsName, InstanceId: .InstanceId, InstanceType: .InstanceType,State: .State.Name, Name: (.Tags[]|select(.Key=="Name")|.Value)}]' | /usr/local/bin/jq -r '.[] | @base64'); do
    _jq() {
     echo ${row} | base64 --decode | /usr/local/bin/jq -r ${1}
    }

    KeyName=$(echo $(_jq '.KeyName'))
    LaunchTime=$(echo $(_jq '.LaunchTime'))
    PublicDnsName=$(echo $(_jq '.PublicDnsName'))
    Name=$(echo $(_jq '.Name'))
    InstanceId=$(echo $(_jq '.InstanceId'))
    InstanceType=$(echo $(_jq '.InstanceType'))
    State=$(echo $(_jq '.State'))

    if [ "$only_see_your_instance" = "1" ] && [[ $Name != $name* ]]
    then
        continue
    fi

    if [ "$State" = "stopped" ]
    then
        print "<item uid=\"${Name}\" arg=\"$PublicDnsName|$Name|$InstanceId|$State\" valid=\"yes\">"
        print "<title>$Name 🛑 $State</title>"
    elif [ "$State" = "stopping" ] || [ "$State" = "pending" ]
    then
        print "<item uid=\"${Name}\" valid=\"no\">"
        print "<title>$Name ⌛ $State</title>"
    else
        print "<item uid=\"${Name}\" arg=\"$PublicDnsName|$Name|$InstanceId|$State\" valid=\"yes\">"
        print "<title>$Name ✅ $State</title>"
    fi
    print "<subtitle>🕐 $LaunchTime 🔑 $KeyName 💻 $InstanceType 🔢 $InstanceId</subtitle>"
    print "<icon>aws.png</icon>"
    print "</item>"
    (( nb_results++ ))
done

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
