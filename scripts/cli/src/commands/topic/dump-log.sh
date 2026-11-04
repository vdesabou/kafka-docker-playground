topic="${args[--topic]}"
partition="${args[--partition]}"
offset="${args[--offset]}"
broker="${args[--broker]}"
all_segments="${args[--all-segments]}"
records="${args[--records]}"
print_data="${args[--print-data]}"
all="${args[--all]}"
last="${args[--last]}"
raw="${args[--raw]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

if [[ -n "$offset" && "$offset" -lt 0 ]]
then
    logerror "❌ --offset must be 0 or more"
    exit 1
fi

get_environment_used

assignment=$(get_topic_partition_assignment "$topic")
if [[ -z "$assignment" ]]
then
    logerror "❌ topic $topic not found"
    exit 1
fi
line=$(awk -v p="$partition" '$1 == p' <<< "$assignment")
if [[ -z "$line" ]]
then
    logerror "❌ topic $topic has no partition $partition (partitions: $(awk '{print $1}' <<< "$assignment" | paste -sd, -))"
    exit 1
fi
read -r _ leader replicas isr <<< "$line"
broker_id="${broker:-$leader}"
if ! tr ',' '\n' <<< "$replicas" | grep -qx "$broker_id"
then
    logerror "❌ broker $broker_id has no replica of $topic-$partition (replicas: $replicas)"
    exit 1
fi

# the broker that holds the replica: its container, or its pod on cfk (kafka-<id>)
if [[ "$environment" == cfk* ]]
then
    target="kafka-$broker_id"
    if ! kubectl -n confluent get pod "$target" > /dev/null 2>&1
    then
        logerror "❌ pod $target of broker $broker_id not found"
        exit 1
    fi
    exec_cmd=(kubectl -n confluent exec -i "$target" --)
else
    get_broker_container_of_id "$broker_id" || exit 1
    target="$broker_id_container"
    exec_cmd=(docker exec -i -e KAFKA_OPTS= -e KAFKA_DEBUG= -e KAFKA_JMX_OPTS= "$target")
fi

# in the broker: the folder of the partition (log.dirs of the broker), its segments, and the dump of the chosen ones.
# Prints "DIR <folder>", "SEG <file> <size>", "CHOSEN <files>", then the output of kafka-dump-log
inner_script='
t="$1"; p="$2"; offset="$3"; all_segments="$4"; print_data="$5"
dirs=$(grep -hE "^log\.dirs?=" /etc/kafka/kafka.properties /opt/confluentinc/etc/kafka/kafka.properties /mnt/config/kafka.properties 2> /dev/null | head -1 | cut -d= -f2 | tr "," " ")
dir=""
for d in $dirs /var/lib/kafka/data /mnt/data/data0/logs /opt/kafka/data
do
  if [ -d "$d/$t-$p" ]; then dir="$d/$t-$p"; break; fi
done
if [ -z "$dir" ]; then echo "ERROR the folder $t-$p is not in the log dirs of this broker ($dirs)"; exit 1; fi
echo "DIR $dir"
segments=$(ls -1 "$dir" | grep -E "^[0-9]+\.log$" | sort)
if [ -z "$segments" ]; then echo "ERROR no segment in $dir"; exit 1; fi
for s in $segments; do echo "SEG $s $(stat -c %s "$dir/$s")"; done
if [ -n "$all_segments" ]; then
  chosen=$(for s in $segments; do printf "%s," "$dir/$s"; done | sed "s/,\$//")
elif [ -n "$offset" ]; then
  pick=""
  for s in $segments; do
    base=$(echo "$s" | sed "s/\.log\$//; s/^0*//"); base=${base:-0}
    if [ "$base" -le "$offset" ]; then pick="$s"; fi
  done
  if [ -z "$pick" ]; then echo "ERROR offset $offset is before the first segment (it was deleted by the retention)"; exit 1; fi
  chosen="$dir/$pick"
else
  chosen="$dir/$(echo "$segments" | tail -1)"
fi
echo "CHOSEN $chosen"
data_opt=""
[ -n "$print_data" ] && data_opt="--print-data-log"
kafka-dump-log --files "$chosen" --deep-iteration $data_opt --max-message-size 104857600 2> /dev/null
'

if [[ -n "$verbose" ]]
then
    log_verbose_command "${exec_cmd[*]} sh -s $topic $partition ... (kafka-dump-log --files <segment> --deep-iteration$( [[ -n "$print_data" ]] && echo " --print-data-log"))"
fi
# the helpers above can leave set -e on: the errors of the dump are reported below, with their message
set +e
dump=$("${exec_cmd[@]}" sh -s "$topic" "$partition" "$offset" "$all_segments" "$print_data" <<< "$inner_script" 2>&1) || true
if grep -q "^ERROR " <<< "$dump"
then
    logerror "❌ $(grep -m1 "^ERROR " <<< "$dump" | sed 's/^ERROR //')"
    exit 1
fi
dir=$(grep -m1 "^DIR " <<< "$dump" | cut -d' ' -f2-)
if [[ -z "$dir" ]]
then
    logerror "❌ could not read the log of $topic-$partition in $target:"
    tail -5 <<< "$dump" >&2
    exit 1
fi

if [[ -n "$raw" ]]
then
    grep -vE "^(DIR|SEG|CHOSEN) " <<< "$dump"
    exit 0
fi

# the dump as one JSON document: segments, then batches with their records
result=$(grep -vE "^(Dumping|Log starting offset)" <<< "$dump" | jq -R -s \
    --arg topic "$topic" --arg partition "$partition" --arg broker "$broker_id" --arg leader "$leader" --arg target "$target" '
    def field($line; $name): ($line | capture("(^| )" + $name + ": (?<v>[^ ]*)").v // null);
    def num: if . == null then null else tonumber end;
    split("\n") as $lines
    | {
        topic: $topic, partition: ($partition | tonumber), broker: ($broker | tonumber), leader: ($leader | tonumber),
        broker_is_leader: ($broker == $leader), host: $target,
        dir: ($lines[] | select(startswith("DIR ")) | .[4:]),
        segments: [$lines[] | select(startswith("SEG ")) | split(" ") | {file: .[1], base_offset: (.[1] | sub("\\.log$"; "") | tonumber), size: (.[2] | tonumber)}],
        read: ([$lines[] | select(startswith("CHOSEN ")) | .[7:] | split(",")[] | split("/")[-1]]),
        batches: (reduce ($lines[] | select(startswith("baseOffset: ") or startswith("| offset: "))) as $l ([];
          if ($l | startswith("baseOffset: ")) then
            . + [{
              base_offset: (field($l; "baseOffset") | num), last_offset: (field($l; "lastOffset") | num),
              count: (field($l; "count") | num), producer_id: (field($l; "producerId") | num),
              producer_epoch: (field($l; "producerEpoch") | num), base_sequence: (field($l; "baseSequence") | num),
              transactional: (field($l; "isTransactional") == "true"), control: (field($l; "isControl") == "true"),
              codec: field($l; "compresscodec"), size: (field($l; "size") | num), position: (field($l; "position") | num),
              timestamp: ((field($l; "CreateTime") // field($l; "LogAppendTime")) | num),
              timestamp_type: (if field($l; "LogAppendTime") then "LogAppendTime" else "CreateTime" end),
              marker: null, records: []
            }]
          else
            (.[-1].records += [{
              offset: (field($l; "offset") | num),
              key_size: (field($l; "keySize") | num), value_size: (field($l; "valueSize") | num),
              headers: ($l | capture("headerKeys: \\[(?<h>[^]]*)\\]").h // ""),
              payload: ($l | capture(" payload: (?<p>.*)$").p // null)
            }])
            | (if ($l | test("endTxnMarker: ")) then .[-1].marker = ($l | capture("endTxnMarker: (?<m>[A-Z]+)").m) else . end)
          end))
      }
    | . as $r
    | .summary = {
        batches: (.batches | length),
        records: ([.batches[] | select(.control | not) | .count] | add // 0),
        first_offset: (.batches[0].base_offset // null), last_offset: (.batches[-1].last_offset // null),
        commit_markers: ([.batches[] | select(.marker == "COMMIT")] | length),
        abort_markers: ([.batches[] | select(.marker == "ABORT")] | length),
        transactional_batches: ([.batches[] | select(.transactional and (.control | not))] | length),
        codecs: ([.batches[] | select(.control | not) | .codec] | group_by(.) | map({codec: .[0], batches: length})),
        largest_batch: ([.batches[] | select(.control | not)] | max_by(.size) // null | if . then {base_offset, size} else null end),
        largest_record: ([.batches[] | .records[] | select(.value_size != null)] | max_by(.value_size) // null | if . then {offset, value_size} else null end),
        first_timestamp: ([.batches[].timestamp | select(. != null and . > 0)] | min),
        last_timestamp: ([.batches[].timestamp | select(. != null and . > 0)] | max),
        producers: (.batches | group_by(.producer_id) | map(
          . as $b
          | ([$b[] | select(.control) ] | last) as $last_marker
          | ([$b[] | select(.transactional and (.control | not))] | last) as $last_data
          | {
              producer_id: $b[0].producer_id,
              epochs: ([$b[].producer_epoch] | unique),
              first_offset: $b[0].base_offset, last_offset: $b[-1].last_offset,
              batches: ([$b[] | select(.control | not)] | length),
              records: ([$b[] | select(.control | not) | .count] | add // 0),
              transactional: ([$b[] | select(.transactional)] | length > 0),
              commits: ([$b[] | select(.marker == "COMMIT")] | length),
              aborts: ([$b[] | select(.marker == "ABORT")] | length),
              open_transaction: (if $last_data == null then null
                                 elif $last_marker == null or $last_marker.base_offset < $last_data.base_offset then {from_offset: ([$b[] | select(.transactional and (.control | not) and (.base_offset > ($last_marker.base_offset // -1)))][0].base_offset), last_offset: $last_data.last_offset}
                                 else null end)
            }) | map(select(.producer_id != -1)))
      }
    | .summary.open_transactions = [.summary.producers[] | select(.open_transaction != null) | {producer_id, from_offset: .open_transaction.from_offset}]
')
if [[ -z "$result" ]]
then
    logerror "❌ could not read the dump of $topic-$partition"
    exit 1
fi

if [[ -n "$json" ]]
then
    printf '%s\n' "$result"
    exit 0
fi

# the human view: where, the digest, then the batches (the last ones, the ones around --offset, or all)
jq -r '
    def human: if . == null then "-" elif . >= 1048576 then "\((. / 104857.6 | floor) / 10) MB" elif . >= 1024 then "\((. / 102.4 | floor) / 10) KB" else "\(.) B" end;
    def ts: if . == null or . <= 0 then "-" else (. / 1000 | floor | localtime | strftime("%Y-%m-%d %H:%M:%S")) end;
    "📂 \(.topic)-\(.partition) on broker \(.broker)\(if .broker_is_leader then " (leader)" else " (follower, leader \(.leader))" end) in \(.host): \(.dir)",
    "   \(.segments | length) segment(s): " + ([.segments[] | "\(.file) (\(.size | human))"] | join(", ")) + "; read: " + (.read | join(", ")),
    (.summary as $s | if $s.batches == 0 then "🧮 no batch in the segment(s) read (empty, or every record was deleted by the retention / compaction)" else
      "🧮 \($s.batches) batch(es), \($s.records) record(s), offsets \($s.first_offset)-\($s.last_offset), \($s.first_timestamp | ts) → \($s.last_timestamp | ts)",
      "   compression: " + ([$s.codecs[] | "\(.codec) (\(.batches))"] | join(", ")) + "; largest batch \($s.largest_batch.size | human) at offset \($s.largest_batch.base_offset)" + (if $s.largest_record then ", largest record value \($s.largest_record.value_size | human) at offset \($s.largest_record.offset)" else "" end),
      "   transactions: \($s.transactional_batches) transactional batch(es), \($s.commit_markers) COMMIT and \($s.abort_markers) ABORT marker(s)"
    end)
' <<< "$result" | while IFS= read -r l; do log "$l"; done

jq -r '
    .summary.producers[] |
    "   producer \(.producer_id) (epoch\(if (.epochs | length) > 1 then "s" else "" end) \(.epochs | map(tostring) | join(",")))  offsets \(.first_offset)-\(.last_offset), \(.records) record(s) in \(.batches) batch(es)" +
    (if .transactional then ", transactional: \(.commits) commit(s), \(.aborts) abort(s)" + (if .open_transaction then ", ⚠️ open since offset \(.open_transaction.from_offset)" else "" end) else ", idempotent" end)
' <<< "$result"

open=$(jq -r '.summary.open_transactions | length' <<< "$result")
if [ "$open" -gt 0 ]
then
    jq -r '.summary.open_transactions[] | "⚠️ producer \(.producer_id): transactional records from offset \(.from_offset) with no COMMIT / ABORT marker after them in the segment(s) read: an open (or hanging) transaction. read_committed consumers stop before offset \(.from_offset) (the last stable offset) until it ends"' <<< "$result" | while IFS= read -r l; do logwarn "$l"; done
    logwarn "   👉 playground broker transactions find-hanging (and describe-producers --topic '"$topic"'), then broker transactions abort if it never ends; a still running transaction is normal"
fi

# the batches to show
select_filter='.batches[-($last):]'
title="last $last batch(es)"
if [[ -n "$all" ]]
then
    select_filter='.batches'
    title="all the batches"
elif [[ -n "$offset" ]]
then
    select_filter='(.batches | map(.last_offset >= ($offset | tonumber)) | index(true)) as $i | if $i == null then [] else .batches[([$i - 3, 0] | max):($i + 4)] end'
    title="the batches around offset $offset"
fi
log "📦 $title"
jq -r --argjson last "$last" --arg offset "$offset" --arg records "$records" "
    def human: if . == null then \"-\" elif . >= 1048576 then \"\\((. / 104857.6 | floor) / 10) MB\" elif . >= 1024 then \"\\((. / 102.4 | floor) / 10) KB\" else \"\\(.) B\" end;
    def ts: if . == null or . <= 0 then \"-\" else (. / 1000 | floor | localtime | strftime(\"%Y-%m-%d %H:%M:%S\")) end;
    \"   offsets        count  producer     kind             codec   size       \\(.batches[0].timestamp_type // \"CreateTime\")\",
    ($select_filter | .[] |
      (\"   \\(if .base_offset == .last_offset then \"\\(.base_offset)\" else \"\\(.base_offset)-\\(.last_offset)\" end | . + \"               \" | .[0:14] ) \\(.count | tostring | . + \"      \" | .[0:6]) \\(\"\\(.producer_id)/\\(.producer_epoch)\" | . + \"            \" | .[0:12]) \\(if .marker then (if .marker == \"COMMIT\" then \"✅ COMMIT marker \" else \"❌ ABORT marker  \" end) elif .transactional then \"transactional   \" else \"-               \" end) \\(.codec | . + \"        \" | .[0:7]) \\(.size | human | . + \"          \" | .[0:10]) \\(.timestamp | ts)\"),
      (if \$records != \"\" and (.control | not) then (.records[] | \"      | \\(.offset)  key \\(if .key_size < 0 then \"null\" else (.key_size | human) end)  value \\(if .value_size < 0 then \"null (tombstone)\" else (.value_size | human) end)\\(if .headers != \"\" then \"  headers [\\(.headers)]\" else \"\" end)\\(if .payload then \"  \\(.payload | if length > 200 then .[0:200] + \"…\" else . end)\" else \"\" end)\") else empty end)
    )
" <<< "$result"
