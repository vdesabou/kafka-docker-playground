pem_file="${args[--pem-file]}"
cloud_formation_yml_file="${args[--cloud-formation-yml-file]}"
suffix="${args[--suffix]}"
aws_region="${args[--region]}"
instance_type="${args[--instance-type]}"
ec2_size="${args[--size]}"

if [[ -n "$pem_file" ]]
then
    if [[ $pem_file == *"@"* ]]
    then
        pem_file=$(echo "$pem_file" | cut -d "@" -f 2)
    fi
elif [[ -n "$EC2_CLOUD_FORMATION_PEM_FILE" ]]
then
    pem_file="$EC2_CLOUD_FORMATION_PEM_FILE"
    if [ ! -f "$EC2_CLOUD_FORMATION_PEM_FILE" ]
    then
        logerror "❌ EC2_CLOUD_FORMATION_PEM_FILE is set with $EC2_CLOUD_FORMATION_PEM_FILE but the file does not exist"
        exit 1
    fi
else
    logerror "❌ --pem-file or EC2_CLOUD_FORMATION_PEM_FILE is required"
    exit 1
fi

if [[ -n "$cloud_formation_yml_file" ]]
then
    if [[ $cloud_formation_yml_file == *"@"* ]]
    then
        cloud_formation_yml_file=$(echo "$cloud_formation_yml_file" | cut -d "@" -f 2)
    fi
elif [[ -n "$EC2_CLOUD_FORMATION_YML_FILE" ]]
then
    cloud_formation_yml_file="$EC2_CLOUD_FORMATION_YML_FILE"
    if [ ! -f "$cloud_formation_yml_file" ]
    then
        logerror "❌ EC2_CLOUD_FORMATION_YML_FILE is set with $EC2_CLOUD_FORMATION_YML_FILE but the file does not exist"
        exit 1
    fi
else
    cloud_formation_yml_file="$root_folder/cloudformation/kafka-docker-playground.yml"
    if [ ! -f "$cloud_formation_yml_file" ]
    then
        logerror "❌ cloud_formation_yml_file is set with $cloud_formation_yml_file but the file does not exist"
        exit 1
    fi
fi


username=$(whoami)
if [[ -n "$suffix" ]]
then
    suffix_kebab="${suffix// /-}"
    suffix_kebab=$(echo "$suffix_kebab" | tr '[:upper:]' '[:lower:]')
else
    suffix_kebab=$(date +%F)
fi
name="kafka-docker-playground-${username}-${suffix_kebab}"
myip=$(dig @resolver4.opendns.com myip.opendns.com +short)
key_name=$(basename $pem_file .pem)

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

cd $tmp_dir
cp "$cloud_formation_yml_file" tmp.yml

log "👷 creating ${instance_type} instance $name in $aws_region region (${ec2_size} Gb)"
log "🌀 cloud formation file used: $cloud_formation_yml_file"
log "🔐 ec2 pem file used: $pem_file"
aws cloudformation create-stack --stack-name $name --template-body "file://tmp.yml" --region ${aws_region} --parameters ParameterKey=InstanceType,ParameterValue=${instance_type} ParameterKey=Ec2RootVolumeSize,ParameterValue=${ec2_size} ParameterKey=KeyName,ParameterValue=${key_name} ParameterKey=InstanceName,ParameterValue=$name ParameterKey=IPAddressRange,ParameterValue=${myip}/32 ParameterKey=SecretsEncryptionPassword,ParameterValue="${SECRETS_ENCRYPTION_PASSWORD}" ParameterKey=LinuxUserName,ParameterValue="${username}"
cd - > /dev/null

# ParameterKey=GithubSshKeyFile,ParameterValue="${github_ssh_key_file_content}"

wait_for_ec2_instance_to_be_running "$name"

instance="$(playground ec2 status --instance "$name" --all)"
if [ $? != 0 ] || [ -z "$instance" ]
then
    logerror "❌ failed to get instance with name $name"
    playground ec2 status --instance "$name" --all
    exit 1
fi
playground ec2 open --instance "$instance"