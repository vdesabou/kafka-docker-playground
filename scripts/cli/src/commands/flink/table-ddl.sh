topic="${args[--topic]}"
table="${args[--table]}"
schema_topic="${args[--schema-topic]}"
sink="${args[--sink]}"
field="${args[--field]}"
select_from="${args[--select-from]}"

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required to write the table"
    exit 1
fi

schema_topic="${schema_topic:-$topic}"
if [[ -z "$table" ]]
then
    table=$(echo "$topic" | sed -E 's/[^A-Za-z0-9_]/_/g')
fi

get_sr_url_and_security
subject="${schema_topic}-value"
schema=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/latest")
if ! echo "$schema" | jq -e '.schema' > /dev/null 2>&1
then
    logerror "❌ no value schema for topic $schema_topic in Schema Registry (subject $subject): $(echo "$schema" | jq -r '.message // .' 2>/dev/null | head -1)"
    logerror "   the topic needs Avro values written with the Schema Registry (io.confluent.connect.avro.AvroConverter, or playground topic produce with an Avro schema)"
    exit 1
fi

sink_args=()
if [[ -n "$sink" ]]
then
    sink_args+=(--sink)
fi
if [[ -n "$field" ]]
then
    sink_args+=(--field "$field")
fi
if [[ -n "$select_from" ]]
then
    sink_args+=(--select-from "$select_from")
fi
echo "$schema" | python3 -I "$root_folder/tools/pipeline-builder/flink_ddl.py" --table "$table" --topic "$topic" "${sink_args[@]}"
