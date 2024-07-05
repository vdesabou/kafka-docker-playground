instance="${args[--instance]}"

if [[ $(type code 2>&1) =~ "not found" ]]
then
    logerror "❌ code command is not found - this command requires vscode to be installed"
    exit 1
fi

if [[ $instance == *"@"* ]]
then
    instance=$(echo "$instance" | cut -d "@" -f 2)
fi
name=$(echo "${instance}" | cut -d "/" -f 1)
username=$(whoami)

playground ec2 allow-my-ip --instance "$instance"

log "👨‍💻 Open EC2 instance $name using Visual Studio code"
code --folder-uri "vscode-remote://ssh-remote+$name/home/$username"