days="${args[--days]}"
vendor="${args[--vendor]}"

if [ ! -f $root_folder/scripts/cli/confluent-hub-plugin-list.txt ]
then
    log "file $root_folder/scripts/cli/confluent-hub-plugin-list.txt not found. Generating it now, it may take a while..."
    playground generate-connector-plugin-list
fi

if [ ! -f $root_folder/scripts/cli/confluent-hub-plugin-list.txt ]
then
    logerror "file $root_folder/scripts/cli/confluent-hub-plugin-list.txt could not be generated"
    exit 1
fi

if [[ -n "$vendor" ]]
then
    log "🆕 Listing last updated connector plugins (within $days days) for $vendor vendor"
else
    log "🆕 Listing last updated connector plugins (within $days days) for all vendors"
fi

for plugin in $(cat $root_folder/scripts/cli/confluent-hub-plugin-list.txt | cut -d "|" -f 1)
do
    if [[ -n "$vendor" && ! "$plugin" =~ $vendor ]]
    then
        continue
    fi
    output=$(playground connector-plugin versions --connector-plugin "$plugin" --force-refresh --last 1 | head -n 1)
    set +e
    if [[ -n "$days" ]]
    then
        last_updated=$(echo "$output" | grep -v "<unknown>" | cut -d "(" -f 2 | cut -d " " -f 1)
        if [[ -n "$last_updated" ]]
        then
            last_updated_days=$(echo $last_updated | tr -d '[:space:]')
            if [[ $last_updated_days -le $days ]]
            then
                documentation_url=$(playground connector-plugin versions --connector-plugin "$plugin" --last 1 | tail -n 1)
                echo "🔌 $plugin - $output - $documentation_url"
            fi
        fi
    fi
    set -e
done