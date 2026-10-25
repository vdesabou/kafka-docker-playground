topic="${args[--topic]}"
connector="${args[--connector]}"
max_messages="${args[--max-messages]}"
grep_regex="${args[--grep]}"
json="${args[--json]}"
verbose="${args[--verbose]}"
output_dir="${args[--output-dir]}"
no_open="${args[--no-open]}"

resolve_dlq_topic "$topic" "$connector"

classes=$(dlq_tool_classes) || exit 1

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

tool_args=(inspect --topic "$dlq_topic" --max-messages "$max_messages")
[[ -n "$grep_regex" ]] && tool_args+=(--grep "$grep_regex")

[[ -z "$json" ]] && log "🩺 Inspecting dead letter queue $dlq_topic"
# '|| ret=$?': get_connect_image turns set -e back on in run_kafka_java_tool
ret=0
run_kafka_java_tool "$classes" DlqTool "${tool_args[@]}" > $tmp_dir/out 2> $tmp_dir/err || ret=$?

if grep -q "^DLQ_ERROR " $tmp_dir/out
then
    logerror "❌ $(grep -m1 "^DLQ_ERROR " $tmp_dir/out | cut -c11-)"
    exit 1
fi
if [ $ret -ne 0 ] || ! grep -q "^DLQ_SUMMARY " $tmp_dir/out
then
    logerror "❌ could not read dead letter queue $dlq_topic"
    grep -v "^DLQ_" $tmp_dir/out | tail -20
    tail -20 $tmp_dir/err
    exit 1
fi

grep "^DLQ_RECORD " $tmp_dir/out | cut -c12- > $tmp_dir/records.json || true
summary=$(grep -m1 "^DLQ_SUMMARY " $tmp_dir/out | cut -c13-)
total=$(echo "$summary" | jq -r .total)
read_count=$(echo "$summary" | jq -r .read)
skipped=$(echo "$summary" | jq -r .skipped_filter)

# one group per connector, stage and exception, most frequent first
jq -s '
  group_by([.errors."connector.name", .errors.stage, .errors."exception.class.name", .errors."exception.message"])
  | map({
      count: length,
      connector: .[0].errors."connector.name",
      stage: .[0].errors.stage,
      class: .[0].errors."class.name",
      exception: .[0].errors."exception.class.name",
      message: .[0].errors."exception.message",
      root_cause: .[0].root_cause,
      original_topics: (map(select(.errors.topic != null) | {topic: .errors.topic, partition: .errors.partition, offset: (.errors.offset | tonumber? // null)})
        | group_by([.topic, .partition])
        | map({topic: .[0].topic, partition: .[0].partition, first_offset: (map(.offset) | min), last_offset: (map(.offset) | max), count: length})),
      dlq_offsets: (group_by(.partition) | map({partition: .[0].partition, first: (map(.offset) | min), last: (map(.offset) | max)})),
      sample_value: .[0].value_preview
    })
  | sort_by(-.count)' $tmp_dir/records.json > $tmp_dir/groups.json

if [[ -n "$json" ]]
then
    jq -n --argjson summary "$summary" --slurpfile groups $tmp_dir/groups.json --arg topic "$dlq_topic" \
        '{topic: $topic, total: $summary.total, read: $summary.read, skipped_by_grep: $summary.skipped_filter, groups: $groups[0]}'
    exit 0
fi

if [ "$total" == "0" ]
then
    log "✅ dead letter queue $dlq_topic is empty"
    exit 0
fi

matched=$((read_count - skipped))
if [ "$read_count" -lt "$total" ]
then
    logwarn "⚠️ read the first $read_count records of $total (--max-messages $max_messages)"
fi
if [[ -n "$grep_regex" ]]
then
    log "🔎 $matched of $read_count records match --grep $grep_regex"
fi

no_headers=$(jq '[.[] | select(.exception == null) | .count] | add // 0' $tmp_dir/groups.json)
if [ "$no_headers" == "$matched" ] && [ "$matched" != "0" ]
then
    logwarn "⚠️ the records have no __connect.errors.* headers, so the error cannot be shown"
    logwarn "   set \"errors.deadletterqueue.context.headers.enable\": \"true\" on the connector, and look at the connect logs (errors.log.enable)"
fi

log "📊 $matched records in $(jq length $tmp_dir/groups.json) group(s), most frequent first"
jq -r '.[] |
  "",
  "🔢 \(.count) record(s)" + (if .connector then " of connector \(.connector)" else "" end) + (if .stage then ", stage \(.stage)" else "" end) + (if .class then " (\(.class))" else "" end),
  (if .exception then "  ❌ \(.exception): \((.message // "") | if length > 300 then .[0:300] + "…" else . end)" else "  ❌ no __connect.errors.* headers" end),
  (if .root_cause and .root_cause != ((.exception // "") + ": " + (.message // "")) then "  🌱 root cause: \(.root_cause | if length > 300 then .[0:300] + "…" else . end)" else empty end),
  (.original_topics[] | "  📍 original records: topic \(.topic) partition \(.partition) offsets \(.first_offset)..\(.last_offset) (\(.count))"),
  (.dlq_offsets[] | "  📬 dlq partition \(.partition) offsets \(.first)..\(.last)"),
  (if .sample_value then "  🔎 sample value: \(.sample_value | if length > 150 then .[0:150] + "…" else . end)" else empty end)
' $tmp_dir/groups.json
echo ""
log "🎓 replay them once the cause is fixed: playground topic dlq replay --topic $dlq_topic"

if ! command -v python3 > /dev/null 2>&1
then
    logwarn "⚠️ python3 is not on PATH: no HTML report"
    exit 0
fi
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
html_out="$output_dir/dlq-$(printf '%s' "$dlq_topic" | tr -c 'A-Za-z0-9._-' '_')-$(date '+%Y%m%d-%H%M%S').html"
if ! python3 -I "$root_folder/tools/dlq-tool/dlq_report.py" --groups $tmp_dir/groups.json --records $tmp_dir/records.json \
    --summary "$summary" --topic "$dlq_topic" --grep "$grep_regex" --max-messages "$max_messages" --html-out "$html_out"
then
    logerror "❌ could not write the HTML report"
    exit 1
fi
open_html_report "$html_out" "$no_open"
