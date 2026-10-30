broker="${args[--broker]}"
topic="${args[--topic]}"
partition="${args[--partition]}"
max_transaction_timeout="${args[--max-transaction-timeout]}"
verbose="${args[--verbose]}"

if [[ -n "$partition" ]] && [[ -z "$topic" ]]
then
    logerror "❌ --partition needs --topic"
    exit 1
fi

# one search per broker, unless the search is limited to a topic
searches=()
if [[ -n "$topic" ]]
then
    search=(--topic "$topic")
    [[ -n "$partition" ]] && search+=(--partition "$partition")
    [[ -n "$broker" ]] && search+=(--broker-id "$broker")
    searches+=("${search[*]}")
    log "🔎 Searching hanging transactions on topic $topic$([[ -n "$partition" ]] && echo " partition $partition") (open for more than $max_transaction_timeout minutes)"
else
    get_broker_config_ids "$broker" || exit 1
    for id in "${broker_config_ids[@]}"
    do
        searches+=("--broker-id $id")
    done
    log "🔎 Searching hanging transactions on broker(s) $(echo "${broker_config_ids[@]}" | tr ' ' ',') (open for more than $max_transaction_timeout minutes)"
fi

rows=""
for search in "${searches[@]}"
do
    rc=0
    output=$(run_kafka_admin_subcommand_tool kafka-transactions find-hanging $search --max-transaction-timeout "$max_transaction_timeout" 2>&1) || rc=$?
    if [ $rc -ne 0 ]
    then
        logerror "❌ kafka-transactions find-hanging $search failed:"
        echo "$output" | grep -v -E "^[[:space:]]+at "
        exit 1
    fi
    if echo "$output" | grep -q "^Topic"
    then
        rows+=$(echo "$output" | sed -n '/^Topic/,$p' | tail -n +2 | awk -F'\t' 'BEGIN { OFS = "\t" } { for (f = 1; f <= NF; f++) gsub(/^[ ]+|[ ]+$/, "", $f) ; $1 = $1 } $1 != "" { print }')$'\n'
    fi
done
rows=$(echo -n "$rows" | sed '/^$/d' | sort -u)

if [[ -z "$rows" ]]
then
    log "✅ no hanging transaction"
    log "🎓 an open transaction that its coordinator still tracks is not hanging, it is aborted after transaction.timeout.ms: see them with playground broker transactions describe-producers --topic <topic>"
    exit 0
fi
logerror "❌ $(echo "$rows" | wc -l | tr -d ' ') hanging transaction(s): they hold the last stable offset, read_committed consumers are stuck"
{
    printf 'TOPIC\tPARTITION\tPRODUCER_ID\tEPOCH\tCOORDINATOR_EPOCH\tSTART_OFFSET\tLAST_TIMESTAMP\tDURATION_MIN\n'
    echo "$rows"
} | column -t -s $'\t'
log "🧹 to abort them (requires administrative privileges):"
echo "$rows" | awk -F'\t' -v cluster_flag="$(mdc_cluster_flag)" '{ printf "playground broker transactions abort --topic %s --partition %s --start-offset %s%s\n", $1, $2, $6, cluster_flag }'
exit 1
