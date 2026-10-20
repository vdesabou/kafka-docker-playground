topic="${args[--topic]}"
connector="${args[--connector]}"
to="${args[--to]}"
max_messages="${args[--max-messages]}"
grep_regex="${args[--grep]}"
keep_error_headers="${args[--keep-error-headers]}"
dry_run="${args[--dry-run]}"
verbose="${args[--verbose]}"

resolve_dlq_topic "$topic" "$connector"

if [ "$to" == "$dlq_topic" ]
then
    logerror "❌ --to is the dead letter queue itself"
    exit 1
fi

classes=$(dlq_tool_classes) || exit 1

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

tool_args=(replay --topic "$dlq_topic" --max-messages "$max_messages")
[[ -n "$to" ]] && tool_args+=(--to "$to")
[[ -n "$grep_regex" ]] && tool_args+=(--grep "$grep_regex")
[[ -n "$keep_error_headers" ]] && tool_args+=(--keep-error-headers)
[[ -n "$dry_run" ]] && tool_args+=(--dry-run)

destination="${to:-the original topics (__connect.errors.topic header)}"
if [[ -n "$dry_run" ]]
then
    log "🧪 Dry run: records of dead letter queue $dlq_topic that would be replayed to $destination"
else
    log "🔁 Replaying dead letter queue $dlq_topic to $destination"
fi
# '|| ret=$?': get_connect_image turns set -e back on in run_kafka_java_tool
ret=0
run_kafka_java_tool "$classes" DlqTool "${tool_args[@]}" > $tmp_dir/out 2> $tmp_dir/err || ret=$?

if grep -q "^DLQ_ERROR " $tmp_dir/out
then
    logerror "❌ $(grep -m1 "^DLQ_ERROR " $tmp_dir/out | cut -c11-)"
    tail -20 $tmp_dir/err
    exit 1
fi
if [ $ret -ne 0 ] || ! grep -q "^DLQ_SUMMARY " $tmp_dir/out
then
    logerror "❌ could not replay dead letter queue $dlq_topic"
    grep -v "^DLQ_" $tmp_dir/out | tail -20
    tail -20 $tmp_dir/err
    exit 1
fi

summary=$(grep -m1 "^DLQ_SUMMARY " $tmp_dir/out | cut -c13-)
total=$(echo "$summary" | jq -r .total)
read_count=$(echo "$summary" | jq -r .read)
replayed=$(echo "$summary" | jq -r .replayed)
skipped_filter=$(echo "$summary" | jq -r .skipped_filter)
skipped_no_topic=$(echo "$summary" | jq -r .skipped_no_topic)

if [ "$total" == "0" ]
then
    log "✅ dead letter queue $dlq_topic is empty, nothing to replay"
    exit 0
fi
if [ "$read_count" -lt "$total" ]
then
    logwarn "⚠️ read the first $read_count records of $total (--max-messages $max_messages)"
fi
if [ "$skipped_filter" != "0" ]
then
    log "🔎 $skipped_filter records do not match --grep $grep_regex and were skipped"
fi
if [ "$skipped_no_topic" != "0" ]
then
    logwarn "⚠️ $skipped_no_topic records have no __connect.errors.topic header and were skipped: use --to <topic> (or enable errors.deadletterqueue.context.headers.enable on the connector)"
fi
echo "$summary" | jq -r '.targets | to_entries[] | "  📤 \(.value) record(s) to topic \(.key)"'
if [[ -n "$dry_run" ]]
then
    log "🧪 $replayed records would be replayed, run again without --dry-run to replay them"
else
    log "✅ $replayed records replayed"
    if [[ -z "$to" ]]
    then
        log "🎓 the sink connector reads them again from its topics: check the dead letter queue with playground topic dlq inspect --topic $dlq_topic"
    fi
fi
