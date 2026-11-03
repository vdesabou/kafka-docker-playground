# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
topic="${args[--topic]}"
compatibility="${args[--compatibility]}"
include_key="${args[--include-key]}"
verbose="${args[--verbose]}"

get_environment_used
get_sr_url_and_security

all_topics=""
if [[ ! -n "$topic" ]]
then
    all_topics=1
    logwarn "--topic flag was not provided, applying command to all topics"
    check_if_continue
    topic=$(playground get-topic-list --skip-internal-topics)
    if [ "$topic" == "" ]
    then
        logerror "❌ No topic found !"
        exit 1
    fi
fi

suffixes="value"
if [[ -n "$include_key" ]]
then
    suffixes="key value"
fi

failed=0
items=($topic)
for topic in ${items[@]}
do
    for suffix in $suffixes
    do
        # without --topic, only the subjects that exist: most topics have no schema, each of them was an error
        if [[ -n "$all_topics" ]] && ! sr_request GET "/subjects/$(urlencode "${topic}-${suffix}")/versions" > /dev/null 2>&1
        then
            continue
        fi
        log "🛡️ Set compatibility for subject ${topic}-${suffix} to $compatibility"
        if sr_request PUT "/config/$(urlencode "${topic}-${suffix}")" "{\"compatibility\": \"$compatibility\"}"
        then
            echo "$sr_response"
        else
            logerror "❌ subject ${topic}-${suffix}: Command failed with error code $sr_error_code"
            logerror "$sr_error_message"
            failed=1
        fi
    done
done
exit $failed
