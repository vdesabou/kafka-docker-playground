instance="${args[--instance]}"

if [[ $instance == *"@"* ]]
then
    instance=$(echo "$instance" | cut -d "@" -f 2)
fi
name=$(echo "${instance}" | cut -d "/" -f 1)
state=$(echo "${instance}" | cut -d "/" -f 2)
id=$(echo "${instance}" | cut -d "/" -f 4)

if [ "$state" != "$EC2_INSTANCE_STATE_STOPPED" ]
then
    log "🔴 stopping ec2 instance $name"
    aws ec2 stop-instances --instance-ids $id
else
    log "ec2 instance $name is already stopped"
fi