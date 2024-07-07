instance="${args[--instance]}"

if [[ $instance == *"@"* ]]
then
    instance=$(echo "$instance" | cut -d "@" -f 2)
fi

if [[ ! -n "$instance" ]]
then
    instance=$(playground --output-level WARN ec2 list)
    if [ "$instance" == "" ]
    then
        log "💤 No ec2 instance was found !"
        exit 1
    fi
fi

items=($instance)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --instance flag was not provided, applying command to all ec2 instances"
fi
for instance in "${items[@]}"
do
    name=$(echo "${instance}" | cut -d "/" -f 1)
    state=$(echo "${instance}" | cut -d "/" -f 2)
    ip=$(echo "${instance}" | cut -d "/" -f 3)

    pem_file="$root_folder/$name.pem"
    username=$(whoami)

    if [ ! -f "$pem_file" ]
    then
        logerror "❌ aws ec2 pem file $pem_file file does not exist"
        exit 1
    fi

    if [ "$state" != "$EC2_INSTANCE_STATE_STOPPED" ] && [ "$state" != "$EC2_INSTANCE_STATE_RUNNING" ]
    then
        log "ec2 instance $name is in state $state (not stopped and not running), skipping it"
        continue
    fi

    playground ec2 allow-my-ip --instance "$instance"
    instance="$(playground ec2 status --instance "$name" --all)"
    ip=$(echo "${instance}" | cut -d "/" -f 3)

    log "👈 Sync ec2 instance $name reproduction-models folder to local"
    rsync -cauv --filter=':- .gitignore' -e "ssh -i $pem_file -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" "$username@$ip:/home/$username/kafka-docker-playground/reproduction-models" "$root_folder"
done