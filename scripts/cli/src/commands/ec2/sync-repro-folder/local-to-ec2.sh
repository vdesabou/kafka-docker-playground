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
    ip=$(echo "${instance}" | cut -d "/" -f 3)

    pem_file="$root_folder/$name.pem"
    username=$(whoami)

    if [ ! -f "$pem_file" ]
    then
        logerror "❌ aws ec2 pem file $pem_file file does not exist"
        exit 1
    fi

    log "👉 Sync local reproduction-models folder to ec2 instance $name"
    rsync -cauv --filter=':- .gitignore' -e "ssh -i $pem_file -o StrictHostKeyChecking=no" "$root_folder/reproduction-models" "$username@$ip:/home/$username/kafka-docker-playground"
done