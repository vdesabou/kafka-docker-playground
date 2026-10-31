# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
subject="${args[--subject]}"
since="${args[--since]}"
file="${args[--file]}"
topic="${args[--topic]}"
include_temporary="${args[--include-temporary]}"
json="${args[--json]}"
cluster="${args[--cluster]}"
verbose="${args[--verbose]}"

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required by 'playground schema history'"
    exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

if [[ -n "$file" ]]
then
    if [ ! -f "$file" ]
    then
        logerror "❌ file $file not found"
        exit 1
    fi
    dump="$file"
    [[ -n "$json" ]] || log "📜 Schema Registry history from $file"
else
    get_environment_used
    if [[ "$environment" == "ccloud" ]]
    then
        logerror "❌ Confluent Cloud doesn't expose the _schemas topic of its Schema Registry"
        logerror "   use the audit logs of the organization (schema registry events), or -f <dump> with a dump of a self-managed registry"
        exit 1
    fi
    maybe_cluster=()
    [[ -n "$cluster" ]] && maybe_cluster=(--cluster "$cluster")
    if [[ ! -n "$topic" ]]
    then
        # kafkastore.topic: _schemas by default, _schemas_<name>_<namespace> with CFK
        topics=$(PLAYGROUND_CLUSTER="${cluster:-$PLAYGROUND_CLUSTER}" playground get-topic-list 2> /dev/null)
        if echo "$topics" | grep -qx "_schemas"
        then
            topic="_schemas"
        else
            topic=$(echo "$topics" | grep "^_schemas" | head -1)
        fi
        if [ -z "$topic" ]
        then
            logerror "❌ no _schemas topic found: set --topic to the kafkastore.topic of the Schema Registry"
            exit 1
        fi
    fi
    [[ -n "$json" ]] || log "📜 Reading the Schema Registry history from topic $topic"
    dump="$tmp_dir/schemas.jsonl"
    playground topic consume -t "$topic" --json --max-messages 100000000 --max-characters 100000000 "${maybe_cluster[@]}" 2> /dev/null | grep '^{' > "$dump"
    if [ ! -s "$dump" ]
    then
        logerror "❌ topic $topic is empty or could not be read"
        exit 1
    fi
fi

history_args=(--file "$dump")
[[ -n "$subject" ]] && history_args+=(--subject "$subject")
[[ -n "$since" ]] && history_args+=(--since "$since")
[[ -n "$include_temporary" ]] && history_args+=(--include-temporary)
[[ -n "$json" ]] && history_args+=(--json)
python3 -I "$root_folder/tools/schema-tool/schema_history.py" "${history_args[@]}"
