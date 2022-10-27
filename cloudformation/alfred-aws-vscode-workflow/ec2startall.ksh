#!/bin/ksh

username=$(whoami)
name="kafka-docker-playground-${username}"

for row in $($aws_cli ec2 describe-instances | /usr/local/bin/jq '[.Reservations | .[] | .Instances | .[] | {KeyName: .KeyName, LaunchTime: .LaunchTime, PublicDnsName: .PublicDnsName, InstanceId: .InstanceId, InstanceType: .InstanceType,State: .State.Name, Name: (.Tags[]|select(.Key=="Name")|.Value)}]' | /usr/local/bin/jq -r '.[] | @base64'); do
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
        echo "Starting $Name ($InstanceId)"
        #$aws_cli ec2 start-instances --instance-ids $InstanceId &
        ksh ./ec2openec2.ksh "$PublicDnsName|$Name|$InstanceId|$State"
    fi
done

exit 0
