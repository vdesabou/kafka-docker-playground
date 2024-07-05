instance="${args[--instance]}"

if [[ $instance == *"@"* ]]
then
    instance=$(echo "$instance" | cut -d "@" -f 2)
fi
name=$(echo "${instance}" | cut -d "/" -f 1)
state=$(echo "${instance}" | cut -d "/" -f 2)
ip=$(echo "${instance}" | cut -d "/" -f 3)
id=$(echo "${instance}" | cut -d "/" -f 4)

pem_file="$root_folder/$name.pem"

if [ ! -f "$pem_file" ]
then
    logerror "❌ aws ec2 pem file $pem_file file does not exist"
    exit 1
fi

group=$(aws ec2 describe-instances --instance-id "$id" --output=json | jq '.Reservations[] | .Instances[] | {SecurityGroups: .SecurityGroups}' | jq -r '.SecurityGroups[0] | .GroupName')

# delete all rules
aws ec2 revoke-security-group-ingress --group-name "$group" \
  --ip-permissions \
  "$(aws ec2 describe-security-groups --output json --group-name "$group" --query "SecurityGroups[0].IpPermissions")" > /dev/null

myip=$(dig @resolver4.opendns.com myip.opendns.com +short)
aws ec2 authorize-security-group-ingress --group-name "$group" --protocol tcp --port 22 --cidr "$myip/32" > /dev/null 2>&1 &
if [ "$state" = "$EC2_INSTANCE_STATE_STOPPED" ]
then
    log "🚀 starting the ec2 instance $name with id $id"
    aws ec2 start-instances --instance-ids "$id"
    wait_for_ec2_instance_to_be_running "$name"
    ip=$(aws ec2 describe-instances --instance-ids "$id" | jq ".Reservations[0].Instances[0].PublicDnsName" | tr -d '"')
fi

mkdir -p $HOME/.ssh
username=$(whoami)
ssh_config_file=$HOME/.ssh/config

if [ -f "$ssh_config_file" ]
then
    if grep "Host $name" -A 1 "$ssh_config_file" | grep "$ip" > /dev/null
    then
        log "🛂 ip $myip is now allowed to connect to ec2 instance $name"
        exit 0
    fi
fi

set +e
grep "$name" "$ssh_config_file" > /dev/null
if [ $? = 0 ]
then
    old_ip=$(grep -w $name -A 1 ${ssh_config_file} | awk '/HostName/ {print $2}')
    sed -e "s/$old_ip/$ip/g" ${ssh_config_file} > /tmp/tmp_file
    mv /tmp/tmp_file "${ssh_config_file}"
else
cat << EOF >> "${ssh_config_file}"

Host $name
  HostName $ip
  IdentityFile $pem_file
  User $username
  StrictHostKeyChecking no
EOF

fi
set -e

log "🛂 ip $myip is now allowed to connect to ec2 instance $name"