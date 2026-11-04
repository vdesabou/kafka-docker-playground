container="${args[--container]}"
engine="${args[--engine]}"
user="${args[--user]}"
password="${args[--password]}"
database="${args[--database]}"
file="${args[--file]}"
sql="${args[--sql]}"
ignore_errors="${args[--ignore-errors]}"
verbose="${args[--verbose]}"

if [[ -n "$file" ]]
then
    statements=$(cat "$file")
elif [[ -n "$sql" ]]
then
    statements="$sql"
else
    statements=$(read_stdin_if_any)
fi

if [[ -z "${statements//[[:space:]]/}" ]]
then
    logerror "❌ no statements: pass them on stdin (heredoc), with --file or with --sql"
    exit 1
fi

db_resolve_container "$container" "$engine" || exit 1
db_resolve_connection "$user" "$password" "$database"

log "🛢️ Running SQL in $db_container $db_kind ($db_engine, ${db_client##*/}${db_user:+, user $db_user}${db_database:+, database $db_database})"

stop="stop"
if [[ -n "$ignore_errors" ]]
then
    stop="continue"
fi

output_file=$(mktemp -t pg-db-sql-XXXXXXXXXX)
trap 'rm -f "$output_file"' EXIT

# the output is shown as it comes (a long script), and kept to count the errors
printf '%s\n' "$statements" | db_exec script "$stop" "$verbose" | tee "$output_file"
rc=${PIPESTATUS[1]}

error_regex=$(db_error_regex)
nb_errors=$(grep -c -E "$error_regex" "$output_file" || true)

if [[ -n "$ignore_errors" ]]
then
    if [ "$nb_errors" -gt 0 ] || [ $rc -ne 0 ]
    then
        logwarn "⚠️ ${nb_errors} error(s) in the output (ignored, --ignore-errors is set)"
    fi
    exit 0
fi

# mongosh runs every command and may exit with 0 after a failing one: the errors in the output decide
if [ $rc -ne 0 ] || [ "$nb_errors" -gt 0 ]
then
    if [[ "$db_engine" == "mongodb" ]]
    then
        logerror "❌ ${nb_errors} command(s) failed, see the error(s) above"
    else
        logerror "❌ a statement failed (the next ones were not run), see the error above"
    fi
    logerror "   🎓 add --ignore-errors to run every statement"
    exit 1
fi
