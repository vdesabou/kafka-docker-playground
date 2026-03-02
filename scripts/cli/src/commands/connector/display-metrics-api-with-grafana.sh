connector="${args[--connector]}"

escape_sed_replacement() {
    echo "$1" | sed -e 's/[\/&]/\\&/g'
}

build_quoted_csv() {
    local values=("$@")
    local result=""
    local value

    for value in "${values[@]}"
    do
        if [[ -z "$value" ]]
        then
            continue
        fi

        if [[ -n "$result" ]]
        then
            result="$result,"
        fi
        result="$result\"$value\""
    done

    echo "$result"
}

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    logerror "🚨 This command is not supported for custom connectors"
    exit 1
fi

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
then

    if [[ ! -n "$connector" ]]
    then
        connector=$(playground get-connector-list)
        if [ "$connector" == "" ]
        then
            log "💤 No $connector_type connector is running !"
            exit 1
        fi
    fi

    items=($connector)
    length=${#items[@]}
    if ((length > 1))
    then
        log "✨ --connector flag was not provided, applying command to all connectors"
    fi

    get_ccloud_connect

    connector_ids=()
    for connector in "${items[@]}"
    do
        connectorId=$(get_ccloud_connector_lcc "$connector")
        if [[ -z "$connectorId" ]]
        then
            logerror "🚨 Could not find connector id for $connector"
            exit 1
        fi
        connector_ids+=("$connectorId")
    done

    get_kafka_docker_playground_dir

    ccloud_config_file="$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta"
    if [ ! -f "$ccloud_config_file" ]
    then
        logerror "🚨 $ccloud_config_file has not been generated"
        exit 1
    fi

    kafka_cluster_id=$(grep "KAFKA CLUSTER ID" "$ccloud_config_file" | awk -F': ' '{print $2}')
    sr_cluster_id=$(grep "SCHEMA REGISTRY CLUSTER ID" "$ccloud_config_file" | awk -F': ' '{print $2}')

    if [[ -z "$kafka_cluster_id" ]]
    then
        logerror "🚨 Could not resolve Kafka cluster id from $ccloud_config_file"
        exit 1
    fi

    if [[ -z "$sr_cluster_id" ]]
    then
        logerror "🚨 Could not resolve Schema Registry cluster id from $ccloud_config_file"
        exit 1
    fi

    display_metrics_dir="$root_folder/scripts/cli/src/display-metrics-api-with-grafana"
    plaintext_dir="$root_folder/environment/plaintext"
    working_dir="/tmp/playground-display-metrics-api-with-grafana"

    mkdir -p "$working_dir/prometheus"
    mkdir -p "$working_dir/grafana/provisioning/datasources"
    mkdir -p "$working_dir/grafana/provisioning/dashboards"
    mkdir -p "$working_dir/grafana/config"

    cp "$plaintext_dir/grafana/provisioning/datasources/datasource.yml" "$working_dir/grafana/provisioning/datasources/datasource.yml"
    cp "$plaintext_dir/grafana/provisioning/dashboards/dashboard.yml" "$working_dir/grafana/provisioning/dashboards/dashboard.yml"
    cp "$display_metrics_dir/grafana/provisioning/dashboards/ccloud.json" "$working_dir/grafana/provisioning/dashboards/ccloud.json"
    cp "$plaintext_dir/grafana/config/grafana.ini" "$working_dir/grafana/config/grafana.ini"

    connector_ids_csv=$(build_quoted_csv "${connector_ids[@]}")
    kafka_ids_csv=$(build_quoted_csv "$kafka_cluster_id")
    sr_ids_csv=$(build_quoted_csv "$sr_cluster_id")

    escaped_cloud_api_key=$(escape_sed_replacement "$CLOUD_API_KEY")
    escaped_cloud_api_secret=$(escape_sed_replacement "$CLOUD_API_SECRET")
    escaped_kafka_ids_csv=$(escape_sed_replacement "$kafka_ids_csv")
    escaped_connector_ids_csv=$(escape_sed_replacement "$connector_ids_csv")
    escaped_sr_ids_csv=$(escape_sed_replacement "$sr_ids_csv")

    sed -e "s|\$CLOUD_API_KEY|$escaped_cloud_api_key|g" \
        -e "s|\$CLOUD_API_SECRET|$escaped_cloud_api_secret|g" \
        -e "s|\${CCLOUD_KAFKA_LKC_IDS}|$escaped_kafka_ids_csv|g" \
        -e "s|\${CCLOUD_CONNECT_LCC_IDS}|$escaped_connector_ids_csv|g" \
        -e "s|\${CCLOUD_SR_LSRC_IDS}|$escaped_sr_ids_csv|g" \
        "$display_metrics_dir/prometheus/prometheus.yml" > "$working_dir/prometheus/prometheus.yml"

    network_name="playground-grafana"
    if ! docker network inspect "$network_name" >/dev/null 2>&1
    then
        docker network create "$network_name" >/dev/null
    fi

    if docker ps -a --format '{{.Names}}' | grep -q '^prometheus-display-metrics-api-with-grafana$'
    then
        docker rm -f prometheus-display-metrics-api-with-grafana >/dev/null
    fi
    if docker ps -a --format '{{.Names}}' | grep -q '^grafana-display-metrics-api-with-grafana$'
    then
        docker rm -f grafana-display-metrics-api-with-grafana >/dev/null
    fi

    docker run -d --name prometheus-display-metrics-api-with-grafana --hostname prometheus \
        --network "$network_name" \
        -p 9090:9090 \
        -v "$working_dir/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
        prom/prometheus:v2.29.2 \
        --config.file=/etc/prometheus/prometheus.yml >/dev/null

    docker run -d --name grafana-display-metrics-api-with-grafana --hostname grafana \
        --network "$network_name" \
        -p 3000:3000 \
        -e GF_SECURITY_ADMIN_USER=admin \
        -e GF_SECURITY_ADMIN_PASSWORD=password \
        -e GF_USERS_ALLOW_SIGN_UP=false \
        -v "$working_dir/grafana/provisioning:/etc/grafana/provisioning:ro" \
        -v "$working_dir/grafana/config/grafana.ini:/etc/grafana/grafana.ini:ro" \
        grafana/grafana:11.1.0 >/dev/null

    if [ -z "$GITHUB_RUN_NUMBER" ]
    then
        automatically=$(playground config get open-grafana-in-browser.automatically)
        if [ "$automatically" == "" ]
        then
            playground config set open-grafana-in-browser.automatically true
        fi

        browser=$(playground config get open-grafana-in-browser.browser)
        if [ "$browser" == "" ]
        then
            playground config set open-grafana-in-browser.browser ""
        fi

        if [ "$automatically" == "true" ] || [ "$automatically" == "" ]
        then

        if [[ $(type -f open 2>&1) =~ "not found" ]]
        then
            log "🔗 Cannot open browser, use url:"
            echo "http://127.0.0.1:3000"
        else
            if [ "$browser" != "" ]
            then
            log "🤖 automatically (disable with 'playground config open-grafana-in-browser automatically false') open grafana in browser $browser (you can change browser with 'playground config open-grafana-in-browser browser <browser>')"
            log "🤖 Open grafana with browser $browser (login/password is admin/password)"
            open -a "$browser" "http://127.0.0.1:3000"
            else
            log "🤖 automatically (disable with 'playground config open-grafana-in-browser automatically false') open grafana in default browser (you can set browser with 'playground config open-grafana-in-browser browser <browser>')"
            log "🤖 Open grafana (login/password is admin/password)"
            open "http://127.0.0.1:3000"
            fi
        fi
        fi
    fi
    log "🛡️ Prometheus is reachable at http://127.0.0.1:9090"
    log "📊 Grafana is reachable at http://127.0.0.1:3000 (login/password is admin/password)"
    log "✨ Prometheus config in use: $working_dir/prometheus/prometheus.yml"

    log "⏳ It will take a couple of minutes for metrics to be collected and displayed in Grafana dashboard, please wait..."

else
    logerror "🚨 This command is only supported for fully managed connectors"
    exit 1
fi