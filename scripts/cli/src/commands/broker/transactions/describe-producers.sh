topic="${args[--topic]}"
partition="${args[--partition]}"
verbose="${args[--verbose]}"

if [[ -n "$partition" ]]
then
    partitions="$partition"
else
    partitions=$(get_topic_partition_assignment "$topic" | awk '{print $1}')
    if [[ -z "$partitions" ]]
    then
        logerror "❌ topic $topic not found"
        exit 1
    fi
fi

log "🏭 Active producers of topic $topic"
rows=""
for p in $partitions
do
    rc=0
    output=$(run_kafka_admin_subcommand_tool kafka-transactions describe-producers --topic "$topic" --partition "$p" 2>&1) || rc=$?
    if [ $rc -ne 0 ] || ! echo "$output" | grep -q "^ProducerId"
    then
        logerror "❌ kafka-transactions describe-producers failed on partition $p:"
        echo "$output" | grep -v -E "^[[:space:]]+at "
        exit 1
    fi
    rows+=$(echo "$output" | sed -n '/^ProducerId/,$p' | tail -n +2 | awk -F'\t' -v p="$p" 'BEGIN { OFS = "\t" } { for (f = 1; f <= NF; f++) gsub(/^[ ]+|[ ]+$/, "", $f) ; } $1 != "" {
        open = ($6 == "-1" || $6 == "None" || $6 == "") ? "-" : $6 " ⚠️"
        print p, $1, $2, $3, $4, $5, open
    }')$'\n'
done
rows=$(echo -n "$rows" | sed '/^$/d')
if [[ -z "$rows" ]]
then
    log "🤷 no active producer (producer state expires after transactional.id.expiration.ms / producer.id.expiration.ms)"
    exit 0
fi
{
    printf 'PARTITION\tPRODUCER_ID\tEPOCH\tCOORDINATOR_EPOCH\tLAST_SEQUENCE\tLAST_TIMESTAMP\tOPEN_TRANSACTION_START_OFFSET\n'
    echo "$rows"
} | column -t -s $'\t'
if echo "$rows" | grep -q "⚠️"
then
    log "🎓 an open transaction holds the last stable offset of its partition: read_committed consumers don't read past it until it commits, aborts or times out"
    log "   is it hanging? playground broker transactions find-hanging --topic $topic"
fi
