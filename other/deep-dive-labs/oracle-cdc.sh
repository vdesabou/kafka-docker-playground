#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-oracle-cdc
# it runs the Oracle XStream example itself (Oracle image from the playground S3 bucket): plaintext CI job only
lab_require_plaintext

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
topic="cflt.C__CFLTUSER.CUSTOMERS"

# runs SQL*Plus as SYSDBA in the oracle container, the statements on stdin
function lab_sysdba () {
    playground container exec --container oracle --command "bash -c \"ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus -s /nolog\""
}

# number of records of the topic of the CUSTOMERS table (offsets: latest - earliest)
function lab_count_records () {
    lab_run playground topic get-number-records --topic "$topic"
    LAB_COUNT=$(grep -E '^[0-9]+$' <<< "$LAB_OUTPUT" | tail -1)
}

log "Step 1: the samples, no database needed"
lab_run playground analyze oracle-xstream-report --sample synthetic_failures --output-dir "$out/samples"
lab_expect_exit 0
lab_expect_contains "🔴 Overall health: CRITICAL 🔴 4 critical 🟠 4 high 🟡 1 medium ⚪ 2 info"
lab_expect_contains "❌ ARCHIVELOG mode NOARCHIVELOG"
lab_expect_contains "🔴 CRITICAL Capture CAP\$_XOUT_1 is ABORTED: ORA-01291: missing logfile"
lab_expect_contains "🟠 HIGH Capture CAP\$_XOUT_1 is PAUSED FOR FLOW CONTROL: the outbound server / connector does not consume fast enough"
lab_expect_contains "👉 ALTER SYSTEM SET streams_pool_size=96M SCOPE=BOTH;"
lab_expect_contains "G. Database prerequisite missing (archivelog, supplemental logging) (2 finding(s))"
lab_expect_contains "✅ HTML report saved: $out/samples/orclcdc_diag_synthetic_failures-xstream-report.html"
lab_run playground analyze oracle-xstream-report --sample missing_archived_log -p "no records processed since 9:10 this morning" --output-dir "$out/samples"
lab_expect_exit 0
lab_expect_contains "🎯 Problem: no records processed since 9:10 this morning"
lab_expect_contains "understood: symptoms=no data dates=none recognized"
lab_expect_contains "• capture CAP\$_XOUT_1: 0 messages captured, 61 enqueued since its startup at 2026-10-14 09:16:14"
lab_expect_contains "already registered and complete: the capture cannot read it (deleted, or not readable from the capture instance) and captures nothing"
lab_expect_contains "I. Capture stuck waiting for redo (archived log missing or unreadable) (1 finding(s))"
lab_run playground analyze oracle-xstream-report -s healthy -s detached --output-dir "$out/samples"
lab_expect_exit 0
lab_expect_contains "📈 Between reports"
lab_expect_contains "orclcdc_diag_healthy.html → orclcdc_diag_detached.html (3m27s)"
lab_expect_contains "capture CAP\$_XOUT_1 🔄 restarted: captured SCN 1,220,736 → 1,183,121 (Δ -37,615)"
lab_expect_contains "outbound XOUT: status ATTACHED → DETACHED"
lab_expect_contains "🟠 HIGH Outbound server XOUT is DETACHED: no connector task is attached"
lab_run bash -c "${DIR}/../../scripts/cli/playground analyze oracle-xstream-report --sample synthetic_failures --json 2>/dev/null | jq -c '[.health, .counts.CRITICAL, (.findings[0] | keys)]'"
lab_expect_exit 0
lab_expect_contains '["CRITICAL",4,["action","evidence","message","pattern","section","severity"]]'
lab_run playground analyze oracle-xstream-report -f /etc/hosts --output-dir "$out/samples"
lab_expect_exit 2
lab_expect_contains "❌ /etc/hosts is not an orclcdc_diag.sql report"
lab_run playground analyze oracle-xstream-report -s healthy -c oracle
lab_expect_exit 1
lab_expect_contains "❌ Provide only one of --file, --container and --sample"

log "Step 2: the XStream example"
# connect 8.4.0 fails to start the XStream connector 1.6.0 (NoClassDefFoundError: org/apache/kafka/common/utils/AppInfoParser,
# https://github.com/vdesabou/kafka-docker-playground/issues/9669): connect runs 8.3.2, like playground run --connect-tag 8.3.2
started=$SECONDS
(cd "${DIR}/../../connect/connect-cdc-xstream-oracle19-source" && CP_CONNECT_TAG=8.3.2 bash cdc-xstream-oracle19.sh)
log "⏱️ the XStream example took $((SECONDS - started)) s"
lab_run playground connector status --connector cdc-xstream-oracle-source
lab_expect_contains "cdc-xstream-oracle-source ✅ RUNNING 0:🟢 RUNNING"
lab_count_records
lab_expect_equals "$LAB_COUNT" "14" "records in $topic after the example"

log "Step 3: the XStream views"
lab_run playground connector oracle-cdc-xstream debug
lab_expect_exit 0
lab_expect_contains "View the status of each capture process"
lab_expect_contains "CAP\$_XOUT_1 - Capture"
lab_expect_contains "XOUT - Apply Reader"
lab_expect_contains "View redo log files required by each capture process"
lab_expect_contains "C##CFLTUSER"
lab_expect_contains "View the rules used by XStream components"

log "Step 4: the diagnostics report of the running example"
lab_run playground connector oracle-cdc-xstream generate-report
lab_expect_exit 0
lab_expect_contains "⚙️ oracle cdc xstream connector diagnostics report is available at /tmp/orclcdc_diag.html"
lab_run playground analyze oracle-xstream-report -c oracle --output-dir "$out/live"
lab_expect_exit 0
lab_expect_contains "⚙️ Generating the diagnostics report in container oracle"
lab_expect_contains "✅ report saved in $out/live/orclcdc_diag_"
lab_expect_contains "🟡 Overall health: AT RISK 🟡 1 medium"
lab_expect_contains "✅ ARCHIVELOG mode ARCHIVELOG"
lab_expect_contains "✅ Database-level ALL column supplemental logging YES"
lab_expect_contains "CAP\$_XOUT_1: status=ENABLED"
lab_expect_contains "XOUT: status=ATTACHED"
lab_expect_contains "rules of CAP\$_XOUT_1: tables: C##CFLTUSER.CUSTOMERS (DDL captured)"
lab_expect_contains "🟡 MEDIUM streams_pool_size is not set explicitly"
lab_expect_contains "A. Undersized streams pool / SGA (spills, memory pressure) (1 finding(s))"
report_running=$(ls "$out"/live/orclcdc_diag_*.html | tail -1)

log "Step 5: RUNNING, but the capture process is stopped"
lab_run lab_sysdba << 'EOF'
CONNECT sys/Admin123 AS SYSDBA
DECLARE
     capture VARCHAR2(128);
BEGIN
     SELECT capture_name INTO capture FROM dba_xstream_outbound WHERE server_name = 'XOUT';
     DBMS_CAPTURE_ADM.STOP_CAPTURE(capture);
END;
/
SELECT capture_name, status FROM dba_capture;
EOF
lab_expect_contains "PL/SQL procedure successfully completed."
lab_expect_contains "DISABLED"
playground container exec --container oracle --command "sqlplus -s c\\#\\#cfltuser/password@//localhost:1521/ORCLCDB" << 'EOF'
insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Max', 'Brod', 'mbrod@confluent.io', 'Male', 'gold', 'Inserted while the capture is stopped');
commit;
exit;
EOF
sleep 30
lab_run playground connector status --connector cdc-xstream-oracle-source
lab_expect_contains "cdc-xstream-oracle-source ✅ RUNNING 0:🟢 RUNNING"
lab_count_records
lab_expect_equals "$LAB_COUNT" "14" "records in $topic while the capture is stopped"
lab_run playground analyze oracle-xstream-report -c oracle --output-dir "$out/live" -p "no new record for the last minute"
lab_expect_exit 0
lab_expect_contains "🔴 Overall health: CRITICAL 🔴 1 critical 🟡 1 medium"
lab_expect_contains "🎯 Problem: no new record for the last minute"
lab_expect_contains "• capture CAP\$_XOUT_1: status=DISABLED state=None"
lab_expect_contains "• outbound server XOUT: status=ATTACHED"
lab_expect_contains "🔴 CRITICAL Capture CAP\$_XOUT_1 is DISABLED"
lab_expect_contains "👉 Fix the error, then EXEC DBMS_CAPTURE_ADM.START_CAPTURE('CAP\$_XOUT_1');"
lab_expect_contains "H. XStream component disabled or aborted (1 finding(s))"
lab_run lab_sysdba << 'EOF'
CONNECT sys/Admin123 AS SYSDBA
DECLARE
     capture VARCHAR2(128);
BEGIN
     SELECT capture_name INTO capture FROM dba_xstream_outbound WHERE server_name = 'XOUT';
     DBMS_CAPTURE_ADM.START_CAPTURE(capture);
END;
/
EOF
lab_expect_contains "PL/SQL procedure successfully completed."
lab_run playground topic wait-for-records --topic "$topic" --min-expected-messages 15 --max-wait 180
lab_expect_exit 0
lab_expect_contains "✅ topic $topic contains 15 records (expected at least 15)"

log "Step 6: pause, then stop the connector"
lab_run playground connector pause --connector cdc-xstream-oracle-source
lab_expect_contains "PAUSED"
sleep 10
lab_run playground analyze oracle-xstream-report -c oracle --output-dir "$out/live"
lab_expect_exit 0
lab_expect_contains "XOUT: status=ATTACHED" "a paused connector stays attached"
lab_run playground connector stop --connector cdc-xstream-oracle-source
lab_expect_contains "has been stopped successfully"
sleep 10
lab_run playground analyze oracle-xstream-report -c oracle --output-dir "$out/live"
lab_expect_exit 0
lab_expect_contains "XOUT: status=DETACHED"
lab_expect_contains "🟠 HIGH Outbound server XOUT is DETACHED: no connector task is attached"
# 1 finding, or 2 when the apply reader still reports a latency (INFO "consequence of the DETACHED outbound server")
lab_expect_contains "D. Outbound server detached (connector not attached) ("
lab_expect_contains "🟠 Overall health: DEGRADED 🟠 1 high 🟡 1 medium"
report_stopped=$(ls "$out"/live/orclcdc_diag_*.html | tail -1)
lab_run playground analyze oracle-xstream-report -f "$report_running" -f "$report_stopped" --output-dir "$out/live"
lab_expect_exit 0
lab_expect_contains "📈 Between reports"
lab_expect_contains "capture CAP\$_XOUT_1 🔄 restarted"
lab_expect_contains "outbound XOUT: status ATTACHED → DETACHED LCRs sent 14 → -"

log "✅ all the outputs of the page are as expected"
