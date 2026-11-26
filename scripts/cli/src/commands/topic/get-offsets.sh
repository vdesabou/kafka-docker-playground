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

# GetOffsetShell runs in the container of the admin tools (the broker, the kerberos client…): its version, not the one
# of connect (--connect-tag), decides the class name
tool_tag=$(get_admin_tool_cp_tag)
if ! version_gt "$tool_tag" "6.9.9"
then
    logerror "❌ playground topic get-offsets requires CP 7.0 or later (it is $tool_tag)"
    exit 1
fi
class_name=$(get_offset_shell_class "$tool_tag")

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
    # partitions GetOffsetShell got no answer for (it leaves them out, without an error): their leader does not answer, or
    # the clients are sent to another broker (advertised.listeners copied), so the TOTAL above misses their records
    get_topic_partition_assignment "$topic" | sort -n > $tmp_dir/assignment
    missing=$(join -v 1 $tmp_dir/assignment <(awk '{print $1}' $tmp_dir/latest | sort) | sort -n | awk '{print $1 " (leader " $2 ")"}' | paste -sd, - | sed 's/,/, /g')
    if [[ -n "$missing" ]]
    then
        logwarn "⚠️ no offsets for partition(s) $missing: their leader did not answer, so they are not counted in TOTAL (playground broker health)"
    fi
done
