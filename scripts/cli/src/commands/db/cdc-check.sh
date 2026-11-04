container="${args[--container]}"
engine="${args[--engine]}"
user="${args[--user]}"
password="${args[--password]}"
database="${args[--database]}"
connector_user="${args[--connector-user]}"
table="${args[--table]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

db_resolve_container "$container" "$engine" || exit 1
db_resolve_connection "$user" "$password" "$database"

if [[ "$db_engine" == "db2" ]]
then
    logerror "❌ db cdc-check does not support Db2 (no Confluent CDC connector reads Db2 logs): oracle, postgres, mysql, mariadb, sqlserver, mongodb"
    exit 1
fi

# one check: db_check <ok|fail|warn|info> "<check>" "<value>" ["<fix>"]
check_status=()
check_name=()
check_value=()
check_fix=()
function db_check () {
    check_status+=("$1")
    check_name+=("$2")
    check_value+=("$3")
    check_fix+=("${4:-}")
}

# runs the statements on stdin, quiet (no headers), every statement even after a failing one: prints the key=value lines
function db_kv_query () {
    db_exec scalar continue "$verbose" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -E '^[a-z_0-9]+=' || true
}

# value of the first key=value line of $kv for $1
function kv () {
    printf '%s\n' "$kv" | grep -m1 "^$1=" | cut -d= -f2-
}

# every value of $1 in $kv, one per line
function kv_all () {
    printf '%s\n' "$kv" | grep "^$1=" | cut -d= -f2-
}

if [[ -z "$json" ]]
then
    log "🔍 Checking the CDC prerequisites of $db_container $db_kind ($db_engine${connector_user:+, connector user $connector_user}${table:+, table $table})"
fi

case "$db_engine" in
    oracle)
        owner=""
        table_name=""
        if [[ -n "$table" ]]
        then
            owner=$(tr '[:lower:]' '[:upper:]' <<< "${table%%.*}")
            table_name=$(tr '[:lower:]' '[:upper:]' <<< "${table#*.}")
            if [[ "$owner" == "$table_name" ]]
            then
                logerror "❌ --table must be <owner>.<table> for oracle, for example C##MYUSER.CUSTOMERS"
                exit 1
            fi
        fi
        cu=$(tr '[:lower:]' '[:upper:]' <<< "$connector_user")
        kv=$(db_kv_query << EOF
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 4000 TRIMOUT ON VERIFY OFF
SELECT 'version=' || version FROM v\$instance;
SELECT 'cdb=' || cdb FROM v\$database;
SELECT 'log_mode=' || log_mode FROM v\$database;
SELECT 'supplemental_log_data_min=' || supplemental_log_data_min FROM v\$database;
SELECT 'supplemental_log_data_all=' || supplemental_log_data_all FROM v\$database;
SELECT 'force_logging=' || force_logging FROM v\$database;
SELECT 'enable_goldengate_replication=' || value FROM v\$parameter WHERE name = 'enable_goldengate_replication';
SELECT 'streams_pool_size=' || value FROM v\$parameter WHERE name = 'streams_pool_size';
SELECT 'archived_logs_24h=' || COUNT(*) FROM v\$archived_log WHERE first_time > SYSDATE - 1;
SELECT 'pdb=' || name || ' ' || open_mode FROM v\$pdbs WHERE name <> 'PDB\$SEED';
SELECT 'outbound=' || o.server_name || '|' || NVL(o.connect_user, '-') || '|' || NVL(o.capture_name, '-') || '|' || NVL(c.status, '-') || '|' || REPLACE(NVL(c.error_message, ''), CHR(10), ' ') FROM dba_xstream_outbound o LEFT JOIN dba_capture c ON c.capture_name = o.capture_name;
SELECT 'table_log=' || log_group_type FROM cdb_log_groups WHERE owner = '$owner' AND table_name = '$table_name';
SELECT 'table_log=' || log_group_type FROM dba_log_groups WHERE owner = '$owner' AND table_name = '$table_name';
SELECT 'table_exists=' || COUNT(*) FROM cdb_tables WHERE owner = '$owner' AND table_name = '$table_name';
SELECT 'user=' || username || ' ' || common FROM dba_users WHERE username = '$cu';
SELECT 'priv=' || privilege FROM dba_sys_privs WHERE grantee = '$cu' OR grantee IN (SELECT granted_role FROM dba_role_privs CONNECT BY PRIOR granted_role = grantee START WITH grantee = '$cu');
SELECT 'objpriv=' || privilege || ' ' || table_name FROM dba_tab_privs WHERE grantee = '$cu' OR grantee IN (SELECT granted_role FROM dba_role_privs CONNECT BY PRIOR granted_role = grantee START WITH grantee = '$cu');
SELECT 'xstream_admin=' || username FROM dba_xstream_administrator WHERE username = '$cu';
EOF
)
        if [[ -z "$(kv log_mode)" ]]
        then
            logerror "❌ could not query the database as $db_user (run with --verbose to see the command)"
            exit 1
        fi
        db_check info "Oracle version" "$(kv version) ($( [[ "$(kv cdb)" == "YES" ]] && echo "CDB, PDBs: $(kv_all pdb | tr '\n' ',' | sed 's/,$//;s/,/, /g')" || echo "non-CDB"))"

        if [[ "$(kv log_mode)" == "ARCHIVELOG" ]]
        then
            db_check ok "ARCHIVELOG mode" "ARCHIVELOG"
        else
            db_check fail "ARCHIVELOG mode" "$(kv log_mode)" "as SYSDBA, local connection: SHUTDOWN IMMEDIATE; STARTUP MOUNT; ALTER DATABASE ARCHIVELOG; ALTER DATABASE OPEN;"
        fi
        db_check info "archived logs of the last 24 hours" "$(kv archived_logs_24h)"

        if [[ "$(kv supplemental_log_data_min)" =~ ^(YES|IMPLICIT)$ ]]
        then
            db_check ok "minimal supplemental logging" "$(kv supplemental_log_data_min)"
        else
            db_check fail "minimal supplemental logging" "$(kv supplemental_log_data_min)" "ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;"
        fi

        if [[ "$(kv supplemental_log_data_all)" == "YES" ]]
        then
            db_check ok "all columns supplemental logging" "YES (database level: every table)"
        elif [[ -n "$table" ]]
        then
            if [[ "$(kv table_exists)" == "0" ]]
            then
                db_check fail "table $owner.$table_name" "not found" "check the owner and the name, they are case sensitive when created quoted"
            elif kv_all table_log | grep -q "ALL COLUMN LOGGING"
            then
                db_check ok "all columns supplemental logging of $owner.$table_name" "ALL COLUMN LOGGING"
            else
                db_check fail "all columns supplemental logging of $owner.$table_name" "$(kv_all table_log | tr '\n' ',' | sed 's/,$//;s/^$/none/')" "ALTER TABLE $owner.$table_name ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS; (in its PDB), or ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;"
            fi
        else
            db_check warn "all columns supplemental logging" "NO at database level" "needed on each captured table: pass --table <owner>.<table> to check one, ALTER TABLE <t> ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS; or ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;"
        fi

        outbound=$(kv_all outbound)
        if [[ -n "$outbound" ]]
        then
            if [[ "$(kv enable_goldengate_replication)" == "TRUE" ]]
            then
                db_check ok "enable_goldengate_replication (XStream)" "TRUE"
            else
                db_check fail "enable_goldengate_replication (XStream)" "$(kv enable_goldengate_replication)" "ALTER SYSTEM SET enable_goldengate_replication=TRUE SCOPE=BOTH;"
            fi
            while IFS='|' read -r server connect_user capture status error
            do
                if [[ "$status" == "ENABLED" ]]
                then
                    db_check ok "XStream outbound server $server" "capture $capture ENABLED, connect user $connect_user"
                else
                    db_check fail "XStream outbound server $server" "capture $capture $status${error:+: $error}" "EXEC DBMS_CAPTURE_ADM.START_CAPTURE('$capture'); after fixing the error ('playground analyze oracle-xstream-report -c $db_container' for the details)"
                fi
            done <<< "$outbound"
            db_check info "streams_pool_size (XStream)" "$(kv streams_pool_size) (0: sized automatically in the SGA)"
        else
            db_check info "XStream" "no outbound server (enable_goldengate_replication=$(kv enable_goldengate_replication)): LogMiner connector, or XStream not set up yet"
        fi

        if [[ -n "$connector_user" ]]
        then
            user_line=$(kv user)
            if [[ -z "$user_line" ]]
            then
                db_check fail "connector user $cu" "does not exist" "CREATE USER $cu IDENTIFIED BY <password>$( [[ "$(kv cdb)" == "YES" ]] && echo " CONTAINER=ALL");"
            else
                if [[ "$(kv cdb)" == "YES" && "${user_line##* }" != "YES" ]]
                then
                    db_check warn "connector user $cu" "local user of a PDB" "a connector reading the CDB needs a common user (C##...)"
                else
                    db_check ok "connector user $cu" "exists$( [[ "$(kv cdb)" == "YES" ]] && echo ", common user")"
                fi
                privs=$(kv_all priv | sort -u)
                if grep -qx "CREATE SESSION" <<< "$privs"
                then
                    db_check ok "CREATE SESSION of $cu" "granted"
                else
                    db_check fail "CREATE SESSION of $cu" "missing" "GRANT CREATE SESSION TO $cu$( [[ "$(kv cdb)" == "YES" ]] && echo " CONTAINER=ALL");"
                fi
                if [[ -n "$(kv xstream_admin)" ]]
                then
                    db_check info "XStream administrator" "$cu is an XStream administrator (DBMS_XSTREAM_AUTH)"
                elif [[ -z "$outbound" ]]
                then
                    # LogMiner: the grants the connector cannot work without, directly or through roles, as a system
                    # privilege or the object grant of the docs (the other views it reads are listed there)
                    objprivs=$(kv_all objpriv | sort -u)
                    container_all=$( [[ "$(kv cdb)" == "YES" ]] && echo " CONTAINER=ALL")
                    if grep -qx "LOGMINING" <<< "$privs"
                    then
                        db_check ok "LOGMINING of $cu (LogMiner)" "granted"
                    else
                        db_check warn "LOGMINING of $cu (LogMiner)" "not found" "GRANT LOGMINING TO $cu$container_all;"
                    fi
                    if grep -qx "EXECUTE DBMS_LOGMNR" <<< "$objprivs" || grep -qx "EXECUTE ANY PROCEDURE" <<< "$privs"
                    then
                        db_check ok "EXECUTE on DBMS_LOGMNR of $cu (LogMiner)" "granted"
                    else
                        db_check warn "EXECUTE on DBMS_LOGMNR of $cu (LogMiner)" "not found" "GRANT EXECUTE ON SYS.DBMS_LOGMNR TO $cu$container_all;"
                    fi
                    if grep -qx 'SELECT V_$LOGMNR_CONTENTS' <<< "$objprivs" || grep -qx "SELECT ANY DICTIONARY" <<< "$privs"
                    then
                        db_check ok "SELECT on V\$LOGMNR_CONTENTS of $cu (LogMiner)" "granted"
                    else
                        db_check warn "SELECT on V\$LOGMNR_CONTENTS of $cu (LogMiner)" "not found" "GRANT SELECT ON V_\$LOGMNR_CONTENTS TO $cu$container_all; (the docs of the connector list the other views)"
                    fi
                fi
            fi
        fi
    ;;

    postgres)
        cu="$connector_user"
        kv=$(db_kv_query << EOF
SELECT 'version=' || current_setting('server_version');
SELECT 'wal_level=' || current_setting('wal_level');
SELECT 'max_replication_slots=' || current_setting('max_replication_slots');
SELECT 'max_wal_senders=' || current_setting('max_wal_senders');
SELECT 'slots_used=' || count(*) FROM pg_replication_slots;
SELECT 'slot=' || slot_name || '|' || coalesce(plugin, '-') || '|' || active::int || '|' || coalesce(wal_status, '-') || '|' || coalesce(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)::bigint, 0) FROM pg_replication_slots;
SELECT 'publication=' || p.pubname || '|' || p.puballtables::int || '|' || (SELECT count(*) FROM pg_publication_tables t WHERE t.pubname = p.pubname) FROM pg_publication p;
SELECT 'no_identity=' || n.nspname || '.' || c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind IN ('r', 'p') AND c.relreplident = 'd' AND NOT EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = c.oid AND i.indisprimary) AND EXISTS (SELECT 1 FROM pg_publication_tables t WHERE t.schemaname = n.nspname AND t.tablename = c.relname);
SELECT 'user=' || rolname || '|' || rolreplication::int || '|' || rolsuper::int || '|' || rolcanlogin::int FROM pg_roles WHERE rolname = '$cu';
SELECT 'table_identity=' || c.relreplident::text || '|' || EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = c.oid AND i.indisprimary)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname || '.' || c.relname = '$( [[ "$table" == *.* ]] && echo "$table" || echo "public.$table")';
EOF
)
        if [[ -z "$(kv wal_level)" ]]
        then
            logerror "❌ could not query the database as $db_user (run with --verbose to see the command)"
            exit 1
        fi
        db_check info "PostgreSQL version" "$(kv version)"
        if [[ "$(kv wal_level)" == "logical" ]]
        then
            db_check ok "wal_level" "logical"
        else
            db_check fail "wal_level" "$(kv wal_level)" "ALTER SYSTEM SET wal_level = logical; then restart PostgreSQL (docker compose: command: postgres -c wal_level=logical)"
        fi
        if [ "$(kv max_wal_senders)" -gt 0 ] 2>/dev/null
        then
            db_check ok "max_wal_senders" "$(kv max_wal_senders)"
        else
            db_check fail "max_wal_senders" "$(kv max_wal_senders)" "ALTER SYSTEM SET max_wal_senders = 10; then restart PostgreSQL"
        fi
        used=$(kv slots_used)
        max=$(kv max_replication_slots)
        if [ "${max:-0}" -eq 0 ] 2>/dev/null
        then
            db_check fail "replication slots" "max_replication_slots=0" "ALTER SYSTEM SET max_replication_slots = 10; then restart PostgreSQL"
        elif [ "${used:-0}" -ge "$max" ]
        then
            db_check fail "replication slots" "$used used of $max: a new connector cannot create its slot" "drop the slots of deleted connectors: SELECT pg_drop_replication_slot('<slot>'); or raise max_replication_slots"
        else
            db_check ok "replication slots" "$used used of $max"
        fi
        while IFS='|' read -r slot plugin active wal_status lag
        do
            [[ -z "$slot" ]] && continue
            lag_mb=$(( ${lag:-0} / 1024 / 1024 ))
            if [[ "$wal_status" == "lost" ]]
            then
                db_check fail "slot $slot ($plugin)" "invalidated (wal_status lost)" "the WAL it needed is gone: drop it and let the connector snapshot again"
            elif [[ "$active" != "1" && $lag_mb -ge 1024 ]]
            then
                db_check warn "slot $slot ($plugin)" "inactive, retains ${lag_mb} MB of WAL" "a stopped or deleted connector keeps WAL on disk: SELECT pg_drop_replication_slot('$slot'); if it is not used anymore"
            else
                db_check info "slot $slot ($plugin)" "$( [[ "$active" == "1" ]] && echo active || echo inactive), ${lag_mb} MB behind, wal_status $wal_status"
            fi
        done <<< "$(kv_all slot)"
        publications=$(kv_all publication)
        if [[ -n "$publications" ]]
        then
            while IFS='|' read -r pub all count
            do
                db_check info "publication $pub" "$( [[ "$all" == "1" ]] && echo "all tables" || echo "$count table(s)")"
            done <<< "$publications"
        else
            db_check info "publications" "none (pgoutput: the connector creates one, publication.autocreate.mode)"
        fi
        no_identity=$(kv_all no_identity)
        if [[ -n "$no_identity" ]]
        then
            while read -r t
            do
                db_check fail "replica identity of $t" "no primary key, REPLICA IDENTITY DEFAULT" "UPDATE and DELETE fail on a published table without replica identity: ALTER TABLE $t REPLICA IDENTITY FULL; (or add a primary key)"
            done <<< "$no_identity"
        fi
        pg_table="$table"
        [[ -n "$table" && "$table" != *.* ]] && pg_table="public.$table"
        if [[ -n "$table" ]] && ! grep -qx "$pg_table" <<< "$no_identity"
        then
            table="$pg_table"
            identity=$(kv table_identity)
            if [[ -z "$identity" ]]
            then
                db_check fail "table $table" "not found" "pass <schema>.<table> (public by default)"
            else
                case "${identity%%|*}" in
                    f) db_check ok "replica identity of $table" "FULL (before values of every column)" ;;
                    d) if [[ "${identity##*|}" == "1" ]]
                       then
                           db_check ok "replica identity of $table" "DEFAULT, primary key (before values of the key only)"
                       else
                           db_check fail "replica identity of $table" "DEFAULT without primary key" "ALTER TABLE $table REPLICA IDENTITY FULL;"
                       fi ;;
                    i) db_check ok "replica identity of $table" "USING INDEX" ;;
                    n) db_check fail "replica identity of $table" "NOTHING" "ALTER TABLE $table REPLICA IDENTITY FULL;" ;;
                esac
            fi
        fi
        if [[ -n "$cu" ]]
        then
            user_line=$(kv user)
            if [[ -z "$user_line" ]]
            then
                db_check fail "connector user $cu" "does not exist" "CREATE ROLE $cu WITH LOGIN REPLICATION PASSWORD '<password>';"
            else
                IFS='|' read -r _ replication super login <<< "$user_line"
                if [[ "$replication" == "1" || "$super" == "1" ]]
                then
                    db_check ok "REPLICATION of $cu" "$( [[ "$super" == "1" ]] && echo superuser || echo granted)"
                else
                    db_check fail "REPLICATION of $cu" "missing" "ALTER ROLE $cu WITH REPLICATION;"
                fi
                [[ "$login" != "1" ]] && db_check fail "LOGIN of $cu" "missing" "ALTER ROLE $cu WITH LOGIN;"
            fi
        fi
    ;;

    mysql|mariadb)
        cu="$connector_user"
        kv=$(db_kv_query << EOF
SELECT CONCAT('version=', @@version);
SELECT CONCAT('log_bin=', @@log_bin);
SELECT CONCAT('binlog_format=', @@binlog_format);
SELECT CONCAT('binlog_row_image=', @@binlog_row_image);
SELECT CONCAT('server_id=', @@server_id);
SELECT CONCAT('gtid_mode=', @@gtid_mode);
SELECT CONCAT('binlog_expire_logs_seconds=', @@binlog_expire_logs_seconds);
SELECT CONCAT('expire_logs_days=', @@expire_logs_days);
SELECT CONCAT('user=', User, '@', Host, '|', Select_priv, '|', Reload_priv, '|', Repl_slave_priv, '|', Repl_client_priv) FROM mysql.user WHERE User = '$cu';
EOF
)
        if [[ -z "$(kv log_bin)" ]]
        then
            logerror "❌ could not query the database as $db_user (run with --verbose to see the command)"
            exit 1
        fi
        db_check info "version" "$(kv version)"
        if [[ "$(kv log_bin)" == "1" ]]
        then
            db_check ok "binary log (log_bin)" "ON"
        else
            db_check fail "binary log (log_bin)" "OFF" "start the server with --log-bin (and --server-id), on by default since MySQL 8.0"
        fi
        if [[ "$(kv binlog_format)" == "ROW" ]]
        then
            db_check ok "binlog_format" "ROW"
        else
            db_check fail "binlog_format" "$(kv binlog_format)" "SET GLOBAL binlog_format = 'ROW'; and binlog_format=ROW in the configuration (only the sessions opened after it use it)"
        fi
        if [[ "$(kv binlog_row_image)" == "FULL" ]]
        then
            db_check ok "binlog_row_image" "FULL"
        else
            db_check fail "binlog_row_image" "$(kv binlog_row_image)" "SET GLOBAL binlog_row_image = 'FULL'; and binlog_row_image=FULL in the configuration"
        fi
        if [ "$(kv server_id)" -gt 0 ] 2>/dev/null
        then
            db_check ok "server_id" "$(kv server_id)"
        else
            db_check fail "server_id" "$(kv server_id)" "set server-id to a value other than 0 in the configuration"
        fi
        [[ -n "$(kv gtid_mode)" ]] && db_check info "gtid_mode" "$(kv gtid_mode)"
        retention=$(kv binlog_expire_logs_seconds)
        if [[ -n "$retention" && "$retention" != "0" ]]
        then
            if [ "$retention" -lt 86400 ]
            then
                db_check warn "binlog retention" "${retention}s" "a connector stopped longer than this loses its position (Could not find first log file name): SET GLOBAL binlog_expire_logs_seconds = 604800;"
            else
                db_check info "binlog retention" "$(( retention / 86400 )) day(s) (binlog_expire_logs_seconds=$retention)"
            fi
        elif [[ -n "$(kv expire_logs_days)" ]]
        then
            db_check info "binlog retention" "expire_logs_days=$(kv expire_logs_days) (0: kept until purged)"
        fi
        if [[ -n "$cu" ]]
        then
            users=$(kv_all user)
            if [[ -z "$users" ]]
            then
                db_check fail "connector user $cu" "does not exist" "CREATE USER '$cu'@'%' IDENTIFIED BY '<password>';"
            else
                while IFS='|' read -r account select reload repl_slave repl_client
                do
                    missing=""
                    [[ "$select" != "Y" ]] && missing="$missing SELECT"
                    [[ "$reload" != "Y" ]] && missing="$missing RELOAD"
                    [[ "$repl_slave" != "Y" ]] && missing="$missing REPLICATION_SLAVE"
                    [[ "$repl_client" != "Y" ]] && missing="$missing REPLICATION_CLIENT"
                    if [[ -z "$missing" ]]
                    then
                        db_check ok "privileges of $account" "SELECT, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT"
                    else
                        db_check fail "privileges of $account" "missing:$(tr '_' ' ' <<< "$missing")" "GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO '${account%@*}'@'${account#*@}';"
                    fi
                done <<< "$users"
            fi
        fi
    ;;

    sqlserver)
        kv=$(db_kv_query << 'EOF'
SELECT 'version=' + CAST(SERVERPROPERTY('ProductVersion') AS varchar(50)) + ' ' + CAST(SERVERPROPERTY('Edition') AS varchar(100));
SELECT 'agent=' + status_desc FROM sys.dm_server_services WHERE servicename LIKE 'SQL Server Agent%';
SELECT 'agent_xps=' + CAST(value_in_use AS varchar(10)) FROM sys.configurations WHERE name = 'Agent XPs';
SELECT 'database=' + name + '|' + CAST(is_cdc_enabled AS varchar(1)) FROM sys.databases WHERE database_id > 4;
EOF
)
        if [[ -z "$(kv version)" ]]
        then
            logerror "❌ could not query the database as $db_user (run with --verbose to see the command)"
            exit 1
        fi
        db_check info "SQL Server version" "$(kv version)"
        agent=$(kv agent)
        if [[ "$agent" == "Running" || ( -z "$agent" && "$(kv agent_xps)" == "1" ) ]]
        then
            db_check ok "SQL Server Agent" "${agent:-running (Agent XPs enabled)}"
        else
            db_check fail "SQL Server Agent" "${agent:-not running (Agent XPs disabled)}" "the capture job of CDC runs in SQL Server Agent: start it (docker: MSSQL_AGENT_ENABLED=true)"
        fi
        cdc_databases=""
        while IFS='|' read -r name enabled
        do
            [[ -z "$name" ]] && continue
            if [[ "$enabled" == "1" ]]
            then
                cdc_databases="$cdc_databases $name"
            elif [[ -n "$database" && "$database" == "$name" ]]
            then
                db_check fail "CDC of database $name" "not enabled" "USE $name; EXEC sys.sp_cdc_enable_db;"
            fi
        done <<< "$(kv_all database)"
        if [[ -z "$cdc_databases" && -z "$database" ]]
        then
            db_check fail "CDC" "no database has CDC enabled" "USE <database>; EXEC sys.sp_cdc_enable_db;"
        fi
        for name in $cdc_databases
        do
            [[ -n "$database" && "$database" != "master" && "$database" != "$name" ]] && continue
            db_kv=$(db_kv_query << EOF
SELECT 'table=' + s.name + '.' + t.name + '|' + ct.capture_instance FROM [$name].cdc.change_tables ct JOIN [$name].sys.tables t ON t.object_id = ct.source_object_id JOIN [$name].sys.schemas s ON s.schema_id = t.schema_id;
SELECT 'job=' + job_type FROM msdb.dbo.cdc_jobs WHERE database_id = DB_ID('$name');
EOF
)
            tables=$(printf '%s\n' "$db_kv" | grep '^table=' | cut -d= -f2- | cut -d'|' -f1)
            if grep -q '^job=capture' <<< "$db_kv"
            then
                db_check ok "CDC of database $name" "enabled, capture job present, $(grep -c . <<< "$tables") table(s): $(tr '\n' ' ' <<< "$tables" | sed 's/ $//;s/ /, /g')"
            else
                db_check fail "CDC of database $name" "enabled, but no capture job" "USE $name; EXEC sys.sp_cdc_add_job @job_type = N'capture';"
            fi
            if [[ -z "$tables" ]]
            then
                db_check warn "CDC tables of $name" "none" "USE $name; EXEC sys.sp_cdc_enable_table @source_schema = N'dbo', @source_name = N'<table>', @role_name = NULL;"
            fi
            if [[ -n "$table" ]]
            then
                wanted="$table"
                [[ "$wanted" != *.* ]] && wanted="dbo.$wanted"
                if grep -qix "$wanted" <<< "$tables"
                then
                    db_check ok "CDC of table $wanted" "enabled in $name"
                else
                    db_check fail "CDC of table $wanted" "not enabled in $name" "USE $name; EXEC sys.sp_cdc_enable_table @source_schema = N'${wanted%%.*}', @source_name = N'${wanted#*.}', @role_name = NULL;"
                fi
            fi
        done
    ;;

    mongodb)
        kv=$(db_kv_query << 'EOF'
const out = [];
out.push('version=' + db.version());
try { const s = rs.status(); out.push('replset=' + s.set + ' ' + s.members.find(m => m.self).stateStr); } catch (e) { out.push('replset_error=' + String(e.message).replace(/\n/g, ' ')); }
try { const r = db.getReplicationInfo(); out.push('oplog_hours=' + r.timeDiffHours); out.push('oplog_size_mb=' + Math.round(r.logSizeMB)); out.push('oplog_used_mb=' + Math.round(r.usedMB)); } catch (e) { }
print(out.join('\n'));
EOF
)
        if [[ -z "$(kv version)" ]]
        then
            logerror "❌ could not query the database${db_user:+ as $db_user} (run with --verbose to see the command)"
            exit 1
        fi
        db_check info "MongoDB version" "$(kv version)"
        if [[ -n "$(kv replset)" ]]
        then
            db_check ok "replica set" "$(kv replset)"
            hours=$(kv oplog_hours)
            size=$(kv oplog_size_mb)
            used=$(kv oplog_used_mb)
            if [[ -n "$hours" && -n "$size" ]]
            then
                # the window only means something once the oplog is full: before, it is the age of the oldest entry
                if [ "${used:-0}" -lt $(( size * 9 / 10 )) ]
                then
                    db_check info "oplog window" "not full yet: ${used} MB used of ${size} MB, oldest entry ${hours} hour(s) ago"
                elif awk -v h="$hours" 'BEGIN { exit !(h < 1) }'
                then
                    db_check warn "oplog window" "${hours} hour(s) (${size} MB, full)" "a connector stopped longer than the window cannot resume (resume token not found): raise the oplog size (replSetResizeOplog)"
                else
                    db_check info "oplog window" "${hours} hour(s) (${size} MB, full)"
                fi
            fi
        else
            db_check fail "replica set" "$(kv replset_error)" "change streams need a replica set: start mongod with --replSet <name>, then rs.initiate()"
        fi
    ;;
esac

nb_ok=0
nb_fail=0
nb_warn=0
for s in "${check_status[@]}"
do
    case "$s" in
        ok) nb_ok=$((nb_ok + 1)) ;;
        fail) nb_fail=$((nb_fail + 1)) ;;
        warn) nb_warn=$((nb_warn + 1)) ;;
    esac
done

if [[ -n "$json" ]]
then
    {
        for i in "${!check_status[@]}"
        do
            jq -n --arg status "${check_status[$i]}" --arg check "${check_name[$i]}" --arg value "${check_value[$i]}" --arg fix "${check_fix[$i]}" \
                '{status: $status, check: $check, value: $value} + (if $fix == "" then {} else {fix: $fix} end)'
        done
    } | jq -s --arg engine "$db_engine" --arg container "$db_container" --argjson ok "$nb_ok" --argjson fail "$nb_fail" --argjson warn "$nb_warn" \
        '{engine: $engine, container: $container, verdict: (if $fail > 0 then "fail" elif $warn > 0 then "warn" else "ok" end), ok: $ok, fail: $fail, warn: $warn, checks: .}'
else
    width=0
    for n in "${check_name[@]}"
    do
        [ ${#n} -gt $width ] && width=${#n}
    done
    for i in "${!check_status[@]}"
    do
        case "${check_status[$i]}" in
            ok) icon="✅" ;;
            fail) icon="❌" ;;
            warn) icon="⚠️ " ;;
            *) icon="ℹ️ " ;;
        esac
        printf '   %s %-*s  %s\n' "$icon" "$width" "${check_name[$i]}" "${check_value[$i]}"
        if [[ -n "${check_fix[$i]}" ]]
        then
            printf '      👉 %s\n' "${check_fix[$i]}"
        fi
    done
    if [ $nb_fail -gt 0 ]
    then
        logerror "❌ $nb_fail CDC prerequisite(s) missing, ✅ $nb_ok ok, ⚠️ $nb_warn warning(s)"
    elif [ $nb_warn -gt 0 ]
    then
        logwarn "⚠️ $nb_warn warning(s), ✅ $nb_ok ok"
    else
        log "✅ the $nb_ok CDC prerequisites are met"
    fi
fi

if [ $nb_fail -gt 0 ]
then
    exit 1
fi
