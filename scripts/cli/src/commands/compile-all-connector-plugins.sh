confluent_only="${args[--confluent-only]}"

rm -rf "${root_folder}/connector-plugin-sourcecode"

function handle_signal {
  echo "Stopping..."
  stop=1
}
# Set the signal handler
trap handle_signal SIGINT

set +e

export GITHUB_RUN_NUMBER=1

if [ ! -f $root_folder/scripts/cli/confluent-hub-plugin-list.txt ]
then
    log "file $root_folder/scripts/cli/confluent-hub-plugin-list.txt not found. Generating it now, it may take a while..."
    playground generate-connector-plugin-list
fi

if [ ! -f $root_folder/scripts/cli/confluent-hub-plugin-list.txt ]
then
    logerror "❌ file $root_folder/scripts/cli/confluent-hub-plugin-list.txt could not be generated"
    exit 1
fi

stop=0
while read -r line || [ $stop != 1 ]; do
    # Skip empty lines or lines starting with # (allowing for leading whitespace)
    if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi

    # Extract the first column using "|" as a delimiter
    # Pipe to 'xargs' to trim any leading/trailing whitespace from the result
    connector_plugin=$(echo "$line" | cut -d "|" -f 1 | xargs)

    if [[ -n "$confluent_only" ]]
    then
        if [[ "${connector_plugin}" != *"confluentinc"* ]]
        then
            log "⏭️ --confluent-only is set skipping non confluent plugin ${connector_plugin}"
            continue
        fi
    fi

    log "🧩 processing plugin: $connector_plugin"
    playground connector-plugin sourcecode --connector-plugin "$connector_plugin" --compile < /dev/null
    
    echo "---"
    echo ""

done < "${root_folder}/scripts/cli/confluent-hub-plugin-list.txt"