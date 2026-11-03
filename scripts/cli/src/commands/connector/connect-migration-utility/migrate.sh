migration_mode=${args[--migration-mode]}
eval "sensitive_property=(${args[--sensitive-property]})"
no_open="${args[--no-open]}"

get_connect_url_and_security

discovery_output_dir="$root_folder/connect-migration-utility-discovery-output"
if [ ! -d "$discovery_output_dir" ]
then
	logerror "❌ $discovery_output_dir does not exist, please run playground connector connect-migration-utility discovery first !"
	exit 1
fi

log "🪄 Migrate discovered local connectors in $discovery_output_dir as fully managed connectors"

log "🔌 bootstrapping ccloud environment"
bootstrap_ccloud_environment "" "" "true"

get_ccloud_connect

# the output of the tool holds the configs of the connectors, secrets included: private file, removed on exit, printed
# redacted (also masking the exact secret values known here)
output_log=$(mktemp -t pg-cmu-migrate-XXXXXXXXXX)
trap 'rm -f "$output_log"' EXIT
secret_values=("$CONFLUENT_CLOUD_API_SECRET" "$CLOUD_SECRET")

for json_file in "$discovery_output_dir/discovered_configs/successful_configs/fm_configs"/*.json
do
    length=${#sensitive_property[@]}
    if ((length > 0)) # Check if the array is not empty
    then
        for sensitive_prop in "${sensitive_property[@]}"
        do
            # key=value: the value is everything after the first '=' (base64 secrets end with '='), and a value
            # written $NAME or ${NAME} is the value of that variable (never evaluated as shell code)
            json_key="${sensitive_prop%%=*}"
            actual_secret_value="${sensitive_prop#*=}"
            if [[ "$sensitive_prop" != *=* ]] || [ -z "$json_key" ]
            then
                logerror "❌ --sensitive-property should be key=value (got $json_key)"
                exit 1
            fi
            if [[ "$actual_secret_value" =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$ ]]
            then
                var_name="${BASH_REMATCH[1]}"
                actual_secret_value="${!var_name}"
                if [ -z "$actual_secret_value" ]
                then
                    logwarn "⚠️ --sensitive-property $json_key: variable $var_name is empty"
                fi
            fi
            secret_values+=("$actual_secret_value")

            if [ -f "$json_file" ]
            then
                # jq: any character of the value is kept as is (quotes, backslashes, @, &...)
                if jq -e --arg k "$json_key" '[.. | objects | select(has($k))] | length > 0' "$json_file" > /dev/null 2>&1
                then
                    temp_file=$(mktemp)
                    jq --arg k "$json_key" --arg v "$actual_secret_value" 'walk(if type == "object" and has($k) then .[$k] = $v else . end)' "$json_file" > "$temp_file"
                    cat "$temp_file" > "$json_file"
                    rm -f "$temp_file"
                    log "🔐 Updated $json_key in $(basename "$json_file")"
                else
                    logwarn "⚠️ $json_key is not in $(basename "$json_file"), --sensitive-property ignored for it"
                fi
            fi
        done
    fi

    if [ -f "$json_file" ]
    then
        log "📄 $(basename "$json_file")"
        if [[ -z "$no_open" ]]
        then
            log "✨ Update the connector config file $(basename "$json_file") as per your needs, save and close the file to continue"
            playground open --file "$json_file" --wait
        fi
    fi
done

set +e
docker run -i --rm --network=host -v "$discovery_output_dir:/discovery_output_dir" vdesabou/docker-connect-migration-utility:latest bash -c "python src/migrate_connector_script.py --worker-urls '$connect_url' --disable-ssl-verify --environment-id $environment --cluster-id $cluster --bearer-token $CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET --kafka-auth-mode KAFKA_API_KEY --kafka-api-key $CLOUD_KEY --kafka-api-secret $CLOUD_SECRET --fm-config-dir /discovery_output_dir/discovered_configs/successful_configs/fm_configs --migration-mode $migration_mode" > "$output_log" 2>&1
ret=$?
set -e
if [ $ret -ne 0 ]
then
	logerror "❌ Failed to Migrate Kafka Connectors, check output below"
	redact_connector_secrets "${secret_values[@]}" < "$output_log"
	exit 1
else
	set +e
	grep "ERROR" "$output_log" > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		logerror "❌ Found ERROR in the output of the migration process, please check output below"
		grep "ERROR" "$output_log" | redact_connector_secrets "${secret_values[@]}"
		exit 1
	fi
	set -e
	log "✅ Migrate Kafka Connectors was successful!"
	playground switch-ccloud

	playground connector status

	if [ -z "$GITHUB_RUN_NUMBER" ] && [[ -z "$no_open" ]]
	then
		# not running with CI
		log "Do you want to see the connector in your browser ?"
		check_if_continue
		playground connector open-ccloud-connector-in-browser
	fi
fi