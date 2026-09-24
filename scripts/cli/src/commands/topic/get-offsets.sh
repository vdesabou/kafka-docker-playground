topic="${args[--topic]}"
verbose="${args[--verbose]}"

get_environment_used

if [[ ! -n "$topic" ]]
then
    log "✨ --topic flag was not provided, applying command to all topics"
    topic=$(playground get-topic-list --skip-internal-topics)
    if [ "$topic" == "" ]
    then
        logerror "❌ No topic found !"
        exit 1
    fi
fi

get_connect_image
if ! version_gt "$CP_CONNECT_TAG" "6.9.9"
then
    logerror "❌ playground topic get-offsets requires CP 7.0 or later (it is $CP_CONNECT_TAG)"
    exit 1
fi
class_name="kafka.tools.GetOffsetShell"
if version_gt "$CP_CONNECT_TAG" "7.6.9"
then
    class_name="org.apache.kafka.tools.GetOffsetShell"
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

items=($topic)
for topic in "${items[@]}"
do
    log "📍 Earliest and latest offsets per partition of topic $topic"
    # GetOffsetShell prints topic:partition:offset, --time -2 is earliest and -1 is latest
    for time in earliest latest
    do
        if [ "$time" == "earliest" ]
        then
            time_value="-2"
        else
            time_value="-1"
        fi
        set +e
        run_kafka_admin_tool kafka-run-class $class_name --topic "$topic" --time $time_value 2>/dev/null | grep -v "No configuration found" > $tmp_dir/raw
        set -e
        # anything else, such as the --verbose output, is displayed as is
        grep -vE ':[0-9]+:-?[0-9]+$' $tmp_dir/raw || true
        grep -E ':[0-9]+:-?[0-9]+$' $tmp_dir/raw | awk -F: '{print $(NF-1), $NF}' | sort -k1,1 > $tmp_dir/$time || true
    done
    if [ ! -s $tmp_dir/latest ]
    then
        logwarn "topic $topic does not exist or has no partition !"
        continue
    fi
    printf "%-10s %-15s %-15s %-15s\n" "PARTITION" "EARLIEST" "LATEST" "RECORDS"
    join $tmp_dir/earliest $tmp_dir/latest | sort -n | awk '{printf "%-10s %-15s %-15s %-15s\n", $1, $2, $3, $3 - $2; total += $3 - $2} END {printf "%-10s %-15s %-15s %-15s\n", "TOTAL", "", "", total}'
done
