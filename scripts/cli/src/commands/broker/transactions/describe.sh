transactional_id="${args[--transactional-id]}"
verbose="${args[--verbose]}"

rc=0
output=$(run_kafka_admin_subcommand_tool kafka-transactions describe --transactional-id "$transactional_id" 2>&1) || rc=$?
if [ $rc -ne 0 ] || ! echo "$output" | grep -q "^CoordinatorId"
then
    if echo "$output" | grep -q -E "TransactionalIdNotFound|could not be found"
    then
        logerror "❌ transactional id $transactional_id not found (playground broker transactions list)"
    else
        logerror "❌ kafka-transactions describe failed:"
        echo "$output" | grep -v -E "^[[:space:]]+at "
    fi
    exit 1
fi

log "💱 Transaction $transactional_id"
# one "key: value" line per column of the single row
echo "$output" | sed -n '/^CoordinatorId/,$p' | head -2 | awk -F'\t' '
    { for (f = 1; f <= NF; f++) gsub(/^[ ]+|[ ]+$/, "", $f) ; }
    NR == 1 { for (i = 1; i <= NF; i++) header[i] = $i ; n = NF }
    NR == 2 { for (i = 1; i <= n; i++) if (header[i] != "") printf "%-32s %s\n", header[i] ":", $i }'
