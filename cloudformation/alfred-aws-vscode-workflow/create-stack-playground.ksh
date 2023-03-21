#!/bin/ksh

arg="$1"
username=$(whoami)
name="kafka-docker-playground-${username}-${arg}"
myip=$(dig @resolver4.opendns.com myip.opendns.com +short)
key_name=$(basename $ssh_pem_file .pem)
github_ssh_key_file_content=""
if [ -f ${github_ssh_key_file} ]
then
    github_ssh_key_file_content=$(cat $github_ssh_key_file)
fi

cp "$cloud_formation_yml_file" tmp.yml
aws cloudformation create-stack --stack-name $name --template-body "file://tmp.yml" --region ${aws_region} --parameters ParameterKey=InstanceType,ParameterValue=${instance_type} ParameterKey=Ec2RootVolumeSize,ParameterValue=${ec2_size} ParameterKey=KeyName,ParameterValue=${key_name} ParameterKey=InstanceName,ParameterValue=$name ParameterKey=IPAddressRange,ParameterValue=${myip}/32 ParameterKey=SecretsEncryptionPassword,ParameterValue="${SECRETS_ENCRYPTION_PASSWORD}" ParameterKey=GithubSshKeyFile,ParameterValue="${github_ssh_key_file_content}" ParameterKey=LinuxUserName,ParameterValue="${username}"
rm -f tmp.yml

sleep 240

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

    if [ "$Name" == "$name" ]
    then
        echo "Starting $Name ($InstanceId)"
        ksh ./ec2openec2.ksh "$PublicDnsName|$Name|$InstanceId|$State"
    fi
done