file="${args[--file]}"
max_wait="${args[--max-wait]}"
ignore_errors="${args[--ignore-errors]}"
width="${args[--width]}"
query_timeout="${args[--query-timeout]}"

if [[ -n "$file" ]]
then
    sql=$(cat "$file")
else
    sql=$(read_stdin_if_any)
fi

if [[ -z "${sql//[[:space:]]/}" ]]
then
    logerror "❌ no ksqlDB statements: pass them on stdin (heredoc) or with --file"
    exit 1
fi

get_ksqldb_url_and_security
container="ksqldb-cli"
timeout_options=""
if is_ansible_host ksqldb-server
then
    # environment/ansible: no ksqldb-cli container, the ksql cli of the archive is on the ksqldb-server host
    container="ksqldb-server"
    # with docker exec -t, timeout runs the cli in a background process group, and the cli is stopped as soon as it
    # touches the terminal (it never returns): keep it in the foreground (the timeout still stops it)
    timeout_options="--foreground"
fi
if [[ -z "$(docker ps --filter "name=^${container}$" --filter "status=running" --format "{{.Names}}")" ]]
then
    logerror "❌ the $container container is not running: start an example with playground run --enable-ksqldb"
    exit 1
fi

if [[ -z "$width" ]]
then
    # the tables of the cli split this width between their columns: without a terminal, they are 5 characters wide
    width=200
    if [ -t 1 ]
    then
        width=$(tput cols 2>/dev/null || echo 200)
    fi
fi

ksqldb_version=$(curl $ksqldb_security -s "${ksqldb_url}/info" | jq -r '.KsqlServerInfo.version // empty' 2>/dev/null)

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
printf '%s\n' "$sql" > "$tmp_dir/statements.sql"
docker cp "$tmp_dir/statements.sql" "$container:/tmp/playground-ksqldb-statements.sql" > /dev/null

cli_options="$ksqldb_cli_security"
if [[ -n "$query_timeout" ]]
then
    cli_options="$cli_options --query-timeout $((query_timeout * 1000))"
fi

log "🧮 Running ksqlDB statements in $container container (ksqlDB ${ksqldb_version:-?}, $ksqldb_url)"
rc=0
# -t + stty: the cli formats the tables for the terminal width. --file runs every statement, even after a failing one,
# and prints the errors in red
output=$(docker exec -t "$container" sh -c "stty cols $width 2>/dev/null; timeout $timeout_options $max_wait ksql $cli_options --file /tmp/playground-ksqldb-statements.sql ${ksqldb_internal_url:-http://ksqldb-server:8088}" 2>&1) || rc=$?
output=$(printf '%s\n' "$output" | tr -d '\r')

# the errors of the statements are the red lines
errors=$(printf '%s\n' "$output" | grep $'\x1b\[31m' | sed 's/\x1b\[[0-9;]*m//g' || true)

# drop the jvm warnings and the startup lines of the cli, keep the results
printf '%s\n' "$output" \
    | grep -v -E "^WARNING: |^FIPS Mode: |^  -> Using netty-tcnative|^Debug Options: ?$" \
    | sed '/\x1b\[31m/s/^/❌ /' \
    | sed 's/\x1b\[[0-9;]*m//g' \
    | cat -s | sed '1{/^$/d;}'

if [ $rc -eq 124 ]
then
    logerror "⏱️ the ksql cli was stopped after ${max_wait}s: a push query (EMIT CHANGES) never ends without a LIMIT"
    logerror "   add LIMIT <n> to the query, set --query-timeout, or increase --max-wait"
    exit 1
fi

if [[ -n "$errors" ]]
then
    nb_errors=$(printf '%s\n' "$errors" | wc -l | tr -d ' ')
    if [[ -n "$ignore_errors" ]]
    then
        logwarn "⚠️ $nb_errors ksqlDB statement(s) failed (ignored, --ignore-errors is set)"
    else
        logerror "❌ $nb_errors ksqlDB statement(s) failed (the other statements were run):"
        printf '%s\n' "$errors" | sed 's/^/   /' >&2
        logerror "   🎓 add --ignore-errors when the failure is expected"
        exit 1
    fi
fi

if [ $rc -ne 0 ]
then
    if printf '%s\n' "$output" | grep -q -iE "Unauthorized|401"
    then
        logerror "❌ the ksql cli could not authenticate to ksqldb-server"
    fi
    logerror "❌ the ksql cli exited with code $rc"
    exit 1
fi
