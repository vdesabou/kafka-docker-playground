# helpers of the db commands (playground db sql | wait-for-rows): find the database container of the running example,
# its engine and credentials, and run statements with its own client: docker exec, or kubectl exec on cfk, where the
# services of the example compose override (the databases) are pods named after the service

DB_SUPPORTED_ENGINES="oracle postgres mysql mariadb sqlserver db2 mongodb"

# engine of a database image (or container name), nothing if it is not a supported database
function db_engine_from_name () {
  local name="${1,,}"
  case "$name" in
    *mongo-express*|*mongoku*) return 1 ;;
    *mongo*) echo "mongodb" ;;
    *mariadb*) echo "mariadb" ;;
    *mysql*|*percona*) echo "mysql" ;;
    *postgres*|*postgis*|*timescale*) echo "postgres" ;;
    *mssql*|*sqlserver*|*azure-sql-edge*) echo "sqlserver" ;;
    *db2*) echo "db2" ;;
    *oracle*|*db-prebuilt*) echo "oracle" ;;
    *) return 1 ;;
  esac
}

# running containers (pods on cfk): one "name<tab>image" line each
function db_list_running () {
  if [[ "$db_transport" == "kubectl" ]]
  then
    kubectl -n confluent get pods --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null
  else
    docker ps --filter "status=running" --format '{{.Names}}{{"\t"}}{{.Image}}'
  fi
}

# sets db_transport, db_container and db_engine from --container / --engine, or from the running containers
function db_resolve_container () {
  local wanted_container="$1" wanted_engine="$2" name image engine
  db_container=""
  db_engine=""
  db_transport="docker"
  db_kind="container"
  get_environment_used
  if [[ "$environment" == cfk* ]]
  then
    db_transport="kubectl"
    db_kind="pod"
  fi

  if [[ -n "$wanted_container" ]]
  then
    if [[ "$db_transport" == "kubectl" ]]
    then
      wanted_container=$(resolve_container_name_for_environment "$wanted_container")
    fi
    image=$(db_list_running | awk -F'\t' -v n="$wanted_container" '$1 == n {print $2}')
    if [[ -z "$image" ]]
    then
      logerror "❌ $db_kind $wanted_container is not running"
      return 1
    fi
    db_container="$wanted_container"
    if [[ -n "$wanted_engine" ]]
    then
      db_engine="$wanted_engine"
      return 0
    fi
    db_engine=$(db_engine_from_name "$image" || db_engine_from_name "$db_container") || {
      logerror "❌ could not tell the database of $db_container (image $image): pass --engine ($DB_SUPPORTED_ENGINES)"
      return 1
    }
    return 0
  fi

  local candidates=()
  while IFS=$'\t' read -r name image
  do
    [[ -z "$name" ]] && continue
    engine=$(db_engine_from_name "$image" || db_engine_from_name "$name") || continue
    if [[ -n "$wanted_engine" && "$engine" != "$wanted_engine" ]]
    then
      continue
    fi
    candidates+=("$name:$engine")
  done < <(db_list_running)

  if [[ ${#candidates[@]} -eq 0 ]]
  then
    logerror "❌ no running ${wanted_engine:-database} container found (supported: $DB_SUPPORTED_ENGINES)"
    logerror "   🎓 start an example with a database, or pass --container (and --engine if the image name does not tell the database)"
    return 1
  fi
  if [[ ${#candidates[@]} -gt 1 ]]
  then
    logerror "❌ several database containers are running, pass --container with one of them:"
    printf '   %s\n' "${candidates[@]}" | sed 's/:/ (/;s/$/)/' >&2
    return 1
  fi
  db_container="${candidates[0]%%:*}"
  db_engine="${candidates[0]##*:}"
}

# runs "$@" in the database container, stdin attached, with the VAR=value pairs of the db_exec_env array
function db_container_run () {
  if [[ "$db_transport" == "kubectl" ]]
  then
    kubectl -n confluent exec -i "$db_container" -- env "${db_exec_env[@]}" "$@"
  else
    local pair env_flags=()
    for pair in "${db_exec_env[@]}"
    do
      env_flags+=(-e "$pair")
    done
    docker exec -i "${env_flags[@]}" "$db_container" "$@"
  fi
}

# value of an environment variable of the database container (first one set among the names given)
function db_container_env () {
  local var value
  if [[ -z "$db_container_env_cache" ]]
  then
    if [[ "$db_transport" == "kubectl" ]]
    then
      db_container_env_cache=$(kubectl -n confluent get pod "$db_container" -o jsonpath='{range .spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' 2>/dev/null)
    else
      db_container_env_cache=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$db_container" 2>/dev/null)
    fi
  fi
  for var in "$@"
  do
    value=$(printf '%s\n' "$db_container_env_cache" | grep -m1 "^${var}=" | cut -d= -f2-)
    if [[ -n "$value" ]]
    then
      echo "$value"
      return 0
    fi
  done
  return 0
}

# true when $1 exists (and is executable) in the database container
function db_container_has () {
  local db_exec_env=()
  db_container_run sh -c "command -v $1 || test -x $1" < /dev/null > /dev/null 2>&1
}

# sets db_user, db_password, db_database and db_client from the flags, or from the container environment
function db_resolve_connection () {
  local user="$1" password="$2" database="$3"
  db_container_env_cache=""
  case "$db_engine" in
    oracle)
      db_user="${user:-sys}"
      db_database="${database:-$(db_container_env ORACLE_SID)}"
      db_database="${db_database:-ORCLCDB}"
      if [[ -z "$password" && -z "$user" ]]
      then
        password=$(db_container_env ORACLE_PWD ORACLE_PASSWORD)
      elif [[ -z "$password" && "${user^^}" == "$(db_container_env APP_USER | tr '[:lower:]' '[:upper:]')" ]]
      then
        password=$(db_container_env APP_USER_PASSWORD)
      fi
      db_password="$password"
      db_client="sqlplus"
    ;;
    postgres)
      db_user="${user:-$(db_container_env POSTGRES_USER)}"
      db_user="${db_user:-postgres}"
      db_password="${password:-$(db_container_env POSTGRES_PASSWORD)}"
      db_database="${database:-$(db_container_env POSTGRES_DB)}"
      db_database="${db_database:-$db_user}"
      db_client="psql"
    ;;
    mysql|mariadb)
      db_user="${user:-root}"
      if [[ -z "$password" ]]
      then
        if [[ "$db_user" == "root" ]]
        then
          password=$(db_container_env MYSQL_ROOT_PASSWORD MARIADB_ROOT_PASSWORD)
        elif [[ "$db_user" == "$(db_container_env MYSQL_USER MARIADB_USER)" ]]
        then
          password=$(db_container_env MYSQL_PASSWORD MARIADB_PASSWORD)
        fi
      fi
      db_password="$password"
      db_database="${database:-$(db_container_env MYSQL_DATABASE MARIADB_DATABASE)}"
      # mariadb 11 images have no mysql binary any more
      if db_container_has mariadb
      then
        db_client="mariadb"
      else
        db_client="mysql"
      fi
    ;;
    sqlserver)
      db_user="${user:-sa}"
      db_password="${password:-$(db_container_env MSSQL_SA_PASSWORD SA_PASSWORD)}"
      db_database="${database:-master}"
      db_client="/opt/mssql-tools18/bin/sqlcmd"
      if ! db_container_has "$db_client"
      then
        db_client="/opt/mssql-tools/bin/sqlcmd"
      fi
    ;;
    db2)
      db_user="${user:-db2inst1}"
      db_password="${password:-$(db_container_env DB2INST1_PASSWORD)}"
      if [[ -z "$database" && "$(db_container_env SAMPLEDB)" == "true" ]]
      then
        database="sample"
      fi
      db_database="${database:-$(db_container_env DBNAME)}"
      db_database="${db_database:-sample}"
      db_client="db2"
    ;;
    mongodb)
      db_user="${user:-$(db_container_env MONGO_INITDB_ROOT_USERNAME)}"
      db_password="${password:-$(db_container_env MONGO_INITDB_ROOT_PASSWORD)}"
      db_database="${database:-test}"
      # images before mongo 6 only have the legacy mongo shell
      if db_container_has mongosh
      then
        db_client="mongosh"
      else
        db_client="mongo"
      fi
      # MONGO_INITDB_ROOT_* only create the user when the image entrypoint runs: an example that starts mongod itself
      # (--replSet) has the variables but no user and no authentication, connect without credentials then
      if [[ -z "$user" && -n "$db_user" ]]
      then
        local db_exec_env=()
        if db_container_run "$db_client" --quiet -u "$db_user" -p "$db_password" --authenticationDatabase admin --eval "1" < /dev/null 2>&1 | grep -q -i "Authentication failed"
        then
          db_user=""
          db_password=""
        fi
      fi
    ;;
  esac
}

# regex of the error lines printed by the client of the engine
function db_error_regex () {
  case "$db_engine" in
    oracle) echo '^(ORA|SP2|PLS)-[0-9]+' ;;
    postgres) echo '(^|: )(ERROR|FATAL):  ' ;;
    mysql|mariadb) echo '^ERROR [0-9]+' ;;
    sqlserver) echo '^(Msg [0-9]+, Level (1[1-9]|2[0-9])|Sqlcmd: Error)' ;;
    db2) echo '^SQL[0-9]+N' ;;
    mongodb) echo '(Mongo[A-Za-z]*Error|SyntaxError|ReferenceError|TypeError|Uncaught[: ])' ;;
  esac
}

# regex of the error that means "this table does not exist" (wait-for-rows counts it as empty)
function db_missing_table_regex () {
  case "$db_engine" in
    oracle) echo 'ORA-00942' ;;
    postgres) echo 'relation .* does not exist' ;;
    mysql|mariadb) echo 'ERROR 1146' ;;
    sqlserver) echo 'Msg 208,' ;;
    db2) echo 'SQL0204N' ;;
    mongodb) echo 'ns does not exist' ;;
  esac
}

# runs the statements read on stdin with the client of the engine
#   $1 mode: script (statements, output for humans) or scalar (one query, prints the bare value)
#   $2 stop: "stop" to stop at the first failing statement, anything else to run them all
#   $3 verbose
# prints the output of the client (stdout and stderr) and returns its exit code
function db_exec () {
  local mode="$1" stop="$2" verbose="$3" input
  input=$(cat)
  db_exec_env=()
  local client_cmd=() prolog="" epilog="" shown

  case "$db_engine" in
    oracle)
      local connect_as=""
      if [[ "${db_user,,}" == "sys" ]]
      then
        connect_as=" AS SYSDBA"
      fi
      # the CONNECT line keeps the password out of the process list. DEFINE OFF: a & in the statements must not
      # prompt for a substitution variable (it would read the next statements as its value)
      prolog="WHENEVER SQLERROR EXIT FAILURE
WHENEVER OSERROR EXIT FAILURE
CONNECT ${db_user}/\"${db_password}\"@//localhost:1521/${db_database}${connect_as}
SET DEFINE OFF"
      if [[ "$mode" == "scalar" ]]
      then
        prolog="$prolog
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF ECHO OFF TRIMOUT ON TAB OFF"
        input="${input%;}
;"
      else
        prolog="$prolog
SET LINESIZE 250 PAGESIZE 1000 TRIMOUT ON TAB OFF FEEDBACK ON SQLBLANKLINES ON"
      fi
      if [[ "$stop" != "stop" ]]
      then
        prolog="$prolog
WHENEVER SQLERROR CONTINUE"
      fi
      epilog="EXIT"
      client_cmd=(sqlplus -S -L /nolog)
    ;;
    postgres)
      db_exec_env+=("PGPASSWORD=$db_password")
      client_cmd=(psql -X -U "$db_user" -d "$db_database")
      if [[ "$mode" == "scalar" ]]
      then
        client_cmd+=(-q -t -A)
      fi
      if [[ "$stop" == "stop" ]]
      then
        client_cmd+=(-v ON_ERROR_STOP=1)
      fi
    ;;
    mysql|mariadb)
      db_exec_env+=("MYSQL_PWD=$db_password")
      client_cmd=("$db_client" "--user=$db_user")
      if [[ -n "$db_database" ]]
      then
        client_cmd+=("--database=$db_database")
      fi
      if [[ "$mode" == "scalar" ]]
      then
        client_cmd+=(--skip-column-names --batch)
      else
        client_cmd+=(--table)
      fi
      if [[ "$stop" != "stop" ]]
      then
        client_cmd+=(--force)
      fi
    ;;
    sqlserver)
      db_exec_env+=("SQLCMDPASSWORD=$db_password")
      client_cmd=("$db_client" -U "$db_user" -d "$db_database")
      if [[ "$db_client" == *mssql-tools18* ]]
      then
        # tools 18 encrypt by default and refuse the self-signed certificate of the container
        client_cmd+=(-C -No)
      fi
      if [[ "$mode" == "scalar" ]]
      then
        client_cmd+=(-h -1 -W)
        input="SET NOCOUNT ON;
${input}"
      fi
      if [[ "$stop" == "stop" ]]
      then
        client_cmd+=(-b)
      fi
      # the last batch runs even without a final GO
      epilog="GO"
    ;;
    db2)
      # the db2 clp needs the profile of the instance owner (su -), and the connection of one db2 call is kept by
      # the next ones of the same shell: both run from a script owned by db2inst1. -s stops at the first failing
      # statement. db2 exits with 1 (no row) or 2 (warning) on success, 4 and 8 on errors
      local script_options="-tv"
      [[ "$stop" == "stop" ]] && script_options="-tvs"
      [[ "$mode" == "scalar" ]] && script_options="-tx"
      # the clp only ends a statement at a ; at the end of a line: one statement per line (outside quotes)
      input=$(printf '%s\n' "${input%;};" | awk '{
        out = ""; q = 0; n = length($0)
        for (i = 1; i <= n; i++) {
          c = substr($0, i, 1); out = out c
          if (c == "\047") q = !q
          if (c == ";" && !q && substr($0, i + 1) ~ /[^[:space:]]/) { print out; out = ""; while (substr($0, i + 1, 1) ~ /[[:space:]]/) i++ }
        }
        print out
      }')
      db_container_run sh -c 'cat > /tmp/playground-db.sql && chmod 644 /tmp/playground-db.sql' <<< "$input" || return 1
      # the script holds the password: it deletes itself first (sh keeps reading it)
      db_container_run sh -c 'cat > /tmp/playground-db-run.sh && chown db2inst1 /tmp/playground-db-run.sh && chmod 700 /tmp/playground-db-run.sh' << EOF || return 1
rm -f /tmp/playground-db-run.sh
db2 connect to $db_database user $db_user using '$db_password' > /tmp/playground-db-connect.log || { cat /tmp/playground-db-connect.log; rm -f /tmp/playground-db-connect.log; exit 8; }
db2 $script_options -f /tmp/playground-db.sql
rc=\$?
db2 terminate > /dev/null
rm -f /tmp/playground-db-connect.log
[ \$rc -ge 4 ] && exit \$rc
exit 0
EOF
      client_cmd=(su - db2inst1 -c "sh /tmp/playground-db-run.sh")
      input=""
    ;;
    mongodb)
      client_cmd=("$db_client" --quiet)
      if [[ -n "$db_user" ]]
      then
        client_cmd+=(-u "$db_user" -p "$db_password" --authenticationDatabase admin)
      fi
      client_cmd+=("$db_database")
      if [[ "$mode" == "scalar" ]]
      then
        client_cmd+=(--eval "$input")
        input=""
      fi
    ;;
  esac

  if [[ "$db_transport" == "kubectl" ]]
  then
    shown="kubectl -n confluent exec -i $db_container -- env ${db_exec_env[*]} ${client_cmd[*]}"
  else
    shown="docker exec -i${db_exec_env[*]:+ -e }${db_exec_env[*]} $db_container ${client_cmd[*]}"
  fi
  if [[ -n "$verbose" ]]
  then
    if [[ -n "$db_password" ]]
    then
      shown="${shown//"$db_password"/*****}"
    fi
    log_verbose_command "$shown"
  fi

  local rc=0
  {
    [[ -n "$prolog" ]] && printf '%s\n' "$prolog"
    [[ -n "$input" ]] && printf '%s\n' "$input"
    [[ -n "$epilog" ]] && printf '%s\n' "$epilog"
  } | db_container_run "${client_cmd[@]}" 2>&1 | db_filter_output
  rc=${PIPESTATUS[1]}
  return $rc
}

# mongosh reads the commands on stdin like a terminal (so that "use <db>" works) and prints its prompt
# (test>, rs0 [direct: primary] inventory>) before each result: remove it
function db_filter_output () {
  if [[ "$db_engine" == "mongodb" ]]
  then
    sed -E -e ':a' -e 's/^([[:alnum:]_.-]+ )?(\[[^]]*\] )?[[:alnum:]_.-]+> //' -e 'ta' | grep -v '^$' || true
  else
    cat
  fi
}
