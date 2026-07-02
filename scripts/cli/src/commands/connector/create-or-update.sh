connector="${args[--connector]}"
json=${args[json]}
level=${args[--level]}
package=${args[--package]}
validate=${args[--validate]}
wait_for_zero_lag=${args[--wait-for-zero-lag]}
skip_automatic_connector_config=${args[--skip-automatic-connector-config]}
verbose="${args[--verbose]}"
no_clipboard="${args[--no-clipboard]}"
offsets=${args[--offsets]}
initial_state=${args[--initial-state]}
use_terraform=${args[--terraform]}

connector_type=$(playground state get run.connector_type)

# Validate terraform flag compatibility
if [[ -n "$use_terraform" ]]
then
    if [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ] && [ "$connector_type" != "$CONNECTOR_TYPE_CUSTOM" ]
    then
        logerror "❌ --terraform is only supported with Confluent Cloud connectors (fully-managed or custom)"
        exit 1
    fi

    if [[ -n "$level" ]]
    then
        logerror "❌ --level is not supported with --terraform"
        exit 1
    fi

    if [[ -n "$package" ]]
    then
        logerror "❌ --package is not supported with --terraform"
        exit 1
    fi

    if [[ -n "$offsets" ]]
    then
        logerror "❌ --offsets is not supported with --terraform"
        exit 1
    fi

    if [[ -n "$initial_state" ]]
    then
        logerror "❌ --initial-state is not supported with --terraform"
        exit 1
    fi
fi

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    if [[ -n "$level" ]] && [[ -z "$use_terraform" ]]
    then
        logerror "❌ --level is set but not supported with $connector_type connector"
        exit 1
    fi

    if [[ -n "$package" ]] && [[ -z "$use_terraform" ]]
    then
        logerror "❌ --package is set but not supported with $connector_type connector"
        exit 1
    fi
fi

if [[ -n "$initial_state" ]]
then
    tag=$(docker ps --format '{{.Image}}' | grep -E 'confluentinc/cp-.*-connect.*:' | awk -F':' '{print $2}')
    if [ $? != 0 ] || [ "$tag" == "" ]
    then
        logerror "❌ could not find current CP version from docker ps"
        exit 1
    fi

    if ! version_gt $tag "7.6.99"; then
        logerror "❌ --initial-state is available since CP 7.7 only"
        exit 1
    fi
fi

environment=$(playground state get run.environment_before_switch)
if [ "$environment" = "" ]
then
    environment=$(playground state get run.environment)
fi

if [ "$environment" = "" ]
then
    environment="plaintext"
fi

is_cfk=0
if [[ "$environment" == "cfk" ]]
then
    is_cfk=1
fi

if [ "$json" = "-" ]
then
    # stdin
    json_content=$(cat "$json")
else
    json_content=$json
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi
json_file=$tmp_dir/connector.json
new_json_file=$tmp_dir/connector_new.json
connector_with_offsets_file=$tmp_dir/connector_with_offsets.json
connector_with_initial_state_file=$tmp_dir/connector_with_initial_state.json
json_validate_file=$tmp_dir/json_validate_file

echo "$json_content" > $json_file

# JSON is invalid
if ! echo "$json_content" | jq -e .  > /dev/null 2>&1
then
    set +e
    jq_output=$(jq . "$json_file" 2>&1)
    error_line=$(echo "$jq_output" | grep -oE 'parse error.*at line [0-9]+' | grep -oE '[0-9]+')

    if [[ -n "$error_line" ]]; then
        logerror "❌ Invalid JSON at line $error_line"
    fi
    set -e

    if [ -z "$GITHUB_RUN_NUMBER" ]
    then
        if [[ $(type -f bat 2>&1) =~ "not found" ]]
        then
            cat -n $json_file
        else
            bat $json_file --highlight-line $error_line
        fi

        log "🔧 In next step, you can fix json, save and close the file to continue"
        playground open --file "${json_file}" --wait
        json_content=$(cat "$json_file")

        if ! echo "$json_content" | jq -e .  > /dev/null 2>&1
        then
            logerror "❌ JSON is still invalid after editing, exiting"
            exit 1
        fi
    else
        exit 1
    fi
fi

is_create=1
if [[ "$is_cfk" -eq 1 ]] && [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ] && [ "$connector_type" != "$CONNECTOR_TYPE_CUSTOM" ]
then
    set +e
    kubectl -n confluent get connector "$connector" > /dev/null 2>&1
    if [[ $? -eq 0 ]]
    then
        is_create=0
    fi
    set -e
else
    set +e
    connectors=$(playground get-connector-list)
    ret=$?
    if [ $ret -ne 0 ]
    then
        logerror "❌ Failed to get list of connectors"
        playground get-connector-list
        exit 1
    fi
    set -e
    items=($connectors)
    for con in ${items[@]}
    do
        if [[ "$con" == "$connector" ]]
        then
            is_create=0
        fi
    done
fi

if [[ -n "$validate" ]]
then
    log "✅ --validate is set"
    set +e
    connector_class=$(echo "$json_content" | jq -r '."connector.class"')

    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" -H \"authorization: Basic $authorization\" --data @$json_file https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connector-plugins/$connector_class/config/validate"
    elif [[ "$is_cfk" -eq 1 ]]
    then
        if [[ "$connector_class" == "null" ]] || [[ -z "$connector_class" ]]
        then
            logerror "❌ connector.class is required"
            exit 1
        fi
        logwarn "⚠️ --validate with CFK currently performs basic checks only (no Connect REST validation endpoint)"
        log "✅ Basic CFK validation passed"
        set -e
        validate=skipped
    else
        get_connect_url_and_security
        if [[ -n "$skip_automatic_connector_config" ]]
        then
            log "🤖 --skip-automatic-connector-config is set"
        else
            add_connector_config_based_on_environment "$environment" "$json_content"
        fi
        # add mandatory name field
        new_json_content=$(echo "$json_content" | jq ". + {\"name\": \"$connector\"}")

        echo "$new_json_content" > $new_json_file
        handle_onprem_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" --data @$new_json_file $connect_url/connector-plugins/$connector_class/config/validate"
    fi
    set -e
    if [[ "$validate" == "skipped" ]]
    then
        :
    else
    if ! echo "$curl_output" | jq -e .  > /dev/null 2>&1
    then
        set +e
        echo "$curl_output" > $json_validate_file
        jq_output=$(jq . "$json_validate_file" 2>&1)
        error_line=$(echo "$jq_output" | grep -oE 'parse error.*at line [0-9]+' | grep -oE '[0-9]+')

        if [[ -n "$error_line" ]]; then
            logerror "❌ Invalid JSON at line $error_line"
        fi
        set -e

        if [ -z "$GITHUB_RUN_NUMBER" ]
        then
            if [[ $(type -f bat 2>&1) =~ "not found" ]]
            then
                cat -n $json_validate_file
            else
                bat $json_validate_file --highlight-line $error_line
            fi
        fi

        exit 1
    fi

    # Check if there were any errors
    has_errors=$(echo "$curl_output" | jq '.configs[] | select(.value.errors | length > 0) | length' | tr -d '\n')

    if [[ "$has_errors" -gt 0 ]]
    then
        output=$(echo "$curl_output" | jq -r '.configs[] | select(.value.errors | length > 0) | .value.name + " ->> " + (.value.errors | to_entries | map("\(.value|tostring)") | join(", "))')
        logerror "❌ Validation errors found in connector config\n$output"

        exit 1
    else
        log "✅ $connector_type connector config is valid !"
    fi
    fi
fi

# Handle Terraform deployment if --terraform flag is set
if [[ -n "$use_terraform" ]]
then
    log "🏗️ Using Terraform to deploy connector $connector"

    # Check prerequisites
    check_terraform_installed
    check_confluent_cloud_terraform_env

    # Get Confluent Cloud environment and cluster details
    get_ccloud_connect

    # Deploy using Terraform
    deploy_connector_with_terraform "$connector" "$json_content" "$environment" "$cluster"
    terraform_dir="$TERRAFORM_DEPLOY_DIR"

    log "✅ Connector $connector successfully deployed using Terraform"
    log "📂 Terraform state saved in: $terraform_dir"

    # Show connector status
    if [ -z "$GITHUB_RUN_NUMBER" ]
    then
        playground connector show-config --connector "$connector" --no-clipboard
    fi

    playground connector status --connector $connector

    if [[ -n "$wait_for_zero_lag" ]]
    then
        playground connector show-lag --connector $connector
    fi

    exit 0
fi

if [ $is_create == 1 ]
then
    log "🛠️ Creating $connector_type connector $connector"
else
    log "🔄 Updating $connector_type connector $connector"
fi

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    if [[ -n "$offsets" ]] && [ $is_create == 0 ]
    then
        logerror "❌ --offsets is set but $connector_type connector $connector already exists"
        exit 1
    fi

    if [[ -n "$initial_state" ]]
    then
        logerror "❌ --initial-state is set but not supported with $connector_type connector"
        exit 1
    fi

    get_ccloud_connect
    if [[ -n "$offsets" ]]
    then
        log "📍 creating $connector_type connector $connector with offsets: $offsets" 
        # add mandatory name field
        new_json_content=$(echo "$json_content" | jq -c ". + {\"name\": \"$connector\"}")

        sed -e "s|:CONNECTOR_NAME:|$connector|g" \
            -e "s|:CONNECTOR_CONFIG:|$new_json_content|g" \
            -e "s|:CONNECTOR_OFFSETS:|$offsets|g" \
            $root_folder/scripts/cli/src/create-connector-post-template.json > ${connector_with_offsets_file}

        handle_ccloud_connect_rest_api "curl $security -s -X POST -H \"Content-Type: application/json\" -H \"authorization: Basic $authorization\" --data @$connector_with_offsets_file https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors"
    else
        handle_ccloud_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" -H \"authorization: Basic $authorization\" --data @$json_file https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config"
    fi
else
    if [[ -n "$offsets" ]]
    then
        logerror "❌ --offsets is set but not supported with $connector_type connector"
        exit 1
    fi
    if [[ -n "$initial_state" ]] && [ $is_create == 0 ]
    then
        logerror "❌ --initial-state is set but $connector_type connector $connector already exists"
        exit 1
    fi
    get_connect_url_and_security
    if [[ -n "$skip_automatic_connector_config" ]]
    then
        log "🤖 --skip-automatic-connector-config is set"
    else
        add_connector_config_based_on_environment "$environment" "$json_content"
    fi

    if [[ "$is_cfk" -eq 1 ]]
    then
        if [[ -n "$initial_state" ]]
        then
            logerror "❌ --initial-state is not supported with CFK Connector CRD"
            exit 1
        fi

        # CFK does not use docker broker aliases; normalize common broker endpoint references.
        json_content=$(echo "$json_content" | jq 'with_entries(if (.value | type) == "string" then .value = (.value | gsub("broker:9092"; "kafka:9071") | gsub("schema-registry"; "schemaregistry")) else . end)')

        connector_cr_file=$tmp_dir/connector-cr.yaml
        connector_class=$(echo "$json_content" | jq -r '."connector.class"')
        if [[ "$connector_class" == "null" ]] || [[ -z "$connector_class" ]]
        then
            logerror "❌ connector.class is required"
            exit 1
        fi

        task_max=$(echo "$json_content" | jq -r '."tasks.max" // "1"')
        configs_yaml=$(echo "$json_content" | jq -r 'del(."connector.class", ."tasks.max", .name) | to_entries[]? | "    \(.key): \(.value|tostring|@json)"')

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
            echo "    name: connect"
            if [[ -n "$configs_yaml" ]]
            then
                echo "  configs:"
                echo "$configs_yaml"
            else
                echo "  configs: {}"
            fi
        } > "$connector_cr_file"

        if [ -z "$GITHUB_RUN_NUMBER" ]
        then
            log "📄 Generated Connector CRD manifest used for apply:"
            sed 's/^/    /' "$connector_cr_file"
        fi
        if [[ -n "$verbose" ]]
        then
            log "🐞 CLI command used"
        fi
        echo "kubectl -n confluent apply -f $connector_cr_file"

        kubectl -n confluent apply -f "$connector_cr_file"
    elif [[ -n "$initial_state" ]]
    then
        log "🪵 creating $connector_type connector $connector with --initial-state: $initial_state" 
        # add mandatory name field
        new_json_content=$(echo "$json_content" | sed 's/&/:AMPERSAND:/g' | jq -c ". + {\"name\": \"$connector\"}")

        sed -e "s|:CONNECTOR_NAME:|$connector|g" \
            -e "s|:CONNECTOR_CONFIG:|$new_json_content|g" \
            -e "s|:CONNECTOR_INITIAL_STATE:|$initial_state|g" \
            $root_folder/scripts/cli/src/create-connector-post-template-initial-state.json > /tmp/connector_with_initial_state_file.json

        sed -e "s|:AMPERSAND:|\&|g" /tmp/connector_with_initial_state_file.json > ${connector_with_initial_state_file}

        handle_onprem_connect_rest_api "curl $security -s -X POST -H \"Content-Type: application/json\" --data @$connector_with_initial_state_file $connect_url/connectors"
    else
        echo "$json_content" > $new_json_file
        handle_onprem_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" --data @$new_json_file $connect_url/connectors/$connector/config"
    fi
fi

echo "$json_content" > "/tmp/config-$connector"

if [ -z "$GITHUB_RUN_NUMBER" ]
then
    if [[ "$OSTYPE" == "darwin"* ]]
    then
        clipboard=$(playground config get clipboard)
        if [ "$clipboard" == "" ]
        then
            playground config set clipboard true
        fi

        if ( [ "$clipboard" == "true" ] || [ "$clipboard" == "" ] ) && [[ ! -n "$no_clipboard" ]]
        then
            tmp_dir_clipboard=$(mktemp -d -t pg-XXXXXXXXXX)
            if [ -z "$PG_VERBOSE_MODE" ]
            then
                trap 'rm -rf $tmp_dir_clipboard' EXIT
            else
                log "🐛📂 not deleting tmp dir $tmp_dir_clipboard"
            fi
            echo "playground connector create-or-update --connector $connector << EOF" > $tmp_dir_clipboard/tmp
            cat "/tmp/config-$connector" | jq -S . | sed 's/\$/\\$/g' >> $tmp_dir_clipboard/tmp
            echo "EOF" >> $tmp_dir_clipboard/tmp

            cat $tmp_dir_clipboard/tmp | pbcopy
            log "📋 $connector_type connector config has been copied to the clipboard (disable with 'playground config clipboard false')"
        fi
    fi
fi

if [[ -n "$level" ]]
then
    if [[ -n "$package" ]]
    then
        playground debug log-level set --level $level --package $package
    else
        playground connector log-level --connector $connector --level $level
    fi
fi
if [ $is_create == 1 ]
then
    log "✅ $connector_type connector $connector was successfully created"
else
    log "✅ $connector_type connector $connector was successfully updated"
fi

if [[ "$is_cfk" -eq 1 ]] && [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ] && [ "$connector_type" != "$CONNECTOR_TYPE_CUSTOM" ]
then
    kubectl -n confluent get connector "$connector" -o yaml
    if [[ -n "$wait_for_zero_lag" ]]
    then
        logwarn "⏭️ --wait-for-zero-lag is not supported with CFK Connector CRD path"
    fi
    exit 0
fi

if [ -z "$GITHUB_RUN_NUMBER" ]
then
    playground connector show-config --connector "$connector" --no-clipboard
fi

playground connector show-config-parameters --connector "$connector" --only-show-json
set +e
playground connector status --connector $connector
if [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ]
then
    playground connector open-docs --only-show-url
fi
set -e

if [[ -n "$wait_for_zero_lag" ]]
then
    maybe_id=""
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/status\" --header \"authorization: Basic $authorization\""
        connectorId=$(get_ccloud_connector_lcc $connector)
        maybe_id=" ($connectorId)"
    else
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/status\""
    fi

    type=$(echo "$curl_output" | jq -r '.type')
    if [ "$type" != "sink" ]
    then
        logwarn "⏭️ --wait-for-zero-lag is set but $connector_type connector ${connector}${maybe_id} is not a sink"
    fi
    playground connector show-lag --connector $connector
fi
