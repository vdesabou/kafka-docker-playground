#!/bin/ksh

arg="$1"
username=$(whoami)
myip=$(dig @resolver4.opendns.com myip.opendns.com +short)
key_name=$(basename $ssh_pem_file .pem)
cp "$cloud_formation_json_file" tmp.json
aws cloudformation create-stack --stack-name kafka-docker-playground-${username}-${arg} --template-body "file://tmp.json" --region ${aws_region} --parameters ParameterKey=InstanceType,ParameterValue=${instance_type} ParameterKey=Ec2RootVolumeSize,ParameterValue=${ec2_size} ParameterKey=KeyName,ParameterValue=${key_name} ParameterKey=InstanceName,ParameterValue=kafka-docker-playground-${username}-${arg} ParameterKey=IPAddressRange,ParameterValue=${myip}/32
rm -f tmp.json
