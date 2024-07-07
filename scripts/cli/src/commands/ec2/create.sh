cloud_formation_yml_file="${args[--cloud-formation-yml-file]}"
suffix="${args[--suffix]}"
aws_region="${args[--region]}"
instance_type="${args[--instance-type]}"
ec2_size="${args[--size]}"

username=$(whoami)
if [[ -n "$suffix" ]]
then
    suffix_kebab="${suffix// /-}"
    suffix_kebab=$(echo "$suffix_kebab" | tr '[:upper:]' '[:lower:]')
else
    suffix_kebab=$(date +%F)
fi
name="kafka-docker-playground-${username}-${suffix_kebab}"
pem_file="$root_folder/$name.pem"

# check if instance already exists
res=$(playground ec2 status --instance "$name" --all)
if [ "$res" != "" ]
then
    logerror "❌ ec2 instance $name already exists"
    logerror "use playground ec2 delete --instance $name to delete it"
    exit 1
fi

log "🔐 creating pem file $pem_file (make sure to create backup)"
aws ec2 create-key-pair --key-name "$name" --key-type rsa --key-format pem --query "KeyMaterial" --output text > $pem_file
chmod 400 $pem_file

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

wait_for_ec2_instance_to_be_running "$name"

instance="$(playground ec2 status --instance "$name" --all)"
if [ $? != 0 ] || [ -z "$instance" ]
then
    logerror "❌ failed to get instance with name $name"
    playground ec2 status --instance "$name" --all
    exit 1
fi
log "👷 ec2 instance $name is created and accesible via SSH, it will be opened with visual studio code in 5 minutes..."
log "🌀 cloud formation is still in progress (installing docker, etc...) and can be reverted after 20 minutes (i.e removing ec2 instance) in case of issue. You can check progress by checking log file output.log in root folder of ec2 instance"
sleep 300
playground ec2 open --instance "$instance"

wait_for_ec2_cloudformation_to_be_completed "$name"

playground ec2 sync-repro-folder local-to-ec2 --instance "$instance"
log "🎉 ec2 instance $name is ready!"