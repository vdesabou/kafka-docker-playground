instance="${args[--instance]}"

if [[ $instance == *"@"* ]]
then
    instance=$(echo "$instance" | cut -d "@" -f 2)
fi
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