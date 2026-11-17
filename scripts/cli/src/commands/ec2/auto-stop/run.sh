idle_minutes="${args[--idle-minutes]}"
dry_run="${args[--dry-run]}"
scheduled="${args[--scheduled]}"

notify_title="⏰ kafka-docker-playground ec2 auto-stop"

if [ "$idle_minutes" -lt 0 ]
then
    logerror "❌ --idle-minutes $idle_minutes must be 0 or more"
    exit 1
fi

if [[ -n "$scheduled" ]]
then
    log "⏰ ec2 auto-stop of $(date '+%Y-%m-%d %H:%M') for $(whoami), idle minutes $idle_minutes"
fi
if [[ -n "$dry_run" ]]
then
    log "🔎 dry-run: listing what would be stopped, nothing is stopped"
fi

# nobody answers at night: a missing or expired login is reported, not prompted for
if ! aws sts get-caller-identity > /dev/null 2>&1
then
    logerror "❌ the aws CLI can't authenticate (~/.aws/credentials, expired SSO session?): no instance checked"
    if [[ -n "$scheduled" ]]
    then
        scheduled_job_notify "$notify_title" "could not reach AWS (expired credentials?): no instance checked"
    fi
    exit 1
fi

# UTC timestamp of $1 seconds since the epoch, in the format of CloudWatch and of LaunchTime (compared as strings)
utc_time () {
    if [[ "$OSTYPE" == "darwin"* ]]
    then
        date -u -r "$1" '+%Y-%m-%dT%H:%M:%S'
    else
        date -u -d "@$1" '+%Y-%m-%dT%H:%M:%S'
    fi
}
now=$(date +%s)
window_start=$(utc_time $((now - idle_minutes * 60)))
window_end=$(utc_time "$now")

stopped=()
nb_running=0
for instance in $(ec2_instance_list)
do
    name=$(echo "$instance" | cut -d "/" -f 1)
    state=$(echo "$instance" | cut -d "/" -f 2)
    id=$(echo "$instance" | cut -d "/" -f 4)
    if [ "$state" != "$EC2_INSTANCE_STATE_RUNNING" ] || [ -z "$id" ]
    then
        continue
    fi
    nb_running=$((nb_running + 1))

    details=$(aws ec2 describe-instances --instance-ids "$id" --output json 2> /dev/null | jq -r '.Reservations[0].Instances[0] | [(.LaunchTime // ""), ((.Tags // []) | map(select(.Key == "playground-keep-running")) | .[0].Value // "")] | @tsv')
    launch_time=$(cut -f 1 <<< "$details")
    keep_tag=$(cut -f 2 <<< "$details" | tr '[:upper:]' '[:lower:]')

    if [ "$keep_tag" == "true" ]
    then
        log "🏷️ keeping $name ($id): tag playground-keep-running=true"
        continue
    fi

    if [ "$idle_minutes" -gt 0 ]
    then
        # LaunchTime is the last start, in UTC (2026-11-17T08:00:00+00:00)
        if [ -n "$launch_time" ] && [[ "${launch_time:0:19}" > "$window_start" ]]
        then
            log "🕐 keeping $name ($id): started at $launch_time, less than $idle_minutes minutes ago"
            continue
        fi
        max_cpu=$(aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization \
            --dimensions "Name=InstanceId,Value=$id" --start-time "${window_start}Z" --end-time "${window_end}Z" \
            --period 300 --statistics Average --output json 2> /dev/null | jq -r '[.Datapoints[].Average] | if length == 0 then "" else (max * 10 | round / 10 | tostring) end')
        if [ -z "$max_cpu" ]
        then
            # no metrics, nothing proves it is idle: kept, rather than stopping a run in progress
            log "❓ keeping $name ($id): no CloudWatch CPU metrics in the last $idle_minutes minutes"
            continue
        fi
        if awk -v c="$max_cpu" 'BEGIN { exit !(c >= 5) }'
        then
            log "🔥 keeping $name ($id): busy, CPU reached ${max_cpu}% in the last $idle_minutes minutes"
            continue
        fi
        reason="idle, CPU at most ${max_cpu}% in the last $idle_minutes minutes"
    else
        reason="--idle-minutes 0"
    fi

    if [[ -n "$dry_run" ]]
    then
        log "🔎 dry-run, would stop $name ($id): $reason"
        continue
    fi
    log "🔴 stopping $name ($id): $reason"
    if aws ec2 stop-instances --instance-ids "$id" > /dev/null 2>&1
    then
        remove_ec2_instance_from_running_list "$name"
        stopped+=("$name")
    else
        logerror "❌ failed to stop $name ($id)"
        if [[ -n "$scheduled" ]]
        then
            scheduled_job_notify "$notify_title" "failed to stop $name"
        fi
    fi
done

if [ $nb_running -eq 0 ]
then
    log "💤 no running instance"
elif [[ -z "$dry_run" ]]
then
    log "⏰ stopped ${#stopped[@]} of $nb_running running instance(s)"
    if [ ${#stopped[@]} -gt 0 ] && [[ -n "$scheduled" ]]
    then
        scheduled_job_notify "$notify_title" "stopped ${stopped[*]} (playground ec2 start to get it back)"
    fi
fi
