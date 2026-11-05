json="${args[--json]}"
verbose="${args[--verbose]}"

container="ksqldb-server"

# label|object name|attribute|format|warning (see jmx_digest_read). The MBean name holds the ksql.service.id
# (_confluent-ksql-<service id>ksql-engine-query-stats): matched with a *
stats="io.confluent.ksql.metrics:type=*ksql-engine-query-stats"
spec="Persistent queries|$stats|num-persistent-queries|int|
Running queries|$stats|RUNNING-queries|int|
Queries in ERROR|$stats|ERROR-queries|int|gt0
Not running queries|$stats|NOT_RUNNING-queries|int|gt0
Rebalancing queries|$stats|REBALANCING-queries|int|gt0
Pending shutdown queries|$stats|PENDING_SHUTDOWN-queries|int|
Pending error queries|$stats|PENDING_ERROR-queries|int|gt0
Error rate|$stats|error-rate|rate|gt0
Active queries|$stats|num-active-queries|int|
Idle queries|$stats|num-idle-queries|int|
Messages consumed/s|$stats|messages-consumed-per-sec|rate|
Messages produced/s|$stats|messages-produced-per-sec|rate|
Liveness indicator|$stats|liveness-indicator|int|"
spec=$(echo "$spec" | sed 's/^[[:space:]]*//')

[[ -n "$verbose" ]] && log "🐞 reading the io.confluent.ksql.metrics MBeans of $container (jmxterm in the container)"
jmx_digest_collect "$spec" "$container $container"
if [[ -z "$JMX_DIGEST_IDS" ]]
then
    logerror "❌ no ksqlDB metrics could be read from container $container"
    exit 1
fi

if [[ -n "$json" ]]
then
    jmx_digest_json container
    exit 0
fi

log "📈 ksqlDB metrics (query states now, rates over the last samples)"
jmx_digest_table "CONTAINER" "$spec"

for label in "Queries in ERROR" "Not running queries" "Rebalancing queries"
do
    value=$(jmx_digest_value "$container" "$label")
    if awk -v v="${value:-0}" 'BEGIN { exit !(v + 0 > 0) }'
    then
        logwarn "⚠️ $label: $(printf '%.0f' "$value"), see playground ksqldb list (state of each query) and playground ksqldb describe --source <its sink> (its errors)"
    fi
done
log "🎓 the records a query could not process are in the KSQL_PROCESSING_LOG stream"
