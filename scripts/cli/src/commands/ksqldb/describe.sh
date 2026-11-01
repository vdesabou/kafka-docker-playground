source="${args[--source]}"
json="${args[--json]}"

get_ksqldb_url_and_security

if [[ -z "$source" ]]
then
    if [[ ! -t 0 ]] || [[ ! -t 1 ]]
    then
        logerror "❌ --source is required"
        exit 1
    fi
    source=$(playground get-ksqldb-source-list | fzf --prompt="🧮 stream or table: " --height=40% --reverse)
    if [[ -z "$source" ]]
    then
        logerror "❌ no stream or table selected"
        exit 1
    fi
fi

# keep a quoted name as is (case sensitive), otherwise ksqlDB uppercases it
if ! response=$(ksqldb_rest_statement "DESCRIBE $source EXTENDED;")
then
    logerror "❌ could not describe $source: $(echo "$response" | jq -r '.message // .' 2>/dev/null)"
    logerror "   🎓 playground ksqldb list shows the streams and tables"
    exit 1
fi

# statistics summed over the servers, the lag of each query is the sum over the partitions of its input topics
description=$(echo "$response" | jq '.[0].sourceDescription
    | .stats = ((.clusterStatistics // []) | group_by(.name) | map({key: .[0].name, value: (map(.value) | add)}) | from_entries)
    | .errors = ((.clusterErrorStats // []) | group_by(.name) | map({key: .[0].name, value: (map(.value) | add)}) | from_entries)
    | .lag = ((.queryOffsetSummaries // []) | map({key: (.groupId | sub("^_confluent-ksql-.*query_"; "")),
        value: ([.topicSummaries[]?.offsets[]? | (.logEndOffset - (.consumerOffset // 0))] | if length == 0 then null else add end)}) | from_entries)')

if [[ -n "$json" ]]
then
    echo "$description"
    exit 0
fi

echo "$description" | jq -r '"🧮 \(.type) \(.name): topic \(.topic) (\(.partitions) partitions, replication \(.replication)), key format \(.keyFormat), value format \(.valueFormat)"
    + (if .windowType then ", \(.windowType) windows" else "" end)
    + (if (.timestamp // "") != "" then ", timestamp column \(.timestamp)" else "" end)' | while IFS= read -r line; do log "$line"; done

echo ""
{
    printf 'FIELD\tTYPE\tKEY\n'
    echo "$description" | jq -r '.fields[] | [.name, (.schema.type + (if .schema.memberSchema then "<\(.schema.memberSchema.type)>" elif .schema.fields then "<STRUCT>" else "" end)), (if .type == "KEY" then "🔑" elif .type == "HEADER" then "header" else "" end)] | @tsv'
} | column -t -s $'\t'

for kind in writeQueries readQueries
do
    nb=$(echo "$description" | jq --arg k "$kind" '.[$k] | length')
    [ "$nb" -eq 0 ] && continue
    echo ""
    if [[ "$kind" == "writeQueries" ]]
    then
        log "✍️ Queries writing to $source"
    else
        log "📖 Queries reading from $source"
    fi
    {
        printf 'QUERY ID\tSTATE\tLAG\n'
        echo "$description" | jq -r --arg k "$kind" '. as $d | .[$k][] | [.id, (.state // "?"), (($d.lag[.id] // "-") | tostring)] | @tsv'
    } | column -t -s $'\t'
done

echo ""
if [[ "$(echo "$description" | jq '.stats | length')" -eq 0 ]]
then
    log "📊 No statistics: no query reads from or writes to $source yet"
else
    log "📊 Statistics (sum over the ksqlDB servers)"
    echo "$description" | jq -r '.stats | to_entries[] | "   \(.key): \(.value)"'
fi
if [[ "$(echo "$description" | jq '.errors | length')" -gt 0 ]]
then
    logwarn "⚠️ Errors"
    echo "$description" | jq -r '.errors | to_entries[] | "   \(.key): \(.value)"'
    logwarn "   🎓 the records that failed are in the processing log: SELECT * FROM KSQL_PROCESSING_LOG EMIT CHANGES LIMIT 10;"
fi
