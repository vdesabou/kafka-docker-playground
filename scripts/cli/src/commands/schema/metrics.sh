json="${args[--json]}"
verbose="${args[--verbose]}"

container="schema-registry"
if is_mdc_environment
then
    get_mdc_cluster
    container="schema-registry-$mdc_cluster"
fi

# label|object name|attribute|format|warning (see jmx_digest_read)
spec="Leader|kafka.schema.registry:type=master-slave-role|master-slave-role|bool|
Requests/s|kafka.schema.registry:type=jersey-metrics|request-rate|rate|
Client errors (4xx)/s|kafka.schema.registry:type=jersey-metrics,http_status_code=4xx|request-error-rate|rate|
Server errors (5xx)/s|kafka.schema.registry:type=jersey-metrics,http_status_code=5xx|request-error-rate|rate|gt0
Server errors (5xx, total)|kafka.schema.registry:type=jersey-metrics,http_status_code=5xx|request-error-total|int|gt0
Request latency avg|kafka.schema.registry:type=jersey-metrics|request-latency-avg|ms|
Request latency p99|kafka.schema.registry:type=jersey-metrics|request-latency-99|ms|
Active connections|kafka.schema.registry:type=jetty-metrics|connections-active|int|
Registered schemas|kafka.schema.registry:type=registered-count|registered-count|int|
Avro schemas created|kafka.schema.registry:type=avro-schemas-created|avro-schemas-created|int|
JSON schemas created|kafka.schema.registry:type=json-schemas-created|json-schemas-created|int|
Protobuf schemas created|kafka.schema.registry:type=protobuf-schemas-created|protobuf-schemas-created|int|
Avro schemas deleted|kafka.schema.registry:type=avro-schemas-deleted|avro-schemas-deleted|int|
JSON schemas deleted|kafka.schema.registry:type=json-schemas-deleted|json-schemas-deleted|int|
Protobuf schemas deleted|kafka.schema.registry:type=protobuf-schemas-deleted|protobuf-schemas-deleted|int|"
spec=$(echo "$spec" | sed 's/^[[:space:]]*//')

[[ -n "$verbose" ]] && log "🐞 reading the kafka.schema.registry MBeans of $container (jmxterm in the container)"
jmx_digest_collect "$spec" "$container $container"
if [[ -z "$JMX_DIGEST_IDS" ]]
then
    logerror "❌ no Schema Registry metrics could be read from container $container"
    exit 1
fi

if [[ -n "$json" ]]
then
    jmx_digest_json container
    exit 0
fi

log "📈 Schema Registry metrics (rates and latencies over the last samples, counts since the start)"
jmx_digest_table "CONTAINER" "$spec"

errors=$(jmx_digest_value "$container" "Server errors (5xx, total)")
if awk -v v="${errors:-0}" 'BEGIN { exit !(v + 0 > 0) }'
then
    logwarn "⚠️ requests failed with a 5xx: playground container logs -c $container --errors"
fi
log "🎓 4xx are answers to the client (404: subject or version not found, 409: incompatible schema, 422: invalid schema),"
log "   not failures of Schema Registry"
log "🎓 subjects, versions and compatibility: playground schema list; the requests of the clients: playground container logs -c $container"
