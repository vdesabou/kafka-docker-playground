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

# first free host port from $1: the grafana profile of the example already publishes 3000 and 9090
find_free_port() {
    local port="$1"
    while (echo > /dev/tcp/127.0.0.1/$port) >/dev/null 2>&1
    do
        port=$((port + 1))
    done
    echo "$port"
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
        # get_ccloud_connector_lcc uses jq -e: without || true an unknown name would end the command silently
        connectorId=$(get_ccloud_connector_lcc "$connector" || true)
        if [[ -z "$connectorId" ]] || [[ "$connectorId" == "null" ]]
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

    mkdir -p "$working_dir"
    chmod 700 "$working_dir"
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

    escaped_cloud_api_key=$(escape_sed_replacement "$CONFLUENT_CLOUD_API_KEY")
    escaped_cloud_api_secret=$(escape_sed_replacement "$CONFLUENT_CLOUD_API_SECRET")
    escaped_kafka_ids_csv=$(escape_sed_replacement "$kafka_ids_csv")
    escaped_connector_ids_csv=$(escape_sed_replacement "$connector_ids_csv")
    escaped_sr_ids_csv=$(escape_sed_replacement "$sr_ids_csv")

    sed -e "s|\$CONFLUENT_CLOUD_API_KEY|$escaped_cloud_api_key|g" \
        -e "s|\$CONFLUENT_CLOUD_API_SECRET|$escaped_cloud_api_secret|g" \
        -e "s|\${CCLOUD_KAFKA_LKC_IDS}|$escaped_kafka_ids_csv|g" \
        -e "s|\${CCLOUD_CONNECT_LCC_IDS}|$escaped_connector_ids_csv|g" \
        -e "s|\${CCLOUD_SR_LSRC_IDS}|$escaped_sr_ids_csv|g" \
        "$display_metrics_dir/prometheus/prometheus.yml" > "$working_dir/prometheus/prometheus.yml"
    # holds the Cloud API key and secret: owner only, and removed once copied into the container
    chmod 600 "$working_dir/prometheus/prometheus.yml"

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

    prometheus_port=$(find_free_port 9090)
    grafana_port=$(find_free_port 3000)
    if [ "$prometheus_port" != "9090" ] || [ "$grafana_port" != "3000" ]
    then
        log "🔀 ports 9090 / 3000 are in use (grafana of the example?), using $prometheus_port / $grafana_port"
    fi

    # the config is copied into the container (not bind mounted) so that the file with the secret can be deleted
    docker create --name prometheus-display-metrics-api-with-grafana --hostname prometheus \
        --network "$network_name" \
        -p $prometheus_port:9090 \
        prom/prometheus:v2.55.1 \
        --config.file=/etc/prometheus/prometheus.yml >/dev/null
    # docker cp keeps the mode and makes root the owner, and prometheus runs as nobody: it must be world readable in
    # the container (locally the folder stays owner only, and the file is removed right after the copy)
    chmod 644 "$working_dir/prometheus/prometheus.yml"
    docker cp "$working_dir/prometheus/prometheus.yml" prometheus-display-metrics-api-with-grafana:/etc/prometheus/prometheus.yml >/dev/null
    rm -f "$working_dir/prometheus/prometheus.yml"
    docker start prometheus-display-metrics-api-with-grafana >/dev/null

    docker run -d --name grafana-display-metrics-api-with-grafana --hostname grafana \
        --network "$network_name" \
        -p $grafana_port:3000 \
        -e GF_SECURITY_ADMIN_USER=admin \
        -e GF_SECURITY_ADMIN_PASSWORD=password \
        -e GF_USERS_ALLOW_SIGN_UP=false \
        -v "$working_dir/grafana/provisioning:/etc/grafana/provisioning:ro" \
        -v "$working_dir/grafana/config/grafana.ini:/etc/grafana/grafana.ini:ro" \
        grafana/grafana:11.1.0 >/dev/null

    sleep 3
    for c in prometheus-display-metrics-api-with-grafana grafana-display-metrics-api-with-grafana
    do
        if [ "$(docker inspect -f '{{.State.Running}}' $c 2>/dev/null)" != "true" ]
        then
            logerror "❌ container $c is not running, its last logs:"
            docker logs --tail 20 $c 2>&1
            exit 1
        fi
    done

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

        if ! can_open_url
        then
            log "🔗 Cannot open browser, use url:"
            echo "http://127.0.0.1:$grafana_port"
        else
            if [ "$browser" != "" ]
            then
            log "🤖 automatically (disable with 'playground config open-grafana-in-browser automatically false') open grafana in browser $browser (you can change browser with 'playground config open-grafana-in-browser browser <browser>')"
            log "🤖 Open grafana with browser $browser (login/password is admin/password)"
            open_url "http://127.0.0.1:$grafana_port" "$browser"
            else
            log "🤖 automatically (disable with 'playground config open-grafana-in-browser automatically false') open grafana in default browser (you can set browser with 'playground config open-grafana-in-browser browser <browser>')"
            log "🤖 Open grafana (login/password is admin/password)"
            open_url "http://127.0.0.1:$grafana_port"
            fi
        fi
        fi
    fi
    log "🛡️ Prometheus is reachable at http://127.0.0.1:$prometheus_port"
    log "📊 Grafana is reachable at http://127.0.0.1:$grafana_port (login/password is admin/password)"
    log "🧹 to stop them: docker rm -f prometheus-display-metrics-api-with-grafana grafana-display-metrics-api-with-grafana"

    log "⏳ It will take a couple of minutes for metrics to be collected and displayed in Grafana dashboard, please wait..."

else
    logerror "🚨 This command is only supported for fully managed connectors"
    exit 1
fi