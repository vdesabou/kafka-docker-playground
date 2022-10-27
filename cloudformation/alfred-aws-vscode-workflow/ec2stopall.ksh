#!/bin/ksh

username=$(whoami)
name="kafka-docker-playground-${username}"

for row in $($aws_cli ec2 describe-instances | /usr/local/bin/jq '[.Reservations | .[] | .Instances | .[] | select(.State.Name=="running") | {KeyName: .KeyName, LaunchTime: .LaunchTime, PublicDnsName: .PublicDnsName, InstanceId: .InstanceId, InstanceType: .InstanceType,State: .State.Name, Name: (.Tags[]|select(.Key=="Name")|.Value)}]' | /usr/local/bin/jq -r '.[] | @base64'); do
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

    if [[ $Name = $name* ]]
    then
        echo "Stopping $Name ($InstanceId)"
        $aws_cli ec2 stop-instances --instance-ids $InstanceId &
    fi
done

exit 0
