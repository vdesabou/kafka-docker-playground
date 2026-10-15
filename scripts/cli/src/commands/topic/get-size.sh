topic="${args[--topic]}"
show_internal="${args[--show-internal]}"

if [[ -n "$topic" ]]
then
    topics=$(echo "$topic" | tr ' ' '\n')
    log "📏 Size of topic(s) $topic"
elif [[ -n "$show_internal" ]]
then
    log "📏 Size of topics, largest first (internal topics are included)"
    topics=$(playground get-topic-list)
else
    log "📏 Size of topics, largest first (internal topics are excluded)"
    topics=$(playground get-topic-list --skip-internal-topics)
fi

if [[ ! -n "$topics" ]]
then
    logwarn "No topic found"
    exit 0
fi

get_environment_used

if [[ "$environment" == "ccloud" ]]
then
    # DescribeLogDirs is rejected by Confluent Cloud (ClusterAuthorizationException), use Metrics API instead
    get_kafka_docker_playground_dir
    if [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta ]
    then
        logerror "❌ $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta has not been generated"
        exit 1
    fi
    cluster=$(grep "KAFKA CLUSTER ID" $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta | cut -d " " -f 5)

    load_secrets_env_vars CONFLUENT_CLOUD_API_KEY CONFLUENT_CLOUD_API_SECRET
    if [ -z "$CONFLUENT_CLOUD_API_KEY" ] || [ -z "$CONFLUENT_CLOUD_API_SECRET" ]
    then
        logerror "❌ environment variables CONFLUENT_CLOUD_API_KEY and CONFLUENT_CLOUD_API_SECRET should be set to use --sort-by-size with ccloud environment"
        logerror "Set them with Cloud API key, see https://docs.confluent.io/cloud/current/access-management/authenticate/api-keys/api-keys.html#cloud-cloud-api-keys"
        exit 1
    fi

    log "〽️ Sizes are retained_bytes from Metrics API for cluster $cluster, they lag a few minutes behind"
    metrics_data="[]"
    page_token=""
    while true
    do
        url="https://api.telemetry.confluent.cloud/v2/metrics/cloud/query"
        if [[ -n "$page_token" ]]
        then
            url="$url?page_token=$page_token"
        fi
        set +e
        response=$(curl -sS -u "$CONFLUENT_CLOUD_API_KEY:$CONFLUENT_CLOUD_API_SECRET" -H "Content-Type: application/json" -X POST "$url" -d @- << EOF
{
    "aggregations": [{ "metric": "io.confluent.kafka.server/retained_bytes" }],
    "filter": { "field": "resource.kafka.id", "op": "EQ", "value": "$cluster" },
    "granularity": "PT1M",
    "group_by": ["metric.topic", "metric.partition"],
    "intervals": ["PT15M/now|m"],
    "limit": 1000
}
EOF
)
        set -e
        if ! echo "$response" | jq -e '.data' > /dev/null 2>&1
        then
            logerror "❌ Metrics API query failed: $response"
            exit 1
        fi
        metrics_data=$(jq -s '.[0] + .[1].data' <(echo "$metrics_data") <(echo "$response"))
        page_token=$(echo "$response" | jq -r '.meta.pagination.next_page_token // empty')
        if [[ ! -n "$page_token" ]]
        then
            break
        fi
    done

    # keep the latest point of each partition, size of a topic is the sum of its partitions
    sizes=$(echo "$metrics_data" | jq -r --arg topics "$topics" '
        ($topics | split("\n") | map(select(length > 0))) as $wanted
        | map(select(."metric.topic" | IN($wanted[])))
        | group_by(."metric.topic", ."metric.partition") | map(max_by(.timestamp))
        | group_by(."metric.topic") | map({topic: .[0]."metric.topic", partitions: length, size: (map(.value) | add)})
        | sort_by(-.size, .topic)[]
        | "\(.size)\t\(.partitions)\t\(.topic)"')

    if [[ ! -n "$sizes" ]]
    then
        logwarn "No retained_bytes metric found in the last 15 minutes for cluster $cluster (new topics and clusters take a few minutes to show up in Metrics API)"
        exit 0
    fi
else
    get_security_broker "--command-config"

    topic_list=$(echo "$topics" | paste -sd, -)

    set +e
    if [[ "$environment" == cfk* ]]
    then
        log_dirs=$(kubectl -n confluent exec $container -- kafka-log-dirs --describe --bootstrap-server $bootstrap_server $security --topic-list "$topic_list" 2>/dev/null | grep '^{')
    else
        log_dirs=$(docker exec $container kafka-log-dirs --describe --bootstrap-server $bootstrap_server $security --topic-list "$topic_list" 2>/dev/null | grep '^{')
    fi
    set -e

    if [[ ! -n "$log_dirs" ]]
    then
        logerror "❌ Could not get log directories information from the brokers"
        exit 1
    fi

    # size of a partition is the largest of its replicas, size of a topic is the sum of its partitions
    sizes=$(echo "$log_dirs" | jq -r '
        [.brokers[].logDirs[].partitions[]
            | {topic: (.partition | sub("-[0-9]+$"; "")), partition: .partition, size: .size}]
        | group_by(.partition) | map({topic: .[0].topic, size: (map(.size) | max)})
        | group_by(.topic) | map({topic: .[0].topic, partitions: length, size: (map(.size) | add)})
        | sort_by(-.size, .topic)[]
        | "\(.size)\t\(.partitions)\t\(.topic)"')

    if [[ ! -n "$sizes" ]]
    then
        logwarn "No partition found on the brokers for topic(s) $(echo $topics)"
        exit 0
    fi
fi

echo "$sizes" \
| awk -F'\t' '
    function human(bytes,   units, i) {
        split("B KB MB GB TB", units, " ")
        i = 1
        while (bytes >= 1024 && i < 5) { bytes /= 1024; i++ }
        return (i == 1) ? sprintf("%d %s", bytes, units[i]) : sprintf("%.1f %s", bytes, units[i])
    }
    BEGIN { printf "%-10s %-10s %s\n", "SIZE", "PARTITIONS", "TOPIC" }
    { printf "%-10s %-10s %s\n", human($1), $2, $3 }'
