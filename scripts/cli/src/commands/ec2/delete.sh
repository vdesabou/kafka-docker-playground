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
    check_if_continue
fi
for instance in "${items[@]}"
do
    name=$(echo "${instance}" | cut -d "/" -f 1)
    state=$(echo "${instance}" | cut -d "/" -f 2)

    log "❌ deleting ec2 cloudformation $name in state $state"
    aws cloudformation delete-stack --stack-name $name
    remove_ec2_instance_from_running_list "$name"
    
    pem_file="$root_folder/$name.pem"

    if [ -f "$pem_file" ]
    then
        log "🔐 deleting pem file $pem_file"
        rm -f "$pem_file"
        log "🔐 deleting pem $name on aws"
        aws ec2 delete-key-pair --key-name "$name"
    fi
done