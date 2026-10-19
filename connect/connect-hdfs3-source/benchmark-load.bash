#!/bin/bash
# load for 'playground connector benchmark': avro files of {"f1":"benchmark message <i>"} records written to hdfs in the
# layout of the hdfs3 sink (<topics.dir>/<topic>/<partition>/<topic>+0+<start>+<end>.avro), read back by the hdfs3 source
# connector (see "Benchmark" in README.md)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

benchmark_load_args "$@"
format=$(jq -r '."format.class" // empty' "$BENCHMARK_CONNECTOR_CONFIG")
if [[ "$format" != *avro.AvroFormat ]]
then
    logerror "❌ this load writes avro files: the connector has format.class=$format"
    exit 1
fi
topics_dir=$(jq -r '."topics.dir" // "topics"' "$BENCHMARK_CONNECTOR_CONFIG")
hdfs="/opt/hadoop-3.1.3/bin/hdfs"
function namenode () {
    playground --output-level ERROR container exec --container namenode --command "$1"
}

if [ -z "$BENCHMARK_LOAD_CHECK" ]
then
    # the topic written by the sink of the example (BENCHMARK_HDFS_TOPIC to choose another one)
    topic="${BENCHMARK_HDFS_TOPIC:-$(namenode "$hdfs dfs -ls -C /$topics_dir" 2> /dev/null | grep -v -E '/(\+tmp|_)' | head -1 | xargs -n1 basename 2> /dev/null)}"
    if [ -z "$topic" ]
    then
        logerror "❌ no topic folder in /$topics_dir in hdfs: run hdfs3-source.sh first"
        exit 1
    fi
    # the source reads the file listed after the last one it read: a partition folder that sorts after the ones of the
    # sink (f1=value<n> with the FieldPartitioner of the example), partition=0 with the DefaultPartitioner, where the
    # offsets of the files below sort after the ones of the sink
    partition=$(namenode "$hdfs dfs -ls -C /$topics_dir/$topic" 2> /dev/null | grep "=" | head -1 | xargs -n1 basename 2> /dev/null | cut -d= -f1)
    case "$partition" in
        partition|"") partition="partition=0" ;;
        *) partition="$partition=zz-benchmark" ;;
    esac
fi
# offsets of the files, increasing from one run (and one batch) to the next
next_offset=$(( $(date +%s) * 1000000000 ))
upload_to_hdfs () {
    local work="$PLAYGROUND_HOST_TMP_DIR/$1" file count list=""
    mkdir -p "$work/avro"
    echo '{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' > "$work/avro/schema.avsc"
    for file in $(cd "$work" && ls *.json)
    do
        count=$(grep -c . "$work/$file")
        list="$list$file $(printf '%s+0+%019d+%019d.avro' "$topic" "$next_offset" $((next_offset + count - 1)))"$'\n'
        next_offset=$((next_offset + count))
    done
    echo -n "$list" > "$work/avro/list"
    # one container for all the files, as root (the hadoop login of avro-tools needs a known user), then given back to
    # the user: they are removed below
    docker run --quiet --rm -v "$work:/w" --entrypoint sh vdesabou/avro-tools -c \
        'while read -r json avro; do java -jar /opt/avro-tools.jar fromjson --schema-file /w/avro/schema.avsc "/w/$json" > "/w/avro/$avro" || exit 1; done < /w/avro/list; chown -R '"$(id -u):$(id -g)"' /w/avro'
    rm -f "$work/avro/schema.avsc" "$work/avro/list"
    playground --output-level ERROR container cp --source "$work/avro" --destination "namenode:/tmp/$1" > /dev/null
    # hdfs dfs -put writes <file>._COPYING_ and renames it: the source never reads a file being written
    namenode "$hdfs dfs -mkdir -p /$topics_dir/$topic/$partition && $hdfs dfs -put /tmp/$1/*.avro /$topics_dir/$topic/$partition/ && rm -rf /tmp/$1" > /dev/null
    rm -rf "$work/avro"
}
benchmark_files_load upload_to_hdfs "$BENCHMARK_LOAD_RECORDS" "$BENCHMARK_LOAD_RECORD_SIZE" "$BENCHMARK_LOAD_MODE" json-f1 json
