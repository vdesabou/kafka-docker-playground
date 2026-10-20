group="${args[--group]}"
topic="${args[--topic]}"
to_earliest="${args[--to-earliest]}"
to_latest="${args[--to-latest]}"
to_offset="${args[--to-offset]}"
to_datetime="${args[--to-datetime]}"
shift_by="${args[--shift-by]}"
by_duration="${args[--by-duration]}"
dry_run="${args[--dry-run]}"
verbose="${args[--verbose]}"

reset_args=()
nb_specs=0
[[ -n "$to_earliest" ]] && { reset_args+=(--to-earliest); nb_specs=$((nb_specs+1)); description="to earliest"; }
[[ -n "$to_latest" ]] && { reset_args+=(--to-latest); nb_specs=$((nb_specs+1)); description="to latest"; }
[[ -n "$to_offset" ]] && { reset_args+=(--to-offset "$to_offset"); nb_specs=$((nb_specs+1)); description="to offset $to_offset"; }
[[ -n "$to_datetime" ]] && { reset_args+=(--to-datetime "$to_datetime"); nb_specs=$((nb_specs+1)); description="to datetime $to_datetime"; }
[[ -n "$shift_by" ]] && { reset_args+=(--shift-by "$shift_by"); nb_specs=$((nb_specs+1)); description="shifted by $shift_by"; }
[[ -n "$by_duration" ]] && { reset_args+=(--by-duration "$by_duration"); nb_specs=$((nb_specs+1)); description="by duration $by_duration"; }
if [ $nb_specs -ne 1 ]
then
    logerror "❌ set exactly one of --to-earliest, --to-latest, --to-offset, --to-datetime, --shift-by, --by-duration"
    exit 1
fi

if [[ -n "$topic" ]]
then
    reset_args+=(--topic "$topic")
    scope="topic $topic"
else
    reset_args+=(--all-topics)
    scope="all its topics"
fi

if [[ -n "$dry_run" ]]
then
    reset_args+=(--dry-run)
    log "🧪 Dry run: offsets of consumer group $group on $scope $description"
else
    reset_args+=(--execute)
    log "⏪ Resetting offsets of consumer group $group on $scope $description"
fi

output=$(run_kafka_admin_tool kafka-consumer-groups --reset-offsets --group "$group" "${reset_args[@]}" 2>&1) || true

# kafka-consumer-groups exits 0 on errors such as an active group, detect them from the output
error=$(echo "$output" | grep -m1 -E "^Error: |inactive|does not exist" || true)
if [ -n "$error" ]
then
    logerror "❌ Failed to reset offsets of consumer group $group: ${error#Error: }"
    if echo "$output" | grep -q "inactive"
    then
        connector_name="${group#connect-}"
        if [ "$connector_name" != "$group" ]
        then
            logerror "   $group is the group of sink connector $connector_name: use playground connector offsets reset|alter --connector $connector_name, it stops and resumes the connector for you"
        else
            logerror "   the group must have no active member: stop its consumers first (playground consumer-group describe --group $group --members)"
        fi
    fi
    exit 1
fi
echo "$output" | grep -v "^$"
if [ $(echo "$output" | grep -v "^$" | grep -vc "^GROUP ") -eq 0 ]
then
    if [[ -n "$topic" ]]
    then
        logwarn "⚠️ nothing to reset: topic $topic does not exist or has no partition"
    else
        logwarn "⚠️ nothing to reset: group $group has no committed offset (unknown group?). Use --topic to set the offsets of a new group"
    fi
    exit 1
fi

if [[ -n "$dry_run" ]]
then
    log "🧪 Nothing was changed, run again without --dry-run to apply"
else
    log "✅ Offsets of consumer group $group reset"
fi
