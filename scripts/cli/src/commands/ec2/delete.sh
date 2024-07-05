instance="${args[--instance]}"

if [[ $instance == *"@"* ]]
then
    instance=$(echo "$instance" | cut -d "@" -f 2)
fi
name=$(echo "${instance}" | cut -d "|" -f 1)
state=$(echo "${instance}" | cut -d "|" -f 2)

log "❌ deleting ec2 cloudformation $name in state $state"
aws cloudformation delete-stack --stack-name $name

pem_file="$root_folder/$name.pem"

if [ -f "$pem_file" ]
then
    log "🔐 deleting pem file $pem_file"
    rm -f "$pem_file"
    log "🔐 deleting pem $name on aws"
    aws ec2 delete-key-pair --key-name "$name"
fi