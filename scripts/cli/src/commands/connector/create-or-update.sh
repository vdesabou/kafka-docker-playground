connector="${args[--connector]}"
json=${args[json]}
level=${args[--level]}
package=${args[--package]}
validate=${args[--validate]}
wait_for_zero_lag=${args[--wait-for-zero-lag]}
wait=${args[--wait]}
max_wait=${args[--max-wait]}
skip_automatic_connector_config=${args[--skip-automatic-connector-config]}
verbose="${args[--verbose]}"
no_clipboard="${args[--no-clipboard]}"
offsets=${args[--offsets]}
initial_state=${args[--initial-state]}
use_terraform=${args[--terraform]}
dry_run=${args[--dry-run]}

connector_type=$(playground state get run.connector_type)
connector_type_from_run="$connector_type"
if [ -z "$connector_type" ]
then
    # the environment was started with 'playground start-environment', not 'playground run'
    connector_type="$CONNECTOR_TYPE_SELF_MANAGED"
fi

is_ccloud_connector=0
if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    is_ccloud_connector=1
fi

# --wait: fully managed connectors take minutes to be provisioned and can fail transiently while
# being provisioned, wait_for_ccloud_connector_up restarts them, which 'connector wait' does not
function wait_for_created_connector () {
    if [ $is_ccloud_connector -eq 1 ]
    then
        if [[ -n "$initial_state" ]] && [ "$initial_state" != "RUNNING" ]
        then
            playground connector wait --connector "$connector" --state "$initial_state" --max-wait "${max_wait:-600}"
        else
            wait_for_ccloud_connector_up "$connector" "${max_wait:-600}"
        fi
    else
        playground connector wait --connector "$connector" --state "${initial_state:-RUNNING}" --max-wait "${max_wait:-120}"
    fi
}

# the keys added, removed and changed by an update, the values of secrets masked:
#   show_config_changes <current config> <new config> <hide removed keys: 1 for Confluent Cloud, which adds its own keys>
function show_config_changes () {
    local changes
    changes=$(jq -n -r --argjson old "$1" --argjson new "$2" --arg hide_removed "$3" '
        def secret: test("password|secret|token|credentials|jaas|private\\.key|api\\.key|access\\.key|keystore\\.key"; "i");
        def show($key; $value): if ($key | secret) then "****" else ($value | tostring) end;
        # __internal.config.version and other internal keys are added by connect
        ($old | del(.name) | with_entries(select(.key | startswith("__") | not))) as $o | ($new | del(.name)) as $n |
        ([$n | keys[] | select($o[.] == null) | "   + \(.): \(show(.; $n[.]))"]
        + (if $hide_removed == "1" then [] else [$o | keys[] | select($n[.] == null) | "   - \(.)"] end)
        + [$n | keys[] | select($o[.] != null and ($o[.] | tostring) != ($n[.] | tostring) and (($o[.] | tostring) | test("^\\*+$") | not))
            | "   ~ \(.): \(show(.; $o[.])) → \(show(.; $n[.]))"])
        | if length == 0 then "   (no change)" else .[] end' 2> /dev/null)
    if [ -n "$changes" ]
    then
        log "🔍 changes compared to the running config:"
        echo "$changes"
    fi
}

# a JSON object, or the error: jq message (with line and column), or the type of the JSON value
function connector_json_error () {
    local error
    if ! error=$(printf '%s\n' "$1" | jq -e . 2>&1 > /dev/null)
    then
        echo "${error:-the config is empty or null}"
        return 0
    fi
    local type
    type=$(printf '%s\n' "$1" | jq -r 'type')
    if [ "$type" != "object" ]
    then
        echo "the config must be a JSON object, not a JSON $type"
    fi
}

# Validate terraform flag compatibility
if [[ -n "$use_terraform" ]]
then
    if [ $is_ccloud_connector -eq 0 ]
    then
        logerror "❌ --terraform is only supported with Confluent Cloud connectors (fully-managed or custom)"
        exit 1
    fi

    if [[ -n "$level" ]]
    then
        logerror "❌ --level is not supported with --terraform"
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

if [ $is_ccloud_connector -eq 1 ]
then
    if [[ -n "$level" ]]
    then
        logerror "❌ --level is set but not supported with $connector_type connector"
        exit 1
    fi

    if [[ -n "$initial_state" ]]
    then
        logerror "❌ --initial-state is set but not supported with $connector_type connector"
        exit 1
    fi
elif [[ -n "$offsets" ]]
then
    logerror "❌ --offsets is set but not supported with $connector_type connector"
    exit 1
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
if [[ "$environment" == cfk* ]] && [ $is_ccloud_connector -eq 0 ]
then
    is_cfk=1
fi

if [[ -n "$initial_state" ]]
then
    if [[ "$is_cfk" -eq 1 ]]
    then
        logerror "❌ --initial-state is not supported with CFK Connector CRD"
        exit 1
    fi
    # one tag per connect worker (connect, connect2, connect3...): get_running_cp_tag keeps the first one
    tag=$(get_running_cp_tag)
    if [ "$tag" == "" ]
    then
        logerror "❌ could not find current CP version from docker ps"
        exit 1
    fi

    if ! version_gt $tag "7.6.99"; then
        logerror "❌ --initial-state is available since CP 7.7 only (it is $tag)"
        exit 1
    fi
fi

if [[ "$is_cfk" -eq 1 ]] && [[ ! "$connector" =~ ^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$ ]]
then
    logerror "❌ with CFK, the connector name is the name of a Kubernetes Connector resource: lower case letters, digits, '-' and '.' only ($connector is not valid)"
    exit 1
fi

# the config: stdin (a heredoc, usually), a file (path or @path), or the json itself
if [ "$json" = "-" ]
then
    # read_stdin_if_any: nothing when stdin is a terminal or stays empty, a plain cat would wait forever
    json_content=$(read_stdin_if_any)
    if [ -z "${json_content//[[:space:]]/}" ]
    then
        logerror "❌ no connector config on stdin: pass it with a heredoc (playground connector create-or-update --connector $connector << 'EOF' ... EOF), or the path of a json file"
        exit 1
    fi
elif [ -f "${json#@}" ]
then
    log "📄 reading the connector config from ${json#@}"
    json_content=$(cat "${json#@}")
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

printf '%s\n' "$json_content" > $json_file

json_error=$(connector_json_error "$json_content")
if [ -n "$json_error" ]
then
    logerror "❌ Invalid connector config: $json_error"
    error_line=$(echo "$json_error" | grep -oE 'at line [0-9]+' | grep -oE '[0-9]+' | head -1)
    if [[ -n "$error_line" ]] && ! [[ $(type -f bat 2>&1) =~ "not found" ]]
    then
        bat $json_file --highlight-line $error_line
    else
        cat -n $json_file
    fi

    # the editor only when someone can use it: not in CI, not without a terminal (an agent, a script)
    if [ -z "$GITHUB_RUN_NUMBER" ] && [ -z "$CI" ] && [[ ! -n "$dry_run" ]] && { true > /dev/tty; } 2> /dev/null
    then
        log "🔧 In next step, you can fix json, save and close the file to continue"
        playground open --file "${json_file}" --wait
        json_content=$(cat "$json_file")

        json_error=$(connector_json_error "$json_content")
        if [ -n "$json_error" ]
        then
            logerror "❌ the connector config is still invalid after editing: $json_error"
            exit 1
        fi
    else
        exit 1
    fi
fi

# the REST API format, as returned by GET /connectors/<name> or found in a support case: {"name": ..., "config": {...}}
# (connector config values are strings: an object under "config" can only be that format)
if echo "$json_content" | jq -e 'has("config") and (.config | type == "object")' > /dev/null 2>&1
then
    log "📦 the config is in the REST API format ({\"name\": ..., \"config\": {...}}): using its \"config\""
    json_content=$(echo "$json_content" | jq '.config')
fi
config_name=$(echo "$json_content" | jq -r 'if (.name | type) == "string" then .name else empty end')
if [ -n "$config_name" ] && [ "$config_name" != "$connector" ]
then
    logwarn "⚠️ the config has \"name\": \"$config_name\", it is replaced by the connector name $connector"
    json_content=$(echo "$json_content" | jq --arg name "$connector" '.name = $name')
fi
printf '%s\n' "$json_content" > $json_file

is_create=1
if [[ "$is_cfk" -eq 1 ]]
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

if [[ -n "$offsets" ]] && [ $is_create == 0 ]
then
    logerror "❌ --offsets is set but $connector_type connector $connector already exists"
    exit 1
fi

# playground run --ccloud-service-account: kafka.auth.mode=SERVICE_ACCOUNT, with a service account
# and the ACLs of the documentation
if [ "$PG_CCLOUD_SERVICE_ACCOUNT" == "true" ] && [ $is_ccloud_connector -eq 1 ]
then
    if [[ -n "$dry_run" ]]
    then
        logwarn "🌵 --dry-run: the service account and its ACLs are not created, the config does not show kafka.auth.mode=SERVICE_ACCOUNT"
    else
        get_ccloud_connect
        ccloud_connector_service_account_setup "$connector" "$json_content" "$is_create" || exit 1
        printf '%s\n' "$json_content" > $json_file
    fi
fi

if [[ -n "$validate" ]]
then
    log "✅ --validate is set"
    set +e
    validate_connector_config "$connector" "$json_content" "$tmp_dir" "$environment" "$is_cfk" "$skip_automatic_connector_config"
    ret=$?
    set -e
    if [ $ret -eq 1 ]
    then
        exit 1
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
    record_ccloud_created_connector "$connector"
    record_ccloud_connector_output_topics "$json_content"
    terraform_dir="$TERRAFORM_DEPLOY_DIR"

    log "✅ Connector $connector successfully deployed using Terraform"
    log "📂 Terraform state saved in: $terraform_dir"

    # Show connector status
    if [ -z "$GITHUB_RUN_NUMBER" ]
    then
        playground connector show-config --connector "$connector" --no-clipboard
    fi

    if [[ -n "$wait" ]]
    then
        wait_for_created_connector
    else
        playground connector status --connector $connector
    fi

    if [[ -n "$wait_for_zero_lag" ]]
    then
        playground connector show-lag --connector $connector
    fi

    exit 0
fi

# --dry-run: the final config and the request, nothing is deployed
function dry_run_exit () {
    local request="$1"
    log "🌵 --dry-run: $connector_type connector $connector would be $([ $is_create == 1 ] && echo created || echo updated) with this config"
    echo "$json_content" | jq -S .
    log "🌵 request: $request"
    exit 0
}

if [[ -z "$dry_run" ]]
then
    if [ $is_create == 1 ]
    then
        log "🛠️ Creating $connector_type connector $connector"
    else
        log "🔄 Updating $connector_type connector $connector"
    fi
fi

if [ $is_ccloud_connector -eq 1 ]
then
    get_ccloud_connect
    if [ $is_create == 0 ]
    then
        set +e
        handle_ccloud_connect_rest_api "curl $security -s -X GET -H \"Content-Type: application/json\" -H \"authorization: Basic $authorization\" https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config" > /dev/null 2>&1 && show_config_changes "$curl_output" "$json_content" 1
        set -e
    fi
    if [[ -n "$offsets" ]]
    then
        [[ -n "$dry_run" ]] && dry_run_exit "POST https://api.confluent.cloud/connect/v1/environments/<environment>/clusters/<cluster>/connectors, with offsets $offsets"
        log "📍 creating $connector_type connector $connector with offsets: $offsets"
        # built with jq: a sed template breaks on "|", "&" and "\" in the config
        jq -n --arg name "$connector" --argjson config "$json_content" --argjson offsets "$offsets" \
            '{name: $name, config: ($config + {name: $name}), offsets: $offsets}' > ${connector_with_offsets_file}

        handle_ccloud_connect_rest_api "curl $security -s -X POST -H \"Content-Type: application/json\" -H \"authorization: Basic $authorization\" --data @$connector_with_offsets_file https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors"
    else
        [[ -n "$dry_run" ]] && dry_run_exit "PUT https://api.confluent.cloud/connect/v1/environments/<environment>/clusters/<cluster>/connectors/$connector/config"
        handle_ccloud_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" -H \"authorization: Basic $authorization\" --data @$json_file https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config"
    fi
    # so that 'playground cleanup-cloud-resources' and the end-of-run cleanup can delete them
    record_ccloud_created_connector "$connector"
    record_ccloud_connector_output_topics "$json_content"
else
    get_connect_url_and_security
    if [[ -n "$skip_automatic_connector_config" ]]
    then
        log "🤖 --skip-automatic-connector-config is set"
    else
        add_connector_config_based_on_environment "$environment" "$json_content"
    fi

    if [[ "$is_cfk" -eq 1 ]]
    then
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
            if [[ "$environment" == "cfk-rbac" ]]
            then
                # CFK creates the connector as connectorSubmitter, it runs as connectorSA (principal.service.name)
                echo "  connectRest:"
                echo "    authentication:"
                echo "      type: bearer"
                echo "      bearer:"
                echo "        secretRef: connector-submitter"
            fi
            if [[ -n "$configs_yaml" ]]
            then
                echo "  configs:"
                echo "$configs_yaml"
            else
                echo "  configs: {}"
            fi
        } > "$connector_cr_file"

        if [ $is_create == 0 ]
        then
            set +e
            current_config=$(kubectl -n confluent get connector "$connector" -o json 2> /dev/null | jq '(.spec.configs // {}) + {"connector.class": .spec.class, "tasks.max": (.spec.taskMax | tostring)}')
            [ -n "$current_config" ] && show_config_changes "$current_config" "$json_content" 0
            set -e
        fi

        if [[ -n "$dry_run" ]]
        then
            log "🌵 --dry-run: Connector CRD manifest that would be applied:"
            sed 's/^/    /' "$connector_cr_file"
            exit 0
        fi

        if [ -z "$GITHUB_RUN_NUMBER" ]
        then
            log "📄 Generated Connector CRD manifest used for apply:"
            sed 's/^/    /' "$connector_cr_file"
        fi
        if [[ -n "$verbose" ]]
        then
            log "🐞 CLI command used"
            echo "kubectl -n confluent apply -f $connector_cr_file"
        fi

        kubectl -n confluent apply -f "$connector_cr_file"

        log "Waiting for CFK connector $connector to reconcile"
        max_attempts=$(( (${max_wait:-180} + 1) / 2 ))
        attempt=1
        while true
        do
            set +e
            connector_status_json=$(kubectl -n confluent get connector "$connector" -o json 2>/dev/null)
            ret=$?
            set -e

            if [ "$ret" -eq 0 ] && [ -n "$connector_status_json" ]
            then
                app_ready=$(echo "$connector_status_json" | jq -r '.status.conditions[]? | select(.type=="platform.confluent.io/app-ready") | .status' | head -1)
                state=$(echo "$connector_status_json" | jq -r '.status.state // ""')
                reason=$(echo "$connector_status_json" | jq -r '.status.conditions[]? | select(.type=="platform.confluent.io/app-ready") | .reason' | head -1)
                message=$(echo "$connector_status_json" | jq -r '.status.conditions[]? | select(.type=="platform.confluent.io/app-ready") | .message' | head -1)

                if [[ "$app_ready" == "True" ]] || [[ "$state" == "RUNNING" ]]
                then
                    log "CFK connector $connector is ready"
                    break
                fi

                if [[ "$reason" == "CreateFailed" ]]
                then
                    logerror "❌ CFK connector creation failed: ${message:-no message from status condition}"
                    kubectl -n confluent get connector "$connector" -o yaml
                    exit 1
                fi
            fi

            if [ "$attempt" -ge "$max_attempts" ]
            then
                logerror "❌ CFK connector $connector did not become ready after $((max_attempts * 2)) seconds"
                kubectl -n confluent get connector "$connector" -o yaml
                exit 1
            fi

            sleep 2
            attempt=$((attempt + 1))
        done
    else
        if [ $is_create == 0 ]
        then
            set +e
            handle_onprem_connect_rest_api "curl $security -s \"$connect_url/connectors/$connector/config\"" > /dev/null 2>&1 && show_config_changes "$curl_output" "$json_content" 0
            set -e
        fi

        if [[ -n "$initial_state" ]] && [ $is_create == 1 ]
        then
            [[ -n "$dry_run" ]] && dry_run_exit "POST $connect_url/connectors with initial_state $initial_state"
            log "🪵 creating $connector_type connector $connector with --initial-state: $initial_state"
            # built with jq: a sed template breaks on "|", "&" and "\" in the config
            jq -n --arg name "$connector" --argjson config "$json_content" --arg state "$initial_state" \
                '{name: $name, config: ($config + {name: $name}), initial_state: $state}' > ${connector_with_initial_state_file}

            handle_onprem_connect_rest_api "curl $security -s -X POST -H \"Content-Type: application/json\" --data @$connector_with_initial_state_file $connect_url/connectors"
        else
            [[ -n "$dry_run" ]] && dry_run_exit "PUT $connect_url/connectors/$connector/config$([[ -n "$initial_state" ]] && echo ", then the connector is set to $initial_state")"
            echo "$json_content" > $new_json_file
            handle_onprem_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" --data @$new_json_file $connect_url/connectors/$connector/config"
            if [[ -n "$initial_state" ]]
            then
                # the connector exists: --initial-state is applied after the update
                log "🪵 $connector_type connector $connector exists, setting it to $initial_state"
                case "$initial_state" in
                    PAUSED)
                        playground connector pause --connector "$connector"
                    ;;
                    STOPPED)
                        playground connector stop --connector "$connector"
                    ;;
                    RUNNING)
                        playground connector resume --connector "$connector"
                    ;;
                esac
            fi
        fi
    fi
fi

# read by 'connector show-config' and the restart helpers: it can hold passwords, only readable by you
rm -f "/tmp/config-$connector"
(umask 077 && echo "$json_content" > "/tmp/config-$connector")

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
            # a quoted heredoc: the config is pasted back byte for byte ("\\d", "$" are kept)
            echo "playground connector create-or-update --connector $connector << 'EOF'" > $tmp_dir/clipboard
            cat "/tmp/config-$connector" | jq -S . >> $tmp_dir/clipboard
            echo "EOF" >> $tmp_dir/clipboard

            cat $tmp_dir/clipboard | pbcopy
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

if [[ "$is_cfk" -eq 1 ]]
then
    if [ -z "$GITHUB_RUN_NUMBER" ]
    then
        kubectl -n confluent get connector "$connector" -o yaml
    fi
    if [[ -n "$wait" ]]
    then
        # the CR being app-ready does not mean that the tasks are RUNNING
        wait_for_created_connector
    fi
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
# with --wait, the status is displayed by 'connector wait' when it fails (right after the creation, it can also be a 404)
if [[ -z "$wait" ]]
then
    playground connector status --connector $connector
fi
# the docs of the connector of the example: only with playground run
if [ -n "$connector_type_from_run" ] && { [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ]; }
then
    playground connector open-docs --only-show-url
fi
set -e

if [[ -n "$wait" ]]
then
    wait_for_created_connector
fi

if [[ -n "$wait_for_zero_lag" ]]
then
    # show-lag skips a source connector with a warning
    playground connector show-lag --connector $connector
fi
