connector="${args[--connector]}"
topic="${args[--topic]}"
table="${args[--table]}"
eval "key_fields=(${args[--key-field]:-})"
eval "ignore_fields=(${args[--ignore-field]:-})"
container="${args[--container]}"
user="${args[--user]}"
password="${args[--password]}"
database="${args[--database]}"
rows_file="${args[--rows-file]}"
direction="${args[--direction]}"
max_examples="${args[--max-examples]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

if [[ -n "$json" ]]
then
    # stdout only gets the json document
    exec 3>&1 1>&2
fi

if ! command -v python3 > /dev/null 2>&1
then
    logerror "❌ python3 is required to compare the records and the rows"
    exit 2
fi

connector_type=$(playground state get run.connector_type)

if [[ -z "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No $connector_type connector is running !"
        exit 2
    fi
    if [ $(echo "$connector" | wc -w) -gt 1 ]
    then
        logerror "❌ several connectors are running ($connector), use --connector"
        exit 2
    fi
fi

if ! get_connector_config_json "$connector"
then
    logerror "❌ could not get the config of connector $connector"
    exit 2
fi
config="$curl_output"

# value of the first config key set (empty values count as not set)
function cfg () {
    local key value
    for key in "$@"
    do
        value=$(jq -r --arg k "$key" '.[$k] // empty | tostring' <<< "$config")
        if [[ -n "$value" ]]
        then
            echo "$value"
            return 0
        fi
    done
}

# a value that is not usable as is: masked by the REST API or the fully managed API, or a config provider reference
function is_hidden () {
    [[ -z "$1" || "$1" == *'${'* || "$1" == *"•"* || "$1" =~ ^\*+$ || "$1" == "[hidden]" ]]
}

# the literal value of a config key in the example script that was run, for a password masked by the REST API
function literal_in_test_file () {
    local key="$1" test_file
    test_file=$(playground state get run.test_file 2>/dev/null)
    [[ -f "$test_file" ]] || return 0
    grep -o -E "\"${key//./\\.}\"[[:space:]]*:[[:space:]]*\"[^\"\$]*\"" "$test_file" | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/'
}

# the topic name after the RegexRouter transforms of the connector (in their order): what a source writes to, what
# ${topic} of table.name.format is for a sink. RegexRouter only renames a topic that matches the whole regex
function apply_regex_routers () {
    local name="$1" alias type regex replacement
    local aliases
    IFS=',' read -r -a aliases <<< "$(cfg transforms)"
    for alias in "${aliases[@]}"
    do
        alias="${alias// /}"
        type=$(cfg "transforms.$alias.type")
        [[ "$type" != *RegexRouter* ]] && continue
        regex=$(cfg "transforms.$alias.regex")
        replacement=$(cfg "transforms.$alias.replacement")
        # "if True:" keeps the code valid once bashly indents it in scripts/cli/playground: python < 3.14 does not
        # dedent the code of -c, and the IndentationError would silently leave the topic name unchanged
        name=$(python3 -I -c 'if True:
    import re, sys
    name, regex, replacement = sys.argv[1:4]
    m = re.fullmatch(regex, name)
    if m:
        # java replacement syntax: $1, \$ for a literal $
        out = re.sub(r"\\\$|\$(\d+)", lambda g: "$" if g.group(0) == "\\$" else (m.group(int(g.group(1))) or ""), replacement)
        name = out
    print(name)' "$name" "$regex" "$replacement" 2>/dev/null || echo "$name")
    done
    echo "$name"
}

connector_class=$(cfg connector.class)
class_lc="${connector_class,,}"

if [[ -z "$direction" ]]
then
    if [[ -n "$(cfg topics topics.regex)" ]]
    then
        direction="sink"
    else
        direction="source"
    fi
fi

key_source="auto"
key_origin="--key-field"
object_store=""
primitive_key_field=""
deletes="true"
allow_duplicates=""
default_ignore=()

# ---- the key, the table and whether deletes are applied, from the config ----------------------------------------
pk_mode=$(cfg pk.mode primary.key.mode)
pk_fields=$(cfg pk.fields primary.key.fields)
if [[ "$direction" == "sink" ]]
then
    deletes=$(cfg delete.enabled)
    deletes="${deletes:-false}"
    if [[ -z "$topic" ]]
    then
        topic=$(cfg topics)
        if [[ "$topic" == *,* ]]
        then
            logerror "❌ connector $connector reads several topics ($topic): pass --topic with one of them"
            exit 2
        fi
        if [[ -z "$topic" ]]
        then
            logerror "❌ connector $connector uses topics.regex ($(cfg topics.regex)): pass --topic"
            exit 2
        fi
    fi
    if storage_is_object_store_sink "$class_lc"
    then
        # an object store sink appends every record: no key, no delete, each record once
        object_store="1"
        deletes="false"
        pk_mode=""
    fi
    case "${pk_mode,,}" in
        record_key)
            key_source="key"
            if [[ ${#key_fields[@]} -eq 0 && -n "$pk_fields" ]]
            then
                IFS=',' read -r -a key_fields <<< "$pk_fields"
                key_origin="pk.fields, pk.mode $pk_mode"
                # a key that is not a struct goes to the one column of pk.fields
                primitive_key_field="${key_fields[0]}"
            fi
        ;;
        record_value)
            key_source="value"
            if [[ ${#key_fields[@]} -eq 0 && -n "$pk_fields" ]]
            then
                IFS=',' read -r -a key_fields <<< "$pk_fields"
                key_origin="pk.fields, pk.mode $pk_mode"
            fi
        ;;
        kafka)
            if [[ ${#key_fields[@]} -eq 0 ]]
            then
                key_source="coordinates"
            fi
        ;;
        record_header)
            logwarn "⚠️ pk.mode record_header: the key is in the headers, pass --key-field with the columns to compare on"
        ;;
    esac
    if [[ -z "$table" && -z "$object_store" ]]
    then
        if [[ "$class_lc" == *mongo* ]]
        then
            table=$(cfg collection)
            table="${table:-$topic}"
            [[ -z "$database" ]] && database=$(cfg database)
            # a document id generated by the sink (BsonOidStrategy, the default) is in no record
            if [[ "$(cfg document.id.strategy)" != *Provided* ]]
            then
                default_ignore+=("_id")
            fi
            if [[ -n "$(cfg delete.on.null.values)" ]]
            then
                deletes=$(cfg delete.on.null.values)
            fi
        else
            table_format=$(cfg table.name.format)
            table_format="${table_format:-\${topic\}}"
            topic_for_table=$(apply_regex_routers "$topic")
            # the Debezium JDBC sink (DefaultTableNamingStrategy) replaces the dots of the topic name
            if [[ "$class_lc" == io.debezium.connector.jdbc.* ]]
            then
                topic_for_table="${topic//./_}"
            fi
            table="${table_format//\$\{topic\}/$topic_for_table}"
        fi
    fi
else
    # source
    tables=$(cfg table.whitelist table.include.list collection.include.list)
    if [[ -z "$table" ]]
    then
        if [[ "$tables" == *,* ]]
        then
            logerror "❌ connector $connector captures several tables ($tables): pass --table and --topic"
            exit 2
        fi
        table="$tables"
        if [[ -z "$table" ]]
        then
            logerror "❌ could not tell the table of connector $connector from its config: pass --table"
            exit 2
        fi
    fi
    if [[ "$(cfg mode)" == "bulk" ]]
    then
        # bulk mode re-sends the whole table at each poll
        allow_duplicates="1"
    fi
    incrementing=$(cfg incrementing.column.name)
    if [[ ${#key_fields[@]} -eq 0 && -n "$incrementing" ]]
    then
        key_fields=("$incrementing")
        key_origin="incrementing.column.name"
    fi
    if [[ -z "$topic" ]]
    then
        prefix=$(cfg topic.prefix database.server.name)
        if [[ "$class_lc" == io.confluent.connect.jdbc.* || "$class_lc" == *source && -n "$(cfg incrementing.column.name timestamp.column.name)" ]]
        then
            # JDBC source: <topic.prefix><table> (query mode: <topic.prefix>)
            if [[ -n "$(cfg query)" ]]
            then
                topic="$prefix"
            else
                topic="${prefix}${table##*.}"
            fi
        elif [[ "$class_lc" == *sqlserver* ]]
        then
            # Debezium SQL Server: <prefix>.<database>.<schema>.<table>
            db_name=$(cfg database.names database.dbname)
            topic="${prefix}.${db_name%%,*}.${table}"
        else
            # Debezium: <prefix>.<schema or database>.<table>
            topic="${prefix}.${table}"
        fi
        topic=$(apply_regex_routers "$topic")
    fi
    # a captured "schema.table" is the table to read
fi

for f in "${default_ignore[@]}"
do
    ignore_fields+=("$f")
done

# ---- the database: the host of the connection url when it is a running container --------------------------------
if [[ -z "$rows_file" && -z "$object_store" ]]
then
    url=$(cfg connection.url connection.uri)
    host=$(cfg database.hostname connection.host)
    if [[ -z "$host" && -n "$url" ]]
    then
        # jdbc:postgresql://postgres:5432/db, jdbc:mysql://mysql:3306/db, jdbc:sqlserver://sqlserver:1433;databaseName=x,
        # jdbc:oracle:thin:@oracle:1521/ORCLPDB1, jdbc:oracle:thin:@//oracle:1521/ORCLPDB1, mongodb://u:p@mongodb:27017
        host=$(sed -E -e 's#^[a-z0-9:+]*(//|@//|@)##' -e 's#^[^@/]*@##' -e 's#[:/;?,].*$##' <<< "$url")
    fi
    if [[ -z "$container" && -n "$host" ]]
    then
        get_environment_used
        if [[ "$environment" == cfk* ]]
        then
            host="${host%%.*}"
        fi
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$host" || { [[ "$environment" == cfk* ]] && kubectl -n confluent get pod "$host" > /dev/null 2>&1; }
        then
            container="$host"
        fi
    fi
    if [[ -z "$database" && -n "$url" && "$class_lc" != *mongo* ]]
    then
        case "$url" in
            *databaseName=*|*database=*) database=$(sed -E 's#.*[;?&](databaseName|database)=([^;&]*).*#\2#' <<< "$url") ;;
            jdbc:oracle:*) database=$(sed -E 's#.*:[0-9]+[/:]([^?]*).*#\1#' <<< "$url") ;;
            jdbc:*//*/*) database=$(sed -E 's#^jdbc:[a-z0-9]+://[^/]*/([^?;]*).*#\1#' <<< "$url") ;;
        esac
    fi
    if [[ -z "$database" ]]
    then
        database=$(cfg database.dbname database.names)
        database="${database%%,*}"
    fi
    # connect as the connector does: the table is in its schema (Oracle), and it can read it
    if [[ -z "$user" ]]
    then
        config_user=$(cfg connection.user database.user)
        if [[ -z "$config_user" && "$url" == *user=* ]]
        then
            config_user=$(sed -E 's#.*[?&;]user=([^&;]*).*#\1#' <<< "$url")
        fi
        config_password=$(cfg connection.password database.password)
        if is_hidden "$config_password"
        then
            config_password=$(literal_in_test_file connection.password)
            [[ -z "$config_password" ]] && config_password=$(literal_in_test_file database.password)
        fi
        if [[ -z "$config_password" && "$url" == *password=* ]]
        then
            config_password=$(sed -E 's#.*[?&;]password=([^&;]*).*#\1#' <<< "$url")
        fi
        if [[ -n "$config_user" && -z "$password" ]] && ! is_hidden "$config_password" && [[ "$class_lc" != *mongo* ]]
        then
            user="$config_user"
            password="$config_password"
        fi
    fi
fi

tmp_dir=$(mktemp -d -t pg-reconcile-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# ---- the rows ---------------------------------------------------------------------------------------------------
if [[ -n "$rows_file" ]]
then
    cp "$rows_file" "$tmp_dir/rows.json"
    table_label=$(basename "$rows_file")
    table_kind="file"
elif [[ -n "$object_store" ]]
then
    log "🪣 Reading every object of topic $topic written by connector $connector (playground storage cat)"
    if ! playground storage cat --connector "$connector" --topic "$topic" --records --max-objects 0 > "$tmp_dir/rows.json" 2> "$tmp_dir/storage.log"
    then
        logerror "❌ could not read the objects of connector $connector:"
        grep -v '^\s*$' "$tmp_dir/storage.log" | tail -10
        exit 2
    fi
    table_label=$(grep -o -E '🪣 [^ ]+' "$tmp_dir/storage.log" | head -1 | sed 's/🪣 //')
    table_label="${table_label:-objects}"
    table_kind="objects in"
    flush_size=$(cfg flush.size)
    if [[ -n "$flush_size" && "$flush_size" != "1" ]]
    then
        log "🎓 an object is written every flush.size=$flush_size records (or rotate.interval.ms): up to $((flush_size - 1)) record(s) per partition after the last object are still in the task, not lost"
    fi
else
    if [[ -z "$table" ]]
    then
        logerror "❌ could not tell the table of connector $connector from its config: pass --table"
        exit 2
    fi
    db_resolve_container "$container" "" || exit 2
    db_resolve_connection "$user" "$password" "$database"
    # connected as the admin user (the password of the connector is masked): an Oracle table is in the schema of the
    # user of the connector
    if [[ "$db_engine" == "oracle" && "$table" != *.* && -n "$config_user" && "${db_user,,}" != "${config_user,,}" ]]
    then
        table="${config_user^^}.$table"
    fi
    table_kind="table"
    [[ "$db_engine" == "mongodb" ]] && table_kind="collection"
    log "🛢️ Reading $db_engine $table_kind $table ($db_container${db_user:+, user $db_user}${db_database:+, database $db_database})"
    rc=0
    db_dump_rows "$table" "$verbose" > "$tmp_dir/rows.json" || rc=$?
    if [[ $rc -eq 2 ]]
    then
        logerror "❌ table $table does not exist in $db_container${db_database:+ (database $db_database)}: pass --table (schema.table works too), --database or --user"
        tail -5 "$tmp_dir/rows.json"
        exit 2
    elif [[ $rc -ne 0 ]]
    then
        logerror "❌ could not read table $table in $db_container:"
        tail -10 "$tmp_dir/rows.json"
        exit 2
    fi
    table_label="$table"
fi

# ---- the records ------------------------------------------------------------------------------------------------
log "📥 Reading every record of topic $topic"
if ! playground topic consume --topic "$topic" --json --max-messages -1 > "$tmp_dir/records.json" 2> "$tmp_dir/consume.log"
then
    logerror "❌ could not read topic $topic:"
    grep -v '^\s*$' "$tmp_dir/consume.log" | tail -10
    if [[ "$direction" == "source" ]]
    then
        logerror "   🎓 the topic name was computed from the config of the connector: pass --topic if it is another one"
    fi
    exit 2
fi

# ---- the comparison ---------------------------------------------------------------------------------------------
joined_keys=$(IFS=,; echo "${key_fields[*]}")
joined_ignore=$(IFS=,; echo "${ignore_fields[*]}")
reconcile_args=(
    "--records=$tmp_dir/records.json" "--rows=$tmp_dir/rows.json" "--direction=$direction"
    "--key-fields=$joined_keys" "--key-origin=$key_origin" "--key-source=$key_source"
    "--primitive-key-field=$primitive_key_field" "--deletes=$deletes" "--ignore-fields=$joined_ignore"
    "--topic=$topic" "--table=$table_label" "--table-kind=$table_kind" "--max-examples=$max_examples"
)
[[ -n "$allow_duplicates" ]] && reconcile_args+=(--allow-duplicates)
[[ -n "$json" ]] && reconcile_args+=(--json)

set +e
log "🧮 Comparing ($direction connector $connector${pk_mode:+, pk.mode $pk_mode}, deletes applied: $deletes)"
if [[ -n "$json" ]]
then
    python3 -I "$root_folder/tools/connector-reconcile/reconcile.py" "${reconcile_args[@]}" >&3
else
    python3 -I "$root_folder/tools/connector-reconcile/reconcile.py" "${reconcile_args[@]}"
fi
rc=$?
if [[ $rc -eq 2 ]]
then
    logerror "❌ the comparison failed, see the error above"
fi
exit $rc
