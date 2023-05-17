topic="${args[--topic]}"

environment=`get_environment_used`

if [ "$environment" == "error" ]
then
    logerror "File containing restart command /tmp/playground-command does not exist!"
    exit 1
fi

if [ "$environment" != "plaintext" ]
then
    logerror "It only works when plaintext environment is used"
    exit 1
fi

DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
dir1=$(echo ${DIR_CLI%/*})
root_folder=$(echo ${dir1%/*})

sr_cli=$root_folder/scripts/cli/schema-registry-statistics
sr_cli_version=1.3.0

if [ ! -f $sr_cli ]
then
    log "⏳ $sr_cli is not installed, installing it now"
    cd /tmp
    rm -f schema-registry-statistics.tar.gz
    curl -L -o schema-registry-statistics.tar.gz https://github.com/EladLeev/schema-registry-statistics/releases/download/v${sr_cli_version}/schema-registry-statistics_${sr_cli_version}_`uname -s`_`uname -m`.tar.gz
    tar xvfz schema-registry-statistics.tar.gz
    mv schema-registry-statistics $sr_cli
    rm -f chema-registry-statistics.tar.gz
    chmod u+x $sr_cli
    cd -
fi

if [[ ! -n "$topic" ]]
then
    log "✨ --topic flag was not provided, applying command to all topics"
    topic=$(playground get-topic-list --skip-connect-internal-topics)
    if [ "$topic" == "" ]
    then
        logerror "❌ No topic found !"
        exit 1
    fi
fi

items=($topic)
for topic in ${items[@]}
do
    nb_messages=$(playground topic get-number-records -t $topic | tail -1)
    rm -f /tmp/results.json
    log "✨ Display statistics of topic $topic, it contains $nb_messages messages"
    output_file="/tmp/output.txt"
    $sr_cli --bootstrap localhost:29092 --topic "$topic" --group "$RANDOM" --limit $nb_messages --store true --path /tmp/results.json  > "$output_file" 2>&1 & 

    pid=$!

    while true
    do
        if grep -q "Use SIGINT to stop consuming" "$output_file"
        then
            break
        fi
        sleep 1
    done
    
    kill -SIGINT $pid

    sleep 2
    grep "Schema ID" $output_file
    cat /tmp/results.json | jq .

    rm -f /tmp/results.json $output_file
done