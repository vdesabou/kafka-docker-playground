broker="${args[--broker]}"
key="${args[--key]}"
all="${args[--all]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

get_broker_config_ids "$broker" || exit 1

# one kafka-configs call for --broker, or for every broker and the cluster-wide default
entity=$'--entity-type\tbrokers'
[[ -n "$broker" ]] && entity=$(broker_config_entity "$broker")
describe_args=(--describe)
[[ -n "$key" || -n "$all" ]] && describe_args+=(--all)
output=$(run_quota_kafka_configs "$entity" "${describe_args[@]}") || exit 1
configs=$(echo "$output" | parse_broker_configs)

# JSON array of "<a>\t<b>..." lines ($1) with the field names ($2: space separated, "?" suffix = null when empty,
# "#" suffix = number, "!" suffix = boolean)
function tsv_to_json () {
    echo -n "$1" | jq -R -s --arg fields "$2" '($fields | split(" ")) as $names | split("\n") | map(select(length > 0) | split("\t") as $row | [range(0; $names | length)] | map(
        ($names[.]) as $n | ($row[.] // "") as $v |
        if ($n | endswith("?")) then { ($n | rtrimstr("?")): (if $v == "" then null else $v end) }
        elif ($n | endswith("#")) then { ($n | rtrimstr("#")): ($v | tonumber? // $v) }
        elif ($n | endswith("!")) then { ($n | rtrimstr("!")): ($v == "true") }
        else { ($n): $v } end) | add)'
}

if [[ -n "$key" ]]
then
    rows=""
    for id in "${broker_config_ids[@]}"
    do
        # \037 between the fields: read collapses empty fields separated by tabs
        line=$(echo "$configs" | awk -F'\t' -v b="$id" -v k="$key" 'BEGIN { OFS = "\037" } $1 == b && $2 == k { print $3, $4, $5 ; exit }')
        [[ -z "$line" ]] && continue
        IFS=$'\037' read -r value sensitive source <<< "$line"
        from=""
        if [[ -z "$source" ]]
        then
            value=""
            if [[ "$key" =~ \.(ms|seconds|minutes|hours)$ ]]
            then
                # a time key that is not set takes its value from a sibling key (log.retention.ms from
                # log.retention.hours): Kafka uses the most precise unit that is set
                from=$(echo "$configs" | awk -F'\t' -v b="$id" -v k="$key" -v base="${key%.*}" '
                    BEGIN { rank["ms"] = 1 ; rank["seconds"] = 2 ; rank["minutes"] = 3 ; rank["hours"] = 4 }
                    $1 == b && $2 != k && $5 != "" {
                        u = $2 ; sub(/.*\./, "", u) ; p = substr($2, 1, length($2) - length(u) - 1)
                        if (p == base && (u in rank) && (best == "" || rank[u] < best)) { best = rank[u] ; found = $2 "=" $3 }
                    }
                    END { print found }')
            fi
        elif [[ "$sensitive" == "true" ]]
        then
            value=""
        fi
        rows+="$id"$'\037'"$value"$'\037'"$source"$'\037'"$sensitive"$'\037'"$from"$'\n'
    done
    if [[ -z "$rows" ]]
    then
        logerror "❌ $key is not a broker config, check its name ('playground broker config get --all' lists them)"
        exit 1
    fi
    if [[ -n "$json" ]]
    then
        tsv_to_json "$(echo -n "$rows" | tr '\037' '\t')" "broker# value? source? sensitive! from?" | jq --arg key "$key" '{ key: $key, brokers: . }'
        exit 0
    fi
    if [[ -n "$broker" ]]
    then
        log "🔎 Value of $key on broker $broker"
    else
        log "🔎 Value of $key on each broker"
    fi
    {
        printf 'BROKER\tVALUE\tSOURCE\n'
        echo -n "$rows" | while IFS=$'\037' read -r id value source sensitive from
        do
            if [[ -z "$source" ]]
            then
                value="(not set)"
                [[ -n "$from" ]] && value="(not set, from $from)"
            elif [[ "$sensitive" == "true" ]]
            then
                value="(sensitive)"
            fi
            printf '%s\t%s\t%s\n' "$id" "$value" "${source:--}"
        done
    } | column -t -s $'\t'
    exit 0
fi

if [[ -n "$all" ]]
then
    if [[ -n "$json" ]]
    then
        for id in "${broker_config_ids[@]}"
        do
            tsv_to_json "$(echo "$configs" | awk -F'\t' -v b="$id" 'BEGIN { OFS = "\t" } $1 == b { if ($4 == "true" || $3 == "null") $3 = "" ; print $2, $3, $5, $4 }')" "key value? source? sensitive!" \
                | jq --argjson broker "$id" '{ broker: $broker, configs: (map({ (.key): del(.key) }) | add // {}) }'
        done | jq -s '{ brokers: . }'
        exit 0
    fi
    for id in "${broker_config_ids[@]}"
    do
        log "📜 All configs of broker $id"
        echo "$configs" | awk -F'\t' -v b="$id" '$1 == b { print "  " $6 }'
    done
    exit 0
fi

# dynamic configs only: the cluster-wide default (unless --broker), then the ones of each broker
targets=()
[[ -z "$broker" ]] && targets+=("default")
targets+=("${broker_config_ids[@]}")
if [[ -n "$json" ]]
then
    for id in "${targets[@]}"
    do
        tsv_to_json "$(echo "$configs" | awk -F'\t' -v b="$id" 'BEGIN { OFS = "\t" } $1 == b { if ($4 == "true" || $3 == "null") $3 = "" ; print $2, $3 }')" "key value?" \
            | jq --arg id "$id" '{ id: $id, configs: (map({ (.key): .value }) | add // {}) }'
    done | jq -s '{
        cluster_wide: (map(select(.id == "default")) | if length == 0 then null else .[0].configs end),
        brokers: map(select(.id != "default") | { broker: (.id | tonumber), configs })
    }'
    exit 0
fi
for id in "${targets[@]}"
do
    if [[ "$id" != "default" ]]
    then
        log "🔎 Dynamic configs of broker $id"
    else
        log "🔎 Cluster-wide dynamic configs (default of all brokers)"
    fi
    lines=$(echo "$configs" | awk -F'\t' -v b="$id" '$1 == b { print "  " $6 }')
    if [[ -n "$lines" ]]
    then
        echo "$lines"
    else
        log "🤷 none, set one with playground broker config set"
    fi
done
