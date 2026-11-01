json="${args[--json]}"

get_ksqldb_url_and_security

if ! response=$(ksqldb_rest_statement "SHOW STREAMS; SHOW TABLES; SHOW QUERIES;")
then
    logerror "❌ could not list the streams, tables and queries:"
    echo "$response" | jq -r '.message // .' >&2
    exit 1
fi

if [[ -n "$json" ]]
then
    echo "$response" | jq '{
        streams: ([.[] | select(."@type" == "streams") | .streams[]]),
        tables: ([.[] | select(."@type" == "tables") | .tables[]]),
        queries: ([.[] | select(."@type" == "queries") | .queries[]])
    }'
    exit 0
fi

ksqldb_version=$(curl $ksqldb_security -s "${ksqldb_url}/info" | jq -r '.KsqlServerInfo.version // empty' 2>/dev/null)
log "🧮 Streams, tables and queries of ksqlDB ${ksqldb_version:-?} ($ksqldb_url)"

# the KSQL_PROCESSING_LOG stream and the internal sources are listed too: they are part of the server
{
    printf 'TYPE\tNAME\tTOPIC\tKEY FORMAT\tVALUE FORMAT\tWINDOWED\n'
    echo "$response" | jq -r '.[] | select(."@type" == "streams" or ."@type" == "tables") | (.streams // .tables)[]
        | [.type, .name, .topic, .keyFormat, .valueFormat, (.isWindowed | tostring)] | @tsv'
} | column -t -s $'\t'

nb_queries=$(echo "$response" | jq '[.[] | select(."@type" == "queries") | .queries[]] | length')
echo ""
if [ "$nb_queries" -eq 0 ]
then
    log "🔎 No persistent query"
    exit 0
fi
{
    printf 'QUERY ID\tSTATE\tTYPE\tSINKS\tSINK TOPICS\n'
    echo "$response" | jq -r '.[] | select(."@type" == "queries") | .queries[]
        | [.id, (.state // "?"), (.queryType // "?"), ((.sinks // []) | join(",")), ((.sinkKafkaTopics // []) | join(","))] | @tsv'
} | column -t -s $'\t'

if echo "$response" | jq -e '[.[] | select(."@type" == "queries") | .queries[] | select(.state == "ERROR")] | length > 0' > /dev/null
then
    echo ""
    logwarn "⚠️ a query is in ERROR: playground ksqldb describe --source <its sink> shows its errors, playground container logs -c ksqldb-server --errors the stack trace"
fi
