log "Monitoring session information about XStream Out components"

docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
    CONNECT sys/Admin123 AS SYSDBA
    SELECT
    action "XStream Component",
    sid, SERIAL#,
    process "OS Process ID",
    SUBSTR(program,INSTR(program,'(')+1,4) "Component Name"
    FROM V\$SESSION
    WHERE module ='XStream';
EOF

log "View the status of each capture process"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
    CONNECT sys/Admin123 AS SYSDBA
    SELECT
    state,
    total_messages_captured,
    total_messages_enqueued
    FROM V\$XSTREAM_CAPTURE;
EOF

log "View the SCN values of each capture process"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
    CONNECT sys/Admin123 AS SYSDBA
    SELECT
    start_scn,captured_scn,
    last_enqueued_scn,required_checkpoint_scn
    FROM ALL_CAPTURE;
EOF

log "View the latencies of each capture process"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
    CONNECT sys/Admin123 AS SYSDBA
    SELECT
    (capture_time - capture_message_create_time) * 86400 "Capture Latency Seconds",
    (enqueue_time - enqueue_message_create_time) * 86400 "Enqueue Latency Seconds"
    FROM V\$XSTREAM_CAPTURE;
EOF


log "View redo log files required by each capture process"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
    CONNECT sys/Admin123 AS SYSDBA
    SELECT
    r.consumer_name "Capture Process Name",
    r.source_database "Source Database",
    r.sequence# "Sequence Number",
    r.name "Archived Redo Log File Name"
    FROM DBA_REGISTERED_ARCHIVED_LOG r,
    ALL_CAPTURE c
    WHERE r.consumer_name = c.capture_name AND
    r.next_scn >= c.required_checkpoint_scn;
EOF

log 'Important Views'
log 'V$XSTREAM_CAPTURE - displays information about each capture process that sends LCRs to an XStream outbound server (https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-XSTREAM_CAPTURE.html)'
log 'ALL_CAPTURE - displays information about the capture processes that enqueue the captured changes into queues accessible to the current user (https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/ALL_CAPTURE.html).'

log "View general information about outbound server"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
    CONNECT sys/Admin123 AS SYSDBA
    SELECT
    server_name "Outbound Server Name",
    capture_name "Capture Process Name",
    connect_user, capture_user,
    queue_owner, queue_name
    FROM ALL_XSTREAM_OUTBOUND;
EOF

log "View information on outbound server current transaction"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
    CONNECT sys/Admin123 AS SYSDBA
    SELECT
    xidusn ||'.'|| xidslt ||'.'|| xidsqn "Transaction ID",
    commitscn, commit_position,
    last_sent_position,
    message_sequence
    FROM V\$XSTREAM_OUTBOUND_SERVER;
EOF

log "View processed low position for an outbound server"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
    CONNECT sys/Admin123 AS SYSDBA
    SELECT
    processed_low_position,
    TO_CHAR(processed_low_time,'HH24:MI:SS MM/DD/YY') processed_low_time
    FROM ALL_XSTREAM_OUTBOUND_PROGRESS;
EOF

log 'Important Views'
log 'V$XSTREAM_OUTBOUND_SERVER - displays statistics about an outbound server (https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-XSTREAM_OUTBOUND_SERVER.html)'
log 'ALL_XSTREAM_OUTBOUND - displays information about the XStream outbound servers (https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/ALL_XSTREAM_OUTBOUND.html)'
log 'ALL_XSTREAM_OUTBOUND_PROGRESS - displays information about the progress made by the XStream outbound servers (https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/ALL_XSTREAM_OUTBOUND_PROGRESS.html)'

log "View capture parameter settings"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
    CONNECT sys/Admin123 AS SYSDBA
    SELECT
    c.capture_name,
    parameter, value,
    set_by_user
    FROM ALL_CAPTURE_PARAMETERS c,
    ALL_XSTREAM_OUTBOUND o
    WHERE c.capture_name = o.capture_name
    ORDER BY parameter;
EOF

log "View apply (outbound server) parameter settings"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
    CONNECT sys/Admin123 AS SYSDBA
    SELECT
    c.capture_name,
    parameter, value,
    set_by_user
    FROM ALL_CAPTURE_PARAMETERS c,
    ALL_XSTREAM_OUTBOUND o
    WHERE c.capture_name = o.capture_name 
    ORDER BY parameter;
EOF

log "View the rules used by XStream components"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
    CONNECT sys/Admin123 AS SYSDBA
    SELECT
    streams_name "XStream Component Name",
    streams_type "XStream Component Type",
    rule_name,
    rule_set_type,
    streams_rule_type,
    schema_name,
    object_name,
    rule_type
    FROM ALL_XSTREAM_RULES;
EOF