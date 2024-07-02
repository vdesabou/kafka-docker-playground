instance="${args[--instance]}"

if [[ $instance == *"@"* ]]
then
    instance=$(echo "$instance" | cut -d "@" -f 2)
fi
log "❌ deleting ec2 cloudformation $instance"
aws cloudformation delete-stack --stack-name $instance