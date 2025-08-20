log "⚙️ Generate and open oracle cdc xstream connector diagnostics"
tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

cd $tmp_dir
if [ ! -f orclcdc_diag.sql ]
then
    wget -q https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/_downloads/6d672a473a3153a88f9c67de5e0b558f/orclcdc_diag.sql
fi
docker cp orclcdc_diag.sql oracle:/orclcdc_diag.sql > /dev/null 2>&1
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA
     @/orclcdc_diag.sql C##CFLTADMIN C##CFLTUSER XOUT ''
END;
/
EOF
playground container exec --container oracle --command "mv /home/oracle/orclcdc_diag_*.html /home/oracle/orclcdc_diag.html"
docker cp oracle:/home/oracle/orclcdc_diag.html /tmp/ > /dev/null 2>&1
if [ -f /tmp/orclcdc_diag.html ]
then
    log "⚙️ oracle cdc xstream connector diagnostics report is available at /tmp/orclcdc_diag.html"
    if [[ $(type -f open 2>&1) =~ "not found" ]]
    then
        :
    else
        open "/tmp/orclcdc_diag.html"
    fi
else
    logwarn "❌ oracle cdc xstream connector diagnostics report is not available"
fi