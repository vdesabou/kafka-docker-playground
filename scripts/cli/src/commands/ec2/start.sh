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
    id=$(echo "${instance}" | cut -d "/" -f 4)

    if [ "$state" != "$EC2_INSTANCE_STATE_RUNNING" ]
    then
        log "🟢 starting ec2 instance $name"
        aws ec2 start-instances --instance-ids $id
    else
        log "ec2 instance $name is already running"
    fi
done