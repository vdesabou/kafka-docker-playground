container="${args[--container]}"
engine="${args[--engine]}"
user="${args[--user]}"
password="${args[--password]}"
database="${args[--database]}"
table="${args[--table]}"
where="${args[--where]}"
query="${args[--query]}"
min_expected_rows="${args[--min-expected-rows]}"
max_wait="${args[--max-wait]}"
interval="${args[--interval]}"
verbose="${args[--verbose]}"

if [[ -z "$table" && -z "$query" ]]
then
    logerror "❌ pass --table (and optionally --where), or --query"
    exit 1
fi
if [[ -n "$where" && -n "$query" ]]
then
    logerror "❌ --where applies to --table, put the condition in --query instead"
    exit 1
fi

db_resolve_container "$container" "$engine" || exit 1
db_resolve_connection "$user" "$password" "$database"

if [[ -n "$query" ]]
then
    what="query"
    count_query="$query"
    unit=""
elif [[ "$db_engine" == "mongodb" ]]
then
    what="collection $table"
    unit=" documents"
    count_query="db.getCollection('${table//\'/\\\'}').countDocuments(${where:-{\}})"
else
    what="table $table"
    count_query="SELECT COUNT(*) FROM $table${where:+ WHERE $where}"
fi

unit="${unit- rows}"
if [[ -n "$query" ]]
then
    log "⏳ Waiting up to $max_wait seconds for query to return at least $min_expected_rows ($db_container $db_kind)"
else
    log "⏳ Waiting up to $max_wait seconds for $what to contain at least $min_expected_rows${unit} ($db_container $db_kind)"
fi
missing_table_regex=$(db_missing_table_regex)
start_time=$SECONDS
last_count=""
nb_failures=0
while true
do
    rc=0
    output=$(printf '%s\n' "$count_query" | db_exec scalar stop "$verbose") || rc=$?
    verbose=""
    count=$(printf '%s\n' "$output" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -E '^[0-9]+$' | tail -1)

    if [[ -z "$count" ]] && [[ -z "$query" ]] && printf '%s\n' "$output" | grep -q -E "$missing_table_regex"
    then
        # a sink connector creates the table with its first records: it does not exist yet
        count=0
        nb_failures=0
        state="does not exist yet"
    elif [[ -z "$count" ]] || [ $rc -ne 0 ]
    then
        # wrong credentials, a syntax error, the database is restarting: fail after 3 in a row instead of waiting
        # until --max-wait
        nb_failures=$((nb_failures + 1))
        if [ $nb_failures -ge 3 ]
        then
            logerror "❌ could not count the rows of $what ($count_query):"
            printf '%s\n' "$output" | tail -10
            exit 1
        fi
        count=0
        state="could not be counted"
    else
        nb_failures=0
        if [[ -n "$query" ]]
        then
            state="returns $count"
        else
            state="contains $count${unit}"
        fi
    fi
    elapsed=$((SECONDS - start_time))

    if [ "$count" -ge "$min_expected_rows" ]
    then
        log "✅ $what $state (expected at least $min_expected_rows) after $elapsed seconds"
        break
    fi

    if [ "$state" != "$last_count" ]
    then
        log "⌛ $what $state (expected at least $min_expected_rows)"
        last_count="$state"
    fi

    if [ $elapsed -ge $max_wait ]
    then
        logerror "❌ $what $state after $max_wait seconds, expected at least $min_expected_rows${unit}"
        exit 1
    fi
    sleep $interval
done
