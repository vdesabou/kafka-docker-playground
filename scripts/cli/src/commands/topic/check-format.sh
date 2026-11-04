topic="${args[--topic]}"
max_messages="${args[--max-messages]}"
from_beginning="${args[--from-beginning]}"
partition="${args[--partition]}"
offset="${args[--offset]}"
key_only="${args[--key-only]}"
value_only="${args[--value-only]}"
samples="${args[--samples]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required by playground topic check-format"
    exit 1
fi

sides="key,value"
[[ -n "$key_only" ]] && sides="key"
[[ -n "$value_only" ]] && sides="value"

classes=$(dlq_tool_classes) || exit 1

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

tool_args=(raw --topic "$topic" --max-messages "$max_messages")
[[ -n "$from_beginning" ]] && tool_args+=(--from-beginning)
[[ -n "$partition" ]] && tool_args+=(--partition "$partition")
[[ -n "$offset" ]] && tool_args+=(--offset "$offset")

# raw bytes, read with kafka-clients: a console consumer would corrupt binary keys and values
# '|| ret=$?': get_connect_image turns set -e back on in run_kafka_java_tool
ret=0
run_kafka_java_tool "$classes" DlqTool "${tool_args[@]}" > $tmp_dir/out 2> $tmp_dir/err || ret=$?

if grep -q "^DLQ_ERROR " $tmp_dir/out
then
    logerror "❌ $(grep -m1 "^DLQ_ERROR " $tmp_dir/out | cut -c11-)"
    exit 1
fi
if [ $ret -ne 0 ] || ! grep -q "^RAW_SUMMARY " $tmp_dir/out
then
    logerror "❌ could not read topic $topic"
    grep -v "^RAW_" $tmp_dir/out | tail -20
    tail -20 $tmp_dir/err
    exit 1
fi
grep "^RAW_RECORD " $tmp_dir/out | cut -c12- > $tmp_dir/records.json || true
summary=$(grep -m1 "^RAW_SUMMARY " $tmp_dir/out | cut -c13-)
read_count=$(echo "$summary" | jq -r .read)
total=$(echo "$summary" | jq -r .total)
nb_partitions=$(echo "$summary" | jq '.partitions | length')

if [ "$read_count" == "0" ]
then
    if [[ -n "$json" ]]
    then
        jq -n --argjson summary "$summary" --arg topic "$topic" '{topic: $topic, total: $summary.total, read: 0, partitions: $summary.partitions, census: {}, findings: [], problems: 0, warnings: 0}'
    else
        logwarn "⚠️ no record to read in topic $topic (total $total)"
    fi
    exit 0
fi

# the schema ids and guids of the records, looked up once each, and the <topic>-key / <topic>-value subjects
get_sr_url_and_security
echo '{"ids": {}, "guids": {}}' > $tmp_dir/schemas.json
add_schema () {
    local kind="$1" key="$2" entry="$3"
    jq --arg kind "$kind" --arg key "$key" --argjson entry "$entry" '.[$kind][$key] = $entry' $tmp_dir/schemas.json > $tmp_dir/schemas.tmp && mv $tmp_dir/schemas.tmp $tmp_dir/schemas.json
}
unreachable=""
while read -r kind key
do
    [ -z "$kind" ] && continue
    if [ "$kind" == "id" ]
    then
        path="/schemas/ids/$key"
    else
        path="/schemas/guids/$key"
    fi
    if sr_request GET "$path"
    then
        schema="$sr_response"
        id="$key"
        if [ "$kind" == "guid" ]
        then
            # a guid (schema id in a header) has its numeric id(s) per context
            id=""
            if sr_request GET "/schemas/guids/$key/ids"
            then
                id=$(echo "$sr_response" | jq -r '[.[] | select(.context == "." or .context == null)][0].id // .[0].id // empty' 2> /dev/null)
            fi
        fi
        versions="[]"
        if [ -n "$id" ] && sr_request GET "/schemas/ids/$id/versions"
        then
            versions="$sr_response"
        fi
        add_schema "${kind}s" "$key" "$(jq -n --argjson s "$schema" --argjson v "$versions" '{found: true, schemaType: ($s.schemaType // "AVRO"), schema: (if ($s.schemaType // "") == "PROTOBUF" then $s.schema else null end), versions: $v}')"
    elif [ "$sr_error_code" == "curl" ] || [ -z "$sr_error_code" ] || [[ "$sr_error_code" == 401* ]] || [[ "$sr_error_code" == 403* ]]
    then
        unreachable="${sr_error_message:-no response from $sr_url}"
        break
    else
        add_schema "${kind}s" "$key" '{"found": false}'
    fi
done < <(python3 -I "$root_folder/tools/dlq-tool/check_format.py" ids --records $tmp_dir/records.json --sides "$sides")
if [ -n "$unreachable" ]
then
    jq --arg u "$unreachable" '.unreachable = $u' $tmp_dir/schemas.json > $tmp_dir/schemas.tmp && mv $tmp_dir/schemas.tmp $tmp_dir/schemas.json
fi

echo '{}' > $tmp_dir/subjects.json
for side in key value
do
    subject="${topic}-${side}"
    entry="null"
    if sr_request GET "/subjects/$(urlencode "$subject")/versions/latest"
    then
        entry=$(echo "$sr_response" | jq '{subject, id, version, schemaType: (.schemaType // "AVRO")}')
    fi
    jq --arg side "$side" --argjson entry "$entry" '.[$side] = $entry' $tmp_dir/subjects.json > $tmp_dir/subjects.tmp && mv $tmp_dir/subjects.tmp $tmp_dir/subjects.json
done

report_args=(report --records $tmp_dir/records.json --summary "$summary" --schemas $tmp_dir/schemas.json
    --subjects $tmp_dir/subjects.json --topic "$topic" --sides "$sides" --status-out $tmp_dir/status.json)
[[ -n "$samples" ]] && report_args+=(--samples)
[[ -n "$json" ]] && report_args+=(--json)

if [[ -z "$json" ]]
then
    if [[ -n "$offset" ]]
    then
        what="around offset $offset"
    elif [[ -n "$from_beginning" ]]
    then
        what="the first ones"
    else
        what="the last ones"
    fi
    where="of each of the $nb_partitions partitions"
    [ "$nb_partitions" == "1" ] && where="of its only partition"
    [[ -n "$partition" ]] && where="of partition $partition"
    log "🔍 $topic: $read_count record(s) read of $total, $what $where"
    subjects_line=$(jq -r '[to_entries[] | select(.value != null) | "\(.value.subject) (\(.value.schemaType), latest version \(.value.version), id \(.value.id))"] | join(", ")' $tmp_dir/subjects.json)
    log "🗂️ subjects: ${subjects_line:-no ${topic}-key / ${topic}-value subject}"
fi

if ! python3 -I "$root_folder/tools/dlq-tool/check_format.py" "${report_args[@]}"
then
    logerror "❌ could not analyze the records"
    exit 1
fi

problems=$(jq -r .problems $tmp_dir/status.json)
warnings=$(jq -r .warnings $tmp_dir/status.json)
if [ "$problems" != "0" ]
then
    [[ -z "$json" ]] && logerror "❌ $problems problem(s): the records of $topic are not all in a format their converter can read"
    exit 1
fi
if [[ -z "$json" ]]
then
    if [ "$warnings" != "0" ]
    then
        logwarn "⚠️ no problem, $warnings warning(s)"
    else
        log "✅ the records of $topic are in one format per side"
    fi
fi
