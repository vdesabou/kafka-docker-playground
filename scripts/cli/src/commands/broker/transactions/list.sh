state="${args[--state]}"
pattern="${args[--pattern]}"
verbose="${args[--verbose]}"

rc=0
output=$(run_kafka_admin_subcommand_tool kafka-transactions list 2>&1) || rc=$?
if [ $rc -ne 0 ] || ! echo "$output" | grep -q "^TransactionalId"
then
    logerror "❌ kafka-transactions list failed:"
    echo "$output" | grep -v -E "^[[:space:]]+at "
    exit 1
fi

rows=$(echo "$output" | sed -n '/^TransactionalId/,$p' | tail -n +2 | awk -F'\t' -v state="$state" -v pattern="$pattern" 'BEGIN { OFS = "\t" } {
    for (f = 1; f <= NF; f++) gsub(/^[ ]+|[ ]+$/, "", $f) ; }
    $1 != "" && (state == "" || tolower($4) == tolower(state)) && (pattern == "" || $1 ~ pattern) { print $1, $2, $3, $4 }')
if [[ -z "$rows" ]]
then
    log "🤷 no transaction found$([[ -n "$state$pattern" ]] && echo " matching the filters")"
    exit 0
fi
log "💱 Transactions ($(echo "$rows" | wc -l | tr -d ' '))"
{
    printf 'TRANSACTIONAL_ID\tCOORDINATOR\tPRODUCER_ID\tSTATE\n'
    echo "$rows" | sort
} | column -t -s $'\t'
if echo "$rows" | awk -F'\t' '$4 == "Ongoing"' | grep -q .
then
    log "🎓 details of an ongoing one: playground broker transactions describe --transactional-id <id>"
fi
