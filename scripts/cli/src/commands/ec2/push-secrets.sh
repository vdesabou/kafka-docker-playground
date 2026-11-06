instance="${args[--instance]}"
profile="${args[--profile]:-$(get_active_secret_profile)}"
dry_run="${args[--dry-run]}"

remote_file=".playground-secrets.properties"

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

names=$(secret_store_names "$profile")
if [ -z "$names" ]
then
    logerror "❌ profile $profile is empty, there is nothing to send"
    logerror "👉 playground secrets import --file <secret.properties>"
    exit 1
fi

secret_backend_ready || exit 1

#
# Resolved from the store (not the environment), in parallel, and built in memory
# before contacting any instance: see secret_build_payload.
#
secret_build_payload "$profile" all shell
payload="$SECRET_PAYLOAD"
nb=$SECRET_PAYLOAD_NB
nb_failed=$SECRET_PAYLOAD_NB_FAILED

if [ $nb -eq 0 ]
then
    logerror "❌ no value of profile $profile could be resolved, nothing to send"
    exit 1
fi

# the credentials that are files, not name=value pairs (see SECRET_PUSH_FILES)
secret_push_available_files
available_files=("${SECRET_PUSH_AVAILABLE_FILES[@]}")

if [[ -n "$dry_run" ]]
then
    log "🔍 $nb variable(s) of profile $profile would be written to ~/$remote_file on:"
    for i in $instance
    do
        log "   👉 $(echo "$i" | cut -d "/" -f 1)"
    done
    for entry in "${available_files[@]}"
    do
        rest="${entry#*:}"
        log "🔍 $root_folder/${entry%%:*} would be sent to ~/${rest%%:*} (mode ${rest##*:})"
    done
    exit 0
fi

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

    pem_file="$root_folder/$name.pem"
    username=$(whoami)

    if [ ! -f "$pem_file" ]
    then
        logerror "❌ aws ec2 pem file $pem_file file does not exist"
        exit 1
    fi

    if [ "$state" != "$EC2_INSTANCE_STATE_RUNNING" ]
    then
        log "ec2 instance $name is in state $state (not running), skipping it"
        continue
    fi

    playground ec2 allow-my-ip --instance "$instance"
    instance="$(playground ec2 status --instance "$name" --all)"
    ip=$(echo "${instance}" | cut -d "/" -f 3)

    log "🔐 Sending $nb variable(s) of profile $profile to $name (~/$remote_file)"
    #
    # umask on the remote side rather than a chmod afterwards: the file is never
    # readable by anyone else, not even for the instant between the two commands.
    #
    if printf '%s' "$payload" | ssh -i "$pem_file" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$username@$ip" "umask 077 && cat > ~/$remote_file"
    then
        log "✅ ~/$remote_file written on $name"
        log "🎓 it is sourced by the playground .zshrc, open a new shell to pick it up"
    else
        logerror "❌ could not write ~/$remote_file on $name"
        exit 1
    fi

    for entry in "${available_files[@]}"
    do
        local_file="$root_folder/${entry%%:*}"
        rest="${entry#*:}"
        remote_path="${rest%%:*}"
        mode="${rest##*:}"

        log "🔐 Sending $(basename "$local_file") to $name (~/$remote_path)"
        remote_script=$(secret_push_file_remote_script "$remote_path" "$mode")

        if ssh -i "$pem_file" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "$username@$ip" "$remote_script" < "$local_file"
        then
            log "✅ ~/$remote_path written on $name"
        else
            logerror "❌ could not write ~/$remote_path on $name"
            exit 1
        fi
    done
done

if [ $nb_failed -gt 0 ]
then
    logwarn "⚠️ $nb_failed variable(s) could not be resolved and were left out"
fi
