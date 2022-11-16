#!/bin/ksh

arg="$1"
username=$(whoami)
myip=$(dig @resolver4.opendns.com myip.opendns.com +short)
key_name=$(basename $ssh_pem_file .pem)
github_ssh_key_file_content=""
if [ -f ${github_ssh_key_file} ]
then
    github_ssh_key_file_content=$(cat $github_ssh_key_file)
fi

cp "$cloud_formation_json_file" tmp.json
aws cloudformation create-stack --stack-name kafka-docker-playground-${username}-${arg} --template-body "file://tmp.json" --region ${aws_region} --parameters ParameterKey=InstanceType,ParameterValue=${instance_type} ParameterKey=Ec2RootVolumeSize,ParameterValue=${ec2_size} ParameterKey=KeyName,ParameterValue=${key_name} ParameterKey=InstanceName,ParameterValue=kafka-docker-playground-${username}-${arg} ParameterKey=IPAddressRange,ParameterValue=${myip}/32 ParameterKey=SecretsEncryptionPassword,ParameterValue="${SECRETS_ENCRYPTION_PASSWORD}" ParameterKey=GithubSshKeyFile,ParameterValue="${github_ssh_key_file_content}"
rm -f tmp.json
