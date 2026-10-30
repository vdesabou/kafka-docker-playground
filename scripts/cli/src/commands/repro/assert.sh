file="${args[--file]}"
log_pattern="${args[--reproduced-if-log]}"
container="${args[--container]}"
connector_state="${args[--reproduced-if-connector-state]}"
connector="${args[--connector]}"
records_less_than="${args[--reproduced-if-records-less-than]}"
records_more_than="${args[--reproduced-if-records-more-than]}"
topic="${args[--topic]}"
command="${args[--reproduced-if-command]}"
message="${args[--message]}"
json="${args[--json]}"

nb_checks=0
for check in "$log_pattern" "$connector_state" "$records_less_than" "$records_more_than" "$command"
do
    [ -n "$check" ] && nb_checks=$((nb_checks + 1))
done
if [ $nb_checks -ne 1 ]
then
    logerror "❌ give exactly one check: --reproduced-if-log, --reproduced-if-connector-state, --reproduced-if-records-less-than, --reproduced-if-records-more-than or --reproduced-if-command (combine several with --reproduced-if-command)"
    exit 1
fi
if { [ -n "$records_less_than" ] || [ -n "$records_more_than" ]; } && [ -z "$topic" ]
then
    logerror "❌ --reproduced-if-records-less-than and --reproduced-if-records-more-than need --topic"
    exit 1
fi

if [ -z "$file" ]
then
    file=$(playground state get run.test_file)
fi
if [[ $file == *"@"* ]]
then
    file=$(echo "$file" | cut -d "@" -f 2)
fi
if [ -n "$file" ]
then
    file=$(repro_model_path "$file")
fi

# 1. the check: reproduced=1 when the problem is there
reproduced=0
if [ -n "$log_pattern" ]
then
    nb_lines=$(playground container logs --container "$container" --grep "$log_pattern" --no-follow 2> /dev/null | grep -c . || true)
    if [ "${nb_lines:-0}" -gt 0 ]
    then
        reproduced=1
        reason="$nb_lines line(s) of the $container logs match \"$log_pattern\""
    else
        reason="no line of the $container logs matches \"$log_pattern\""
    fi
elif [ -n "$connector_state" ]
then
    connector_type=$(playground state get run.connector_type)
    if [ -z "$connector" ]
    then
        connector=$(playground get-connector-list)
        if [ -z "$connector" ]
        then
            logerror "❌ no connector is running, use --connector"
            exit 1
        fi
        if [ $(echo "$connector" | wc -w) -gt 1 ]
        then
            logerror "❌ several connectors are running ($(echo $connector)), use --connector"
            exit 1
        fi
    fi
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/status\" --header \"authorization: Basic $authorization\"" > /dev/null 2>&1 || true
    else
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/status\"" > /dev/null 2>&1 || true
    fi
    states=$(echo "$curl_output" | jq -r '"connector \(.connector.state // "unknown")", (.tasks[]? | "task \(.id) \(.state)")' 2>/dev/null)
    if [ -z "$states" ] || [[ "$states" == "connector unknown" ]]
    then
        logerror "❌ could not get the status of connector $connector"
        exit 1
    fi
    matching=$(echo "$states" | grep " $connector_state$" | sed "s/ $connector_state$//" | paste -sd ',' - | sed 's/,/, /g')
    if [ -n "$matching" ]
    then
        reproduced=1
        reason="$connector_state in connector $connector: $matching"
    else
        reason="nothing $connector_state in connector $connector ($(echo "$states" | paste -sd ',' - | sed 's/,/, /g'))"
    fi
elif [ -n "$records_less_than" ] || [ -n "$records_more_than" ]
then
    count_output=$(playground topic get-number-records --topic "$topic" 2>&1 || true)
    nb_records=$(echo "$count_output" | tail -1 | tr -cd '0-9')
    # a count that fails still ends with 0: no verdict from it
    if [ -z "$nb_records" ] || echo "$count_output" | grep -qE "Error occurred|Exception"
    then
        echo "$count_output" | grep -E "Error|Exception" | head -3
        logerror "❌ could not count the records of topic $topic"
        exit 1
    fi
    if [ -n "$records_less_than" ]
    then
        if [ "$nb_records" -lt "$records_less_than" ]
        then
            reproduced=1
            reason="$nb_records record(s) in topic $topic, less than $records_less_than"
        else
            reason="$nb_records record(s) in topic $topic, not less than $records_less_than"
        fi
    else
        if [ "$nb_records" -gt "$records_more_than" ]
        then
            reproduced=1
            reason="$nb_records record(s) in topic $topic, more than $records_more_than"
        else
            reason="$nb_records record(s) in topic $topic, not more than $records_more_than"
        fi
    fi
else
    if bash -c "$command" > /dev/null 2>&1
    then
        reproduced=1
        reason="the command succeeded: $command"
    else
        reason="the command failed: $command"
    fi
fi
if [ -n "$message" ]
then
    reason="$message ($reason)"
fi

# 2. the verdict, kept with the versions it was obtained with (read by 'repro status' and 'repro export')
if [ $reproduced -eq 1 ]
then
    verdict="reproduced"
else
    verdict="not reproduced"
fi
connector_version="${CONNECTOR_TAG}"
if [ -z "$connector_version" ] && [ -n "$CONNECTOR_ZIP" ]
then
    connector_version="zip $(basename "$CONNECTOR_ZIP")"
fi
if [ -z "$connector_version" ] && [ -n "$CONNECTOR_JAR" ]
then
    connector_version="jar $(basename "$CONNECTOR_JAR")"
fi
record=$(jq -cn \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg script "$file" \
    --arg verdict "$verdict" \
    --arg reason "$reason" \
    --arg cp_version "${TAG:-}" \
    --arg connector_version "$connector_version" \
    --arg environment "$(playground state get run.environment 2> /dev/null)" \
    '{date: $date, script: $script, verdict: $verdict, reason: $reason, cp_version: $cp_version, connector_version: $connector_version, environment: $environment}')
echo "$record" >> "$root_folder/playground-repro-verdicts"

if [[ -n "$json" ]]
then
    echo "$record" | jq .
    exit 0
fi
versions="CP ${TAG:-default}"
if [ -n "$connector_version" ]
then
    versions="$versions, connector $connector_version"
fi
if [ $reproduced -eq 1 ]
then
    log "🐞 REPRODUCED: $reason ($versions)"
else
    log "✅ NOT REPRODUCED: $reason ($versions)"
fi
