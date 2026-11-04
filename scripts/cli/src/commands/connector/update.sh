connector="${args[--connector]}"

connector_type=$(playground state get run.connector_type)
get_environment_used

is_cfk=0
if [[ "$environment" == cfk* ]] && [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ] && [ "$connector_type" != "$CONNECTOR_TYPE_CUSTOM" ]
then
    is_cfk=1
fi

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        log "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

# the file is only applied if it was saved with a change: editors that do not block (subl, ...) return at once
function file_checksum () {
    cksum < "$1"
}

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in "${items[@]}"
do
    log "🛠️ Updating $connector_type connector $connector"
    if [[ "$is_cfk" -eq 1 ]]
    then
        file=$tmp_dir/connector-cr-$connector.yaml

        set +e
        log "☸️ kubectl -n confluent get connector $connector -o json"
        connector_json=$(kubectl -n confluent get connector "$connector" -o json 2>/dev/null)
        if [ $? -ne 0 ] || [[ -z "$connector_json" ]]
        then
            logerror "❌ could not retrieve CFK Connector CR for $connector"
            exit 1
        fi
        set -e

        connector_class=$(echo "$connector_json" | jq -r '.spec.class')
        task_max=$(echo "$connector_json" | jq -r '.spec.taskMax // 1')
        connect_cluster_ref=$(echo "$connector_json" | jq -r '.spec.connectClusterRef.name // "connect"')
        configs_yaml=$(echo "$connector_json" | jq -r '.spec.configs // {} | to_entries[]? | "    \(.key): \(.value|tostring|@json)"')

        {
            echo "apiVersion: platform.confluent.io/v1beta1"
            echo "kind: Connector"
            echo "metadata:"
            echo "  name: $connector"
            echo "  namespace: confluent"
            echo "spec:"
            echo "  class: $connector_class"
            echo "  taskMax: $task_max"
            echo "  connectClusterRef:"
            echo "    name: $connect_cluster_ref"
            if [[ -n "$configs_yaml" ]]
            then
                echo "  configs:"
                echo "$configs_yaml"
            else
                echo "  configs: {}"
            fi
        } > "$file"

        log "✨ Update the CFK Connector CR as needed, save and close the file to continue"
        checksum_before=$(file_checksum "$file")
        playground open --file "${file}" --wait
        if [ "$(file_checksum "$file")" == "$checksum_before" ]
        then
            log "💤 the CFK Connector CR of $connector was not changed, nothing applied"
            continue
        fi
        log "☸️ kubectl -n confluent apply -f $file"
        kubectl -n confluent apply -f "$file"
        log "✅ CFK Connector CR $connector was updated"
    else
        file=$tmp_dir/config-$connector.sh

        set +e
        echo "#!/bin/bash" > $file
        echo -e "" >> $file
        echo -e "##########################" >> $file
        echo "# this is the part to edit" >> $file
        # captured first: in a pipeline, $? would be the status of the last command, not of show-config
        current_config=$(playground connector show-config --connector "$connector" --no-clipboard)
        if [ $? -ne 0 ]
        then
            logerror "❌ playground connector show-config --connector $connector failed with:"
            echo "$current_config"
            exit 1
        fi
        set -e
        # a Confluent Cloud connector config read from the REST API has its secrets masked: applying it would replace
        # the real values with the mask
        if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
        then
            masked_keys=$(echo "$current_config" | grep -E '"[^"]+" *: *"\*{3,}"' | sed -E 's/^ *"([^"]+)".*/\1/' | paste -sd ' ' -)
            if [ -n "$masked_keys" ]
            then
                logerror "❌ the config of $connector_type connector $connector comes from the REST API, which masks secrets ($masked_keys): updating it would overwrite them with the mask"
                logerror "👉 run 'playground connector create-or-update --connector $connector' with the full config instead (once it is done, 'connector update' reuses it)"
                exit 1
            fi
        fi
        echo "$current_config" | grep -v "Current config for" >> $file
        echo "# end of part to edit" >> $file
        echo -e "##########################" >> $file
        echo -e "" >> $file
        echo "exit 0" >> $file

        echo -e "" >> $file
        docs_links=$(playground state get run.connector_docs_links)
        if [ "$docs_links" != "" ]
        then
            for docs_link in $(echo "${docs_links}" | tr '|' ' ')
            do
                name=$(echo "$docs_link" | cut -d "@" -f 1)
                url=$(echo "$docs_link" | cut -d "@" -f 2)
                echo "🌐⚡ documentation for $connector_type connector $name is available at:" >> $file
                echo "$url" >> $file
            done
        else
            playground connector open-docs --only-show-url | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" >> $file
        fi

        echo -e "" >> $file
        playground connector show-config-parameters --connector $connector  | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" >> $file

        log "✨ Update the connector config as per your needs, save and close the file to continue"
        checksum_before=$(file_checksum "$file")
        playground open --file "${file}" --wait
        if [ "$(file_checksum "$file")" == "$checksum_before" ]
        then
            log "💤 the config of $connector_type connector $connector was not changed, nothing applied"
            continue
        fi
        bash $file
    fi
done
