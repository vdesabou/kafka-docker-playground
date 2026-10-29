file="${args[--file]}"
max_wait="${args[--max-wait]}"

if [[ -n "$file" ]]
then
    sql=$(cat "$file")
else
    sql=$(read_stdin_if_any)
fi

if [[ -z "${sql//[[:space:]]/}" ]]
then
    logerror "❌ no SQL statements: pass them on stdin (heredoc) or with --file"
    exit 1
fi

get_flink_rest_url
flink_version=$(curl -s "${flink_rest_url}/overview" | jq -r '."flink-version"' 2>/dev/null)

# the sql-client container has the rest address of the jobmanager. it stops when someone quits the client after a
# docker attach: then use the sql client of the jobmanager image, which submits to its own rest api
container=$(docker ps --filter "name=^sql-client$" --filter "status=running" --format "{{.Names}}")
if [[ -z "$container" ]]
then
    container="$flink_jobmanager_container"
fi

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
printf '%s\n' "$sql" > "$tmp_dir/statements.sql"
docker cp "$tmp_dir/statements.sql" "$container:/tmp/playground-flink-statements.sql" > /dev/null

log "🐿️ Running Flink SQL statements in $container container (Flink $flink_version, $flink_rest_url)"
rc=0
output=$(docker exec "$container" timeout "$max_wait" bin/sql-client.sh -Dsql-client.execution.result-mode=tableau -f /tmp/playground-flink-statements.sql 2>&1) || rc=$?

if [ $rc -eq 124 ]
then
    # killed by timeout: the client then fails on its closed rest client with a long stack trace, hide it
    output=$(echo "$output" | sed '/^Exception in thread "main"/,$d')
fi

# drop the jvm warnings and the client banner, keep the statements and their results
echo "$output" | sed 's/\x1b\[[0-9;]*m//g' \
    | grep -v -E "^WARNING: |org\.jline\.utils\.Log|^\[INFO\] Executing SQL from file\.|^Command history file path|^Shutting down the session|^done\.$|^Flink SQL> ?$" \
    | perl -pe 's/^((?:Flink SQL)?> [^+\[](?:.*?[^> ])?)(\[(INFO|ERROR)\]|\+-)/$1\n$2/' \
    | cat -s | sed '1{/^$/d;}'

for job_id in $(echo "$output" | grep -o -E "Job ID: [0-9a-f]+" | awk '{print $3}')
do
    log "🚀 Job $job_id submitted, follow it with: playground flink list-jobs"
done

if echo "$output" | grep -q "\[ERROR\]"
then
    logerror "❌ a Flink SQL statement failed, the next statements were not run"
    if echo "$output" | grep -q -E "ValidationException: Could not find any factory for identifier|ClassNotFoundException"
    then
        logerror "   the connector or format is not in the Flink image: set FLINK_URL to the jar to download, or answer yes when --enable-flink asks for connectors"
    fi
    exit 1
fi

if [ $rc -eq 124 ]
then
    logwarn "⏱️ the SQL client was stopped after ${max_wait}s: a SELECT on an unbounded table never ends in streaming mode"
    logwarn "   add a LIMIT, use SET 'execution.runtime-mode' = 'batch' on a bounded source, or increase --max-wait"
    logwarn "   its job may still run on the cluster: playground flink list-jobs --state RUNNING, then playground flink cancel"
    exit 1
fi

if [ $rc -ne 0 ]
then
    logerror "❌ the SQL client exited with code $rc"
    exit 1
fi
