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
# Build the whole file in memory before contacting any instance: a locked
# 1Password then fails before a half written file lands on the remote side.
#
# Like `playground secrets push-github`, this deliberately reads the store and
# not the environment. The instance must get what the store holds, not what the
# shell that happens to launch the command still has exported.
#
payload=""
nb=0
nb_failed=0
for name in $names
do
    if value=$(secret_get_from_store "$name" "$profile")
    then
        payload="${payload}${name}=${value}"$'\n'
        nb=$((nb+1))
    else
        logwarn "⚠️ $name could not be resolved, skipped"
        nb_failed=$((nb_failed+1))
    fi
done

if [ $nb -eq 0 ]
then
    logerror "❌ no value of profile $profile could be resolved, nothing to send"
    exit 1
fi

#
# Credentials that cannot live in the secrets store, because they are multi
# line files and not name=value pairs. They used to travel inside secrets.tar,
# which the cloud formation bootstrap decrypted on the instance; sending them
# over ssh instead is what makes that tarball removable.
#
# Each entry is <local file at repo root>:<remote path>:<mode>.
#
# The two aws ones are bind mounted into the connect container by the
# *-with-assuming-iam-role examples, hence the world readable mode: the uid
# inside the container is not the uid of the ec2 user.
#
files_to_send=(
    "aws_credentials_with_assuming_iam_role:.aws/credentials-with-assuming-iam-role:644"
    "aws_credentials_aws_account_with_assume_role:.aws/credentials_aws_account_with_assume_role:644"
    "github_ssh_key_file:.ssh/id_rsa:600"
)

available_files=()
for entry in "${files_to_send[@]}"
do
    local_file="$root_folder/${entry%%:*}"
    if [ -f "$local_file" ]
    then
        available_files+=("$entry")
    else
        logwarn "⚠️ $local_file does not exist, it will not be sent"
    fi
done

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
        #
        # umask first so the file is never readable by anyone else while it is
        # being written, then the final mode once it is complete.
        #
        if ssh -i "$pem_file" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "$username@$ip" "umask 077 && mkdir -p ~/$(dirname "$remote_path") && cat > ~/$remote_path && chmod $mode ~/$remote_path" < "$local_file"
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
