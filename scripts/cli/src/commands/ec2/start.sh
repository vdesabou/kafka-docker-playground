instance="${args[--instance]}"
pem_file="${args[--pem-file]}"

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

if [[ $instance == *"@"* ]]
then
    instance=$(echo "$instance" | cut -d "@" -f 2)
fi
name=$(echo "${instance}" | cut -d "|" -f 1)
state=$(echo "${instance}" | cut -d "|" -f 2)
#ip=$(echo "${instance}" | cut -d "|" -f 3)
id=$(echo "${instance}" | cut -d "|" -f 4)

if [ "$state" != "$EC2_INSTANCE_STATE_RUNNING" ]
then
    log "🟢 starting ec2 instance $name"
    aws ec2 start-instances --instance-ids $id
else
    log "ec2 instance $name is already running"
fi