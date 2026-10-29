broker="${args[--broker]}"
key="${args[--key]}"
all="${args[--all]}"
verbose="${args[--verbose]}"

get_broker_config_ids "$broker" || exit 1

if [[ -n "$key" ]]
then
    if [[ -n "$broker" ]]
    then
        log "🔎 Value of $key on broker $broker"
    else
        log "🔎 Value of $key on each broker"
    fi
    key_regex="${key//./\\.}"
    found=0
    for id in "${broker_config_ids[@]}"
    do
        output=$(run_quota_kafka_configs "$(broker_config_entity "$id")" --describe --all) || exit 1
        line=$(echo "$output" | grep -E "^[[:space:]]*${key_regex}=" | head -1)
        if [[ -z "$line" ]]
        then
            continue
        fi
        if [ $found -eq 0 ]
        then
            printf '%-8s %-20s %s\n' "BROKER" "VALUE" "SOURCE"
            found=1
        fi
        value=$(echo "$line" | sed -E "s/^[[:space:]]*${key_regex}=(.*) sensitive=(true|false) synonyms=\{.*\}$/\1/")
        synonyms=$(echo "$line" | sed -E 's/.* synonyms=\{(.*)\}$/\1/')
        source="${synonyms%%:*}"
        if [[ -z "$source" ]]
        then
            # no value and no default: another key gives it (e.g. log.retention.hours for log.retention.ms)
            value="(not set)"
            source="-"
        elif echo "$line" | grep -q " sensitive=true "
        then
            value="(sensitive)"
        fi
        printf '%-8s %-20s %s\n' "$id" "$value" "$source"
    done
    if [ $found -eq 0 ]
    then
        logerror "❌ $key is not a broker config, check its name ('playground broker config get --all' lists them)"
        exit 1
    fi
    exit 0
fi

if [[ -n "$all" ]]
then
    for id in "${broker_config_ids[@]}"
    do
        log "📜 All configs of broker $id"
        run_quota_kafka_configs "$(broker_config_entity "$id")" --describe --all | grep -v -E "are:$" || exit 1
    done
    exit 0
fi

# dynamic configs only: the cluster-wide default (unless --broker), then the ones of each broker
targets=()
[[ -z "$broker" ]] && targets+=("")
targets+=("${broker_config_ids[@]}")
for id in "${targets[@]}"
do
    if [[ -n "$id" ]]
    then
        log "🔎 Dynamic configs of broker $id"
    else
        log "🔎 Cluster-wide dynamic configs (default of all brokers)"
    fi
    output=$(run_quota_kafka_configs "$(broker_config_entity "$id")" --describe) || exit 1
    output=$(echo "$output" | grep -v -E "are:$" || true)
    if [[ -n "$output" ]]
    then
        echo "$output"
    else
        log "🤷 none, set one with playground broker config set"
    fi
done
