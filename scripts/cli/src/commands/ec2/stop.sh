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

ec2_resolve_instances "$instance" || exit 1
instance="$ec2_resolved_instances"
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
    id=$(echo "${instance}" | cut -d "/" -f 4)

    if [ "$state" != "$EC2_INSTANCE_STATE_STOPPED" ] && [ "$state" != "$EC2_INSTANCE_STATE_RUNNING" ]
    then
        log "ec2 instance $name is in state $state (not stopped and not running), skipping it"
        continue
    fi
    
    if [ "$state" != "$EC2_INSTANCE_STATE_STOPPED" ]
    then
        log "🔴 stopping ec2 instance $name"
        aws ec2 stop-instances --instance-ids "$id"
        remove_ec2_instance_from_running_list "$name"
    else
        log "ec2 instance $name is already stopped"
    fi
done