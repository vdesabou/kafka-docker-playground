instance="${args[--instance]}"
enable_sync_repro_folder="${args[--enable-sync-repro-folder]}"

if [[ $(type code 2>&1) =~ "not found" ]]
then
    logerror "❌ code command is not found - this command requires vscode to be installed"
    exit 1
fi

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

username=$(whoami)
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

    if [ "$state" != "$EC2_INSTANCE_STATE_STOPPED" ] && [ "$state" != "$EC2_INSTANCE_STATE_RUNNING" ]
    then
        log "ec2 instance $name is in state $state (not stopped and not running), skipping it"
        continue
    fi

    playground ec2 allow-my-ip --instance "$instance"

    if [[ -n "$enable_sync_repro_folder" ]]
    then
        instance="$(playground ec2 status --instance "$name" --all)"
        playground ec2 sync-repro-folder local-to-ec2 --instance "$instance" 
    fi

    log "👨‍💻 Open EC2 instance $name using Visual Studio code"
    log "🐚 make sure to use zsh in order to have everything working out of the box"
    code --folder-uri "vscode-remote://ssh-remote+$name/home/$username"
done