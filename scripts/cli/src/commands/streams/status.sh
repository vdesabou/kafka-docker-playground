eval "containers=(${args[--container]})"
sample="${args[--sample]}"
application_id="${args[--application-id]}"
json="${args[--json]}"
verbose="${args[--verbose]}"
html="${args[--html]}"
output_dir="${args[--output-dir]:-/tmp/playground-streams}"
no_open="${args[--no-open]}"

sample_dir=""
if [[ -n "$sample" ]]
then
    case "$sample" in
        kafka_streams) sample_dir="$root_folder/tools/log-analyzer/samples/kafka-streams" ;;
    esac
    log "🧪 sample $sample: the logs of $sample_dir, not the running containers (no consumer group)"
elif ! docker info > /dev/null 2>&1
then
    logerror "❌ container engine must be running - run 'playground doctor' (or try --sample kafka_streams)"
    exit 1
fi

if [ -z "$sample_dir" ] && [ ${#containers[@]} -eq 0 ]
then
    # the instances of other/kafka-streams
    while IFS= read -r name
    do
        [ -n "$name" ] && containers+=("$name")
    done < <(docker ps -a --format '{{.Names}}' | grep -E '^streams[0-9]*$' | sort)
fi
if [ -z "$sample_dir" ] && [ ${#containers[@]} -eq 0 ]
then
    logerror "❌ no Kafka Streams container found (streams, streams2, streams3...): pass the containers of the instances with --container"
    exit 1
fi

if ! command -v python3 &>/dev/null
then
    logerror "❌ python3 is required for this command"
    exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

report_args=()
if [ -n "$sample_dir" ]
then
    for file in "$sample_dir"/*.log
    do
        report_args+=("$(basename "$file" .log)=$file")
    done
fi
for container in "${containers[@]}"
do
    status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
    if [ -z "$status" ]
    then
        logerror "❌ container $container does not exist"
        exit 1
    fi
    if [[ -n "$verbose" ]]
    then
        log_verbose_command "docker logs $container"
    fi
    docker logs "$container" > "$tmp_dir/$container.log" 2>&1
    report_args+=("$container=$tmp_dir/$container.log" --container-status "$container=$status")
done
if [[ -n "$application_id" ]]
then
    report_args+=(--application-id "$application_id")
fi

set +e
python3 -I "$root_folder/tools/streams-analyzer/streams_report.py" --json "${report_args[@]}" > "$tmp_dir/report.json"
rc=$?
set -e
if [ $rc -eq 2 ] || [ "$(jq '.applications | length' "$tmp_dir/report.json" 2>/dev/null)" == "0" ]
then
    logerror "❌ no Kafka Streams line found in the logs of ${containers[*]}${sample_dir}${application_id:+ for application.id $application_id}: the Kafka Streams library logs at INFO (org.apache.kafka.streams)"
    exit 1
elif [ $rc -ne 0 ]
then
    logerror "❌ could not analyze the logs of ${containers[*]}"
    exit 1
fi

# the consumer group of each application (group id = application.id): state, members, lag. Not for a sample
groups_json="{}"
[ -n "$sample_dir" ] && apps_for_groups="" || apps_for_groups=$(jq -r '.applications[] | select(.instances | length > 0) | .application_id' "$tmp_dir/report.json")
while IFS= read -r app
do
    [ -z "$app" ] && continue
    set +e
    state_output=$(run_kafka_admin_tool kafka-consumer-groups --describe --group "$app" --state 2>/dev/null)
    offsets_output=$(run_kafka_admin_tool kafka-consumer-groups --describe --group "$app" 2>/dev/null)
    set -e
    # GROUP COORDINATOR (ID) ASSIGNMENT-STRATEGY STATE #MEMBERS
    group_state=$(echo "$state_output" | awk -v g="$app" '$1 == g {print $(NF-1); exit}')
    group_members=$(echo "$state_output" | awk -v g="$app" '$1 == g {print $NF; exit}')
    # LAG is the 6th column, "-" without a committed offset
    group_lag=$(echo "$offsets_output" | awk -v g="$app" '$1 == g && $6 ~ /^[0-9]+$/ {sum += $6; found = 1} END {if (found) print sum}')
    groups_json=$(jq --arg app "$app" --arg state "$group_state" --arg members "$group_members" --arg lag "$group_lag" \
        '. + {($app): {state: (if $state == "" then null else $state end), members: (if $members == "" then null else ($members | tonumber? // $members) end), lag: (if $lag == "" then null else ($lag | tonumber) end)}}' <<< "$groups_json")
done <<< "$apps_for_groups"

jq --argjson groups "$groups_json" '.applications |= map(. + {consumer_group: ($groups[.application_id] // null)})' "$tmp_dir/report.json" > "$tmp_dir/report-groups.json"

html_out=""
if [[ -n "$html" ]]
then
    mkdir -p "$output_dir"
    output_dir=$(cd "$output_dir" && pwd)
    html_out="$output_dir/streams-status-$(date '+%Y%m%d-%H%M%S').html"
    if python3 -I "$root_folder/tools/streams-analyzer/streams_report.py" --from-json "$tmp_dir/report-groups.json" --html-out "$html_out"
    then
        jq --arg html "$html_out" '. + {html_report: $html}' "$tmp_dir/report-groups.json" > "$tmp_dir/report-html.json"
        mv "$tmp_dir/report-html.json" "$tmp_dir/report-groups.json"
    else
        logwarn "⚠️ could not write the HTML report"
        html_out=""
    fi
fi

# exit 1 when an instance is not RUNNING, or its container is stopped
not_running=$(jq '[.applications[].instances[] | select(.state != "RUNNING" or ((.container_status // "running") != "running"))] | length' "$tmp_dir/report-groups.json")

if [[ -n "$json" ]]
then
    cat "$tmp_dir/report-groups.json"
else
    # the text view: the JSON written above, printed by the same script
    python3 -I "$root_folder/tools/streams-analyzer/streams_report.py" "${report_args[@]}"
    while IFS=$'\t' read -r app state members lag
    do
        if [ "$state" == "null" ]
        then
            log "👥 consumer group $app: not found (the application has not joined the group yet, or it was deleted)"
        else
            lag_text="lag $lag"
            [ "$lag" == "null" ] && lag_text="no committed offset yet"
            [ "$lag" == "0" ] && lag_text="lag 0 🏁"
            log "👥 consumer group $app: $state, $members member(s), $lag_text"
        fi
    done < <(jq -r '.applications[] | select(.consumer_group != null) | [.application_id, (.consumer_group.state // "null"), (.consumer_group.members // "null"), (.consumer_group.lag // "null")] | @tsv' "$tmp_dir/report-groups.json")
    if [ "$not_running" != "0" ]
    then
        logwarn "⚠️ $not_running instance(s) not RUNNING"
    fi
    if [ -n "$html_out" ]
    then
        open_html_report "$html_out" "$no_open"
    fi
fi

if [ "$not_running" != "0" ]
then
    exit 1
fi
