# 🍪 Deep dive: Oracle CDC (LogMiner and XStream)

Confluent has two connectors that stream the changes of an Oracle database: the **Oracle CDC Source** connector, which
runs LogMiner itself, and the **Oracle XStream CDC Source** connector, which attaches to an XStream outbound server that
Oracle runs. Both exist self-managed and fully managed, and both are frequent support topics: "the connector is
`RUNNING` but nothing comes in", "it lags", "it fails after a restart with a missing log". This page is about where the
state of each connector lives, why the answer is so often in the database rather than in Connect, and the playground
tools that read the database side for you. Takes about 15 minutes to read, the lab about 10 minutes in CI.

> [!TIP]
> 🎬 Short on time? The video session [🅾️ Oracle XStream CDC lags or is idle](/sessions?id=🅾️-oracle-xstream-cdc-lags-or-is-idle)
> shows `analyze oracle-xstream-report` in 5 minutes. This page goes further: the mental model of both connectors, the
> examples, what each command really runs, a hands-on lab on a live XStream setup and recipes for support repros.

| You want | Command |
| --- | --- |
| the playground examples for Oracle | `playground find-example "oracle cdc"`, `playground find-example "oracle xstream"` |
| a working XStream setup (Oracle 19c, outbound server `XOUT`, connector, 14 records) | `playground run -f connect/connect-cdc-xstream-oracle19-source/cdc-xstream-oracle19.sh` |
| a working LogMiner setup | `playground run -f connect/connect-cdc-oracle19-source/cdc-oracle19-cdb-table.sh` (or `-pdb-table`, TLS, mTLS variants) |
| the state of the XStream components, raw | `playground connector oracle-cdc-xstream debug` |
| the diagnostics report support asks for (`orclcdc_diag_<date>.html`) | `playground connector oracle-cdc-xstream generate-report` |
| that report, digested into findings | `playground analyze oracle-xstream-report -c oracle` (live) / `-f <report.html>` (a customer's) |
| what moved between two reports | `playground analyze oracle-xstream-report -f day1.html -f day2.html` |
| the findings that explain a symptom first | `… -p "no records processed since 11th of OCT"` |
| what the analyzer reports, without a database | `playground analyze oracle-xstream-report --sample synthetic_failures` |

---

## 1. Mental model (the 3 things to remember)

1. **Two connectors, two places where the redo is read.**

   | | Oracle CDC Source (LogMiner) | Oracle XStream CDC Source |
   | --- | --- | --- |
   | Class (self-managed) | `io.confluent.connect.oracle.cdc.OracleCdcSourceConnector` | `io.confluent.connect.oracle.xstream.cdc.OracleXStreamSourceConnector` |
   | Fully managed type | `OracleCdcSource` | `OracleXStreamSource` |
   | Who mines the redo | the connector: task 0 opens LogMiner sessions over JDBC (`DBMS_LOGMNR`) | Oracle: a **capture process** (`CAP$_XOUT_1` in the example) mines the redo, stages the changes (LCRs) in a queue (`Q$_XOUT_2`), and an **outbound server** (`XOUT`) sends them to the client attached to it |
   | Tasks | task 0 writes every raw redo event to the **redo log topic** (`redo.log.topic.name`), the other tasks read it back (`redo.log.consumer.*`) and write the table topics: once the snapshots are done, the connector needs 1 task for the redo log + 1 per table | **one** task (`tasks.max` > 1 fails: `Only a single connector task may be started`), attached to the outbound server as its `connect_user` through the Oracle client (`xstreams.jar` + Instant Client libraries, OCI) |
   | Where the position lives | Connect offsets (an SCN) and the redo log topic | the connector offsets, passed to the outbound server when the task attaches (`outbound.server.attach.position.mode`, default `connector_managed`); the outbound server also tracks its processed low position (`ALL_XSTREAM_OUTBOUND_PROGRESS`) |
   | Database objects | a user with LogMiner grants, nothing else | XStream admin and connect users, the capture process, the queue, the outbound server and its rules (`DBMS_XSTREAM_ADM.CREATE_OUTBOUND`) |
   | Readiness script (run by the examples) | `oracle-readiness.sql` | `orclcdc_readiness.sql` |
   | Diagnostics | the connector logs and metrics | the same, plus `orclcdc_diag.sql` (`generate-report`) |

   The XStream connector is built on Debezium's Oracle connector (its source says so in the file headers): its config
   keys (`table.include.list`, `topic.prefix`, `snapshot.mode`, `schema.history.internal.*`) and record format
   (`before` / `after` / `op`) are Debezium's. The LogMiner connector has its own keys (`table.inclusion.regex`,
   `start.from`, `table.topic.name.template`) and a flat record format with `op_type` and `scn` fields.

2. **With XStream, half of the state is in the database, and Connect doesn't see it.** The connector status only says
   that the task is alive. Whether changes flow depends on the capture process (`ENABLED` /
   `DISABLED` / `ABORTED`, and its state: `CAPTURING CHANGES`, `WAITING FOR REDO`, `PAUSED FOR FLOW CONTROL`…), on the
   redo it can still read, and on the outbound server (`ATTACHED` / `DETACHED`). A capture stopped by a DBA, aborted on
   `ORA-01291: missing logfile`, or waiting for an archived log that was deleted gives exactly the most common ticket:
   **`RUNNING`, no error in the Connect logs, no new record**. The lab reproduces it: the capture is stopped, the
   connector stays `RUNNING`, the topic doesn't move, and only the diagnostics report says why. So for XStream, the
   first thing to ask is the `orclcdc_diag_<date>.html` report, ideally two taken some minutes apart.

3. **The prerequisites are database settings, the same for both connectors.** `ARCHIVELOG` mode (the redo must
   survive a log switch until it is mined), supplemental logging (minimal, plus all columns: the examples run
   `ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS`), archived logs kept until the connector (LogMiner) or the
   capture process (XStream) no longer needs them, and a user with the right grants. XStream adds
   `enable_goldengate_replication=TRUE`, an admin user granted with `DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE`, the
   outbound server, and memory in the streams pool (`streams_pool_size`, `MAX_SGA_SIZE` of capture and apply). After
   a restart, an XStream capture mines the redo again from its **applied** SCN (the position the connector
   acknowledged), so the archived logs from there must still exist: a "missing log" after a restart is a retention
   problem, not a connector bug.

---

## 2. The examples

| Example | Scripts | In CI |
| --- | --- | --- |
| [`connect/connect-cdc-xstream-oracle19-source`](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-cdc-xstream-oracle19-source) | `cdc-xstream-oracle19.sh` (plaintext), `-ssl`, `-ssl-wallet`, `-mtls-wallet`, `-blocking-snapshot` (signal table), `-blocking-snapshot-kafka-signal` | yes |
| [`connect/connect-cdc-oracle19-source`](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-cdc-oracle19-source) | `cdc-oracle19-cdb-table.sh`, `-pdb-table`, `-pdb-mview`, and `-ssl`, `-mtls`, `-mtls-db-auth` for CDB and PDB | yes |
| [`connect/connect-cdc-oracle21-source`](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-cdc-oracle21-source) | the same 9 variants on Oracle 21c | yes |
| [`ccloud/fm-cdc-xstream-oracle19-source`](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-cdc-xstream-oracle19-source) | `fully-managed-cdc-xstream-oracle19.sh`, `-blocking-snapshot`, `-ssl-wallet` | yes |
| [`ccloud/fm-cdc-oracle19-source`](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/fm-cdc-oracle19-source) | `fully-managed-cdc-oracle19-cdb-table.sh` | yes |
| `connect/connect-debezium-oracle19-source` | `debezium-oracle19.sh` (the community Debezium connector) | no |
| JDBC and JMS: `connect/connect-jdbc-oracle19-source` / `-sink`, `connect-jdbc-oracle21-*`, `connect-jms-oracle19-*`, `connect-jms-oracle21-*`, `ccloud/fm-jdbc-oracle19-source` / `-sink` | not CDC: JDBC queries the tables, JMS reads Oracle Advanced Queuing (AQ) queues | yes |

What the CDC examples have in common:

- **The Oracle image** is a prebuilt `db-prebuilt-<checksum of the setup script>:19.3.0-ee` image
  (`create_or_get_oracle_image`): taken from the local Docker images, else downloaded from the playground S3 bucket
  (Confluent employees, AWS credentials), else built from `oracle/docker-images` with the database zip you downloaded
  (`LINUX.X64_193000_db_home.zip`, about 10 minutes the first time). The database is ready when its log says
  `DATABASE IS READY TO USE` (the scripts wait up to 600 s for it). Give Docker a big disk (96 GB is known to work).
- **The XStream examples also need the Oracle Instant Client** (`instantclient_19_25_x86.zip` or `_arm64.zip`, from
  S3 or downloaded by hand): `ojdbc8.jar`, `xstreams.jar` and the libraries are copied into the connector plugin
  folder, `LD_LIBRARY_PATH` points to them, and `libaio` / `libnsl` are installed in the `connect` container.
- **The database setup is in the script**, as `sqlplus` heredocs run with `playground container exec -c oracle`:
  copy those blocks to understand or change what the customer has (grants, supplemental logging, a second table in
  the outbound server). XStream: `enable_goldengate_replication`, `ARCHIVELOG`, supplemental logging (all columns),
  tablespaces, `c##cfltadmin` (admin) and `c##cfltuser` (connect user, owner of `CUSTOMERS`), outbound server `XOUT`
  on `C##CFLTUSER.CUSTOMERS`. LogMiner: `ARCHIVELOG` is set by the setup script of the image
  (`ora-setup-scripts-cdb-table/01_user-setup.sh`), then the `C##CDC_PRIVS` role, the `C##MYUSER` user and
  supplemental logging.
- **The connector is created only once the database is set up**, and the XStream examples wait for the 5 records of
  the snapshot (`topic wait-for-records`) before the DML: `RUNNING` doesn't mean the snapshot is done, and changes
  made before it starts end up in the snapshot instead of being streamed.
- **Fully managed**: the database runs locally and an `ngrok` container exposes port 1521 to Confluent Cloud
  (`NGROK_AUTH_TOKEN`). The database-side commands below work the same, since the `oracle` container is local. See the
  [fully managed deep dive](/deep-dive-fully-managed.md) for the connector side.

Gotchas:

- **Each XStream variant starts from a fresh database**: there is no "add a table" command. To capture another table,
  add it to the `CREATE_OUTBOUND` block (`tables(2) := 'C##CFLTUSER.ORDERS'`) and to `table.include.list`.
- **The LogMiner example writes 2 topics**: the table topic `ORCLCDB.C__MYUSER.CUSTOMERS` and the redo log topic
  `redo-log-topic`. `#` is not valid in a topic name, so `C##MYUSER` becomes `C__MYUSER` (XStream: `cflt.C__CFLTUSER.CUSTOMERS`).
- **The LogMiner examples need connector 2.14.9 or later with CP 8.x** (they exit 111 otherwise).

---

## 3. `connector oracle-cdc-xstream`: the database side, live

Both commands are only available when a container named `oracle` runs (filter `oracle_running`), and both connect as
`sys/Admin123 AS SYSDBA` to `ORCLCDB`: the credentials of the playground examples.

**`debug`** runs a fixed list of queries with `sqlplus` in the `oracle` container and prints the raw results, with a
link to the Oracle documentation of the main views:

| Query | View |
| --- | --- |
| XStream sessions (`module = 'XStream'`) | `V$SESSION` |
| capture state, messages captured and enqueued, latencies | `V$XSTREAM_CAPTURE` |
| capture SCNs: start, captured, last enqueued, required checkpoint | `ALL_CAPTURE` |
| archived logs still needed by each capture (`next_scn >= required_checkpoint_scn`) | `DBA_REGISTERED_ARCHIVED_LOG` |
| outbound server, its capture, connect user and queue | `ALL_XSTREAM_OUTBOUND` |
| the transaction the outbound server is sending, its processed low position | `V$XSTREAM_OUTBOUND_SERVER`, `ALL_XSTREAM_OUTBOUND_PROGRESS` |
| capture parameters | `ALL_CAPTURE_PARAMETERS` |
| rules of the XStream components (which tables) | `ALL_XSTREAM_RULES` |

**`generate-report`** downloads `orclcdc_diag.sql` from the connector documentation, copies it into the container,
runs it with `C##CFLTADMIN C##CFLTUSER XOUT` and copies the result to **`/tmp/orclcdc_diag.html`** (overwritten on
each run, opened in the browser in an interactive terminal). This is the report support asks customers for, with the
same script: what you get from the example is directly comparable with theirs.

Gotchas:

- **Hardcoded names**: container `oracle`, `sys/Admin123`, SID `ORCLCDB`, users `C##CFLTADMIN` / `C##CFLTUSER`,
  outbound server `XOUT`. In a repro model with another outbound server name or user, run the script yourself
  (`playground container cp` + `sqlplus … @/orclcdc_diag.sql <admin> <user> <server> ''`), or keep the example's names.
- **`generate-report` needs internet** (it downloads the script each time) and takes some seconds: the script queries
  dozens of views.
- `debug` prints the "apply parameter settings" with the same query as the capture parameters: read the outbound
  server parameters in the report (`Apply: Parameters`) instead.
- The LogMiner connector has no equivalent command: there is no capture process to look at. Its database side is
  the archived logs (`V$ARCHIVED_LOG`) and the LogMiner session the task opens, and its health is in the connector
  logs and metrics (the example sets `io.confluent.connect.oracle.cdc.util.metrics.MetricsReporter` to `DEBUG` and
  `enable.metrics.collection=true`).

---

## 4. `analyze oracle-xstream-report`: the report, digested

The `orclcdc_diag` report is hundreds of tables. `analyze oracle-xstream-report` (Python, standard library only, in
`tools/xstream-analyzer/`) parses it and prints a digest: prerequisites, capture, LogMiner, outbound server, apply
reader, queue and streams pool, findings sorted by severity (each with the report section, the exact values and, when
there is one, the SQL to run), and the matched root-cause patterns. It also writes a self-contained HTML report in
`--output-dir` (default `./xstream-analysis-output`: pass `--output-dir /tmp/…`).

| Input | Where the report comes from |
| --- | --- |
| `-c oracle` (the default when no input is given) | runs `generate-report` on the running example, keeps a timestamped copy `orclcdc_diag_<YYYYMMDD_HHMMSS>.html` in `--output-dir`, then analyzes it |
| `-f <report.html>` (repeatable) | a customer's report, or yours; several reports of the same database are ordered by their generation time and compared (`📈 Between reports`) |
| `--sample <name>` (repeatable) | shipped in `tools/xstream-analyzer/samples`: `healthy`, `large_transaction`, `detached`, `older_script_version`, `synthetic_failures`, `missing_archived_log` |

The patterns:

| Pattern | Meaning | Typical finding |
| --- | --- | --- |
| A | undersized streams pool / SGA | `Oracle estimates 5,000 spills at the current streams pool size (64 MB)` → `ALTER SYSTEM SET streams_pool_size=96M SCOPE=BOTH;` |
| B | large or long running transactions | `Large transaction 10.21.771 open in capture and apply: 150,013 LCRs` |
| C | flow control | `Capture … is PAUSED FOR FLOW CONTROL: the outbound server / connector does not consume fast enough` |
| D | outbound server detached | `Outbound server XOUT is DETACHED: no connector task is attached` |
| E | LogMiner memory pressure | `LogMiner session of … uses 97% of its memory` |
| F | overlapping capture processes | a `GLOBAL` rule, or the same table captured by two captures |
| G | database prerequisite missing | `Database is in NOARCHIVELOG mode`, `Minimal supplemental logging is not enabled` |
| H | component disabled or aborted | `Capture … is ABORTED: ORA-01291: missing logfile`, `Capture … is DISABLED` |
| I | capture stuck waiting for redo | `WAITING FOR REDO … on archived log … already registered and complete: the capture cannot read it` |

Gotchas:

- **Give the symptom with `-p`** ("no records processed since 11th of OCT"): the output then starts with a
  `🎯 Problem` block: the symptoms and dates it understood, the capture position as a date, messages captured, LCRs
  sent, the newest registered log, and the findings that explain it first. Without it, a capture
  `WAITING FOR REDO` looks like an idle database.
- **Latency on an idle database means nothing**: with nothing to capture, latency grows; the analyzer downgrades it
  to INFO when the capture waits for redo and is not stuck.
- **Spills of large or old transactions are by design** (above `TXN_LCR_SPILL_THRESHOLD`, 10,000 LCRs, or
  `TXN_AGE_SPILL_THRESHOLD`, 15 minutes, in the samples): MEDIUM, pattern B. Only spills below those thresholds point
  to memory (pattern A).
- **Exit codes**: `0` analysis done, `2` not an `orclcdc_diag` report (the readiness script output, a wrong
  attachment), `1` usage error such as two inputs at once (`❌ Provide only one of --file, --container and --sample`).
- **`-c` generates the report with the example's names** (see `generate-report` above): any container name other
  than `oracle` only changes the "is it running" check.
- **`--json`** prints `health`, `counts`, `findings` (`severity`, `message`, `section`, `evidence`, `action`,
  `pattern`), `patterns`, `prerequisites`, `summary`, `deltas` (with several reports: `{"reports": […], "deltas": …}`),
  and writes no HTML report.
- The report doesn't contain the connector version, its config, nor anything about Kafka: read them in the connector
  logs (`playground container logs -c connect --errors`) and config. The skill `kdp-xstream-report` (Claude Code)
  combines both into a case write-up.
- A customer report is untrusted data: it is only parsed, nothing in it runs. Open its HTML in a browser only if you
  trust where it comes from; the analyzer's HTML report escapes every value.

---

## 5. Hands-on lab (≈10 min in CI)

The lab runs the XStream example, then reads the database side the way you would on a case: the raw views, the
report, a capture stopped behind a `RUNNING` connector, and an outbound server that detaches. Every output below comes
from a CI run of [`other/deep-dive-labs/oracle-cdc.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/deep-dive-labs/oracle-cdc.sh),
which asserts them. The LogMiner connector is not replayed: there is no playground command dedicated to its database
side, and its examples already run every night in CI (`connect/connect-cdc-oracle19-source`, `-oracle21-source`).

**Step 1: the samples, no database needed**

```bash
playground analyze oracle-xstream-report --sample synthetic_failures --output-dir /tmp/xstream
# 🔴 Overall health: CRITICAL  🔴 4 critical  🟠 4 high  🟡 1 medium  ⚪ 2 info
# ✅ Prerequisites
#    ❌ ARCHIVELOG mode                                  NOARCHIVELOG
#    ❌ Minimal supplemental logging                     NO
# …
# 🔎 Findings
#    🔴 CRITICAL Capture CAP$_XOUT_1 is ABORTED: ORA-01291: missing logfile
#       § Capture Process: Status  [pattern H]
#       👉 Fix the error, then EXEC DBMS_CAPTURE_ADM.START_CAPTURE('CAP$_XOUT_1');
#    🟠 HIGH     Capture CAP$_XOUT_1 is PAUSED FOR FLOW CONTROL: the outbound server / connector does not consume fast enough
#    🟠 HIGH     Oracle estimates 5,000 spills at the current streams pool size (64 MB)
#       👉 ALTER SYSTEM SET streams_pool_size=96M SCOPE=BOTH;
# 🧩 Matched patterns
#    G. Database prerequisite missing (archivelog, supplemental logging) (2 finding(s))
# ✅ HTML report saved: /tmp/xstream/orclcdc_diag_synthetic_failures-xstream-report.html

playground analyze oracle-xstream-report --sample missing_archived_log -p "no records processed since 9:10 this morning" --output-dir /tmp/xstream
# 🎯 Problem: no records processed since 9:10 this morning
#    understood: symptoms=no data  dates=none recognized
#    • capture CAP$_XOUT_1: 0 messages captured, 61 enqueued since its startup at 2026-10-14 09:16:14
#    👉 findings that explain it, most relevant first:
#       🔴 CRITICAL Capture CAP$_XOUT_1 is WAITING FOR REDO since 2026-10-14 09:16:40 on archived log thread 1 sequence 3 (…),
#          already registered and complete: the capture cannot read it (deleted, or not readable from the capture instance) and captures nothing. …
#    I. Capture stuck waiting for redo (archived log missing or unreadable) (1 finding(s))

playground analyze oracle-xstream-report -s healthy -s detached --output-dir /tmp/xstream
# 🟠 HIGH     Outbound server XOUT is DETACHED: no connector task is attached
# 📈 Between reports
#    orclcdc_diag_healthy.html → orclcdc_diag_detached.html (3m27s)
#       capture CAP$_XOUT_1 🔄 restarted: captured SCN 1,220,736 → 1,183,121 (Δ -37,615)
#       outbound XOUT: status ATTACHED → DETACHED  LCRs sent 14 → - (Δ -)

playground analyze oracle-xstream-report --sample synthetic_failures --json | jq -c '[.health, .counts.CRITICAL, (.findings[0] | keys)]'
# ["CRITICAL",4,["action","evidence","message","pattern","section","severity"]]
playground analyze oracle-xstream-report -f /etc/hosts
# ❌ /etc/hosts is not an orclcdc_diag.sql report (…)                                    <- exit 2
playground analyze oracle-xstream-report -s healthy -c oracle
# ❌ Provide only one of --file, --container and --sample                                 <- exit 1
```

**Step 2: the XStream example**

```bash
playground run -f "$PWD/connect/connect-cdc-xstream-oracle19-source/cdc-xstream-oracle19.sh"
# 351 s in CI, 2 min 20 s of them to download and load the 11 GB Oracle image (db-prebuilt-2943665357:19.3.0-ee)
playground connector status --connector cdc-xstream-oracle-source
# cdc-xstream-oracle-source      ✅ RUNNING  0:🟢 RUNNING
playground topic get-number-records --topic cflt.C__CFLTUSER.CUSTOMERS
# 14
```

> [!NOTE]
> With CP 8.4.0, the XStream connector 1.6.0 fails to start (`NoClassDefFoundError: org/apache/kafka/common/utils/AppInfoParser`,
> [#9669](https://github.com/vdesabou/kafka-docker-playground/issues/9669)): the lab runs connect on 8.3.2, like
> `playground run -f … --connect-tag 8.3.2`.

**Step 3: the XStream views**

```bash
playground connector oracle-cdc-xstream debug
# Monitoring session information about XStream Out components
# XOUT - Apply Coordinator … AP01
# CAP$_XOUT_1 - Capture … CP01
# XOUT - Apply Reader … AS01
# View the status of each capture process
# WAITING FOR TRANSACTION
#                   32351                      55        <- TOTAL_MESSAGES_CAPTURED, TOTAL_MESSAGES_ENQUEUED
# View redo log files required by each capture process
# CAP$_XOUT_1 / ORCLCDB / 8 / /opt/oracle/product/19c/dbhome_1/dbs/arch1_8_1108484583.dbf
# CAP$_XOUT_1 / ORCLCDB / 9 / /opt/oracle/product/19c/dbhome_1/dbs/arch1_9_1108484583.dbf
# View general information about outbound server
# XOUT / CAP$_XOUT_1 / C##CFLTUSER / C##CFLTADMIN / C##CFLTADMIN / Q$_XOUT_2
# (condensed here: SQL*Plus prints the wide columns one per line, each block repeating the headers)
```

The raw output is long and wrapped: it answers "is there a capture session, what does it wait for, which archived logs
does it still need". For a verdict, read the report.

**Step 4: the diagnostics report of the running example**

```bash
playground connector oracle-cdc-xstream generate-report
# ⚙️ oracle cdc xstream connector diagnostics report is available at /tmp/orclcdc_diag.html
playground analyze oracle-xstream-report -c oracle --output-dir /tmp/xstream
# ⚙️ Generating the diagnostics report in container oracle
# ✅ report saved in /tmp/xstream/orclcdc_diag_20261028_122319.html
# 🟡 Overall health: AT RISK  🟡 1 medium  ⚪ 2 info
# ✅ Prerequisites
#    ✅ ARCHIVELOG mode                                  ARCHIVELOG
#    ✅ Minimal supplemental logging                     IMPLICIT
#    ✅ Database-level ALL column supplemental logging   YES
# 📸 Capture
#    CAP$_XOUT_1: status=ENABLED state=WAITING FOR TRANSACTION latency=2s SGA=used 6 MB, allocated 31 MB, max INFINITE
#       SCN start=2,164,996 captured=2,202,909 applied=2,164,996 gap to current=76  messages captured=32,361 enqueued=56  redo mined=149.03 MB
# 📤 Outbound server
#    XOUT: status=ATTACHED state=IDLE user=C##CFLTUSER capture=CAP$_XOUT_1
#       transactions sent=5 LCRs sent=14 last sent=2026-10-28 12:22:46 (31s before the report)
#    rules of CAP$_XOUT_1: tables: C##CFLTUSER.CUSTOMERS (DDL captured)
# 🔎 Findings
#    🟡 MEDIUM   streams_pool_size is not set explicitly
```

This is the healthy baseline: 14 LCRs sent for the 14 records of the topic, a capture waiting for the next
transaction, the outbound server attached. The only finding is the streams pool, left to automatic memory management
in the playground image.

**Step 5: `RUNNING`, but the capture process is stopped**

```bash
playground container exec -c oracle --command "bash -c \"ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus -s /nolog\"" << 'EOF'
CONNECT sys/Admin123 AS SYSDBA
DECLARE
     capture VARCHAR2(128);
BEGIN
     SELECT capture_name INTO capture FROM dba_xstream_outbound WHERE server_name = 'XOUT';
     DBMS_CAPTURE_ADM.STOP_CAPTURE(capture);
END;
/
EOF
# PL/SQL procedure successfully completed.          (CAP$_XOUT_1 is now DISABLED)
# … insert one row in CUSTOMERS and commit, wait 30 s
playground connector status --connector cdc-xstream-oracle-source
# cdc-xstream-oracle-source      ✅ RUNNING  0:🟢 RUNNING
playground topic get-number-records --topic cflt.C__CFLTUSER.CUSTOMERS
# 14                                                <- still 14: the new row is not captured
playground analyze oracle-xstream-report -c oracle --output-dir /tmp/xstream -p "no new record for the last minute"
# 🔴 Overall health: CRITICAL  🔴 1 critical  🟡 1 medium  …
# 🎯 Problem: no new record for the last minute
#    understood: symptoms=no data  dates=none recognized
#    • capture CAP$_XOUT_1: status=DISABLED state=None
#    • outbound server XOUT: status=ATTACHED state=WAIT FOR CLIENT LCRs sent=14 last sent=2026-10-28 12:22:46
#    👉 findings that explain it, most relevant first:
#       🔴 CRITICAL Capture CAP$_XOUT_1 is DISABLED
# 🔎 Findings
#    🔴 CRITICAL Capture CAP$_XOUT_1 is DISABLED
#       § Capture Process: Status  [pattern H]
#       👉 Fix the error, then EXEC DBMS_CAPTURE_ADM.START_CAPTURE('CAP$_XOUT_1');
# 🧩 Matched patterns
#    H. XStream component disabled or aborted (1 finding(s))
```

The connector and its task are `RUNNING`, the outbound server is still `ATTACHED`, and nothing comes in: only the
database knows why. Start the capture again (`DBMS_CAPTURE_ADM.START_CAPTURE`) and the row arrives:

```bash
playground topic wait-for-records --topic cflt.C__CFLTUSER.CUSTOMERS --min-expected-messages 15 --max-wait 180
# ✅ topic cflt.C__CFLTUSER.CUSTOMERS contains 15 records (expected at least 15) after 16 seconds
```

**Step 6: pause, then stop the connector**

```bash
playground connector pause --connector cdc-xstream-oracle-source
playground analyze oracle-xstream-report -c oracle --output-dir /tmp/xstream
#    XOUT: status=ATTACHED state=IDLE user=C##CFLTUSER capture=CAP$_XOUT_1      <- a paused task stays attached
playground connector stop --connector cdc-xstream-oracle-source
playground analyze oracle-xstream-report -c oracle --output-dir /tmp/xstream
# 🟠 Overall health: DEGRADED  🟠 1 high  🟡 1 medium  …
#    XOUT: status=DETACHED state=None user=C##CFLTUSER capture=CAP$_XOUT_1
#    🟠 HIGH     Outbound server XOUT is DETACHED: no connector task is attached
#       § Outbound Server: General  [pattern D]
#    D. Outbound server detached (connector not attached) (1 finding(s))   <- 2 when the apply reader still shows a latency
playground analyze oracle-xstream-report -f /tmp/xstream/orclcdc_diag_20261028_122319.html -f /tmp/xstream/orclcdc_diag_20261028_122456.html
# 📈 Between reports
#    orclcdc_diag_20261028_122319.html → orclcdc_diag_20261028_122456.html (97s)
#       capture CAP$_XOUT_1 🔄 restarted: captured SCN 2,202,909 → 2,206,765 (Δ 3,856)
#          messages captured 32,361 → 34,973 (Δ 2,612)  latency 2 → 6 (Δ 4)
#       outbound XOUT: status ATTACHED → DETACHED  LCRs sent 14 → - (Δ -)
```

`pause` keeps the task and its XStream connection: `ATTACHED`. `stop` (and `delete`, see the `detached` sample) shuts
the task down: `DETACHED`. The comparison of the first report of step 4 with the last one also catches the capture
restart of step 5.

```bash
playground stop
```

---

## 6. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "XStream connector `RUNNING`, no new record, no error" | ask for `orclcdc_diag_<date>.html` (two, a few minutes apart), then `analyze oracle-xstream-report -f a.html -f b.html -p "<symptom, since when>"`: look at capture status / state and the captured SCN as a date |
| "the capture aborted with ORA-01291 / ORA-00308" | pattern H / I: the archived log is gone or unreadable; the finding gives the `RMAN> RESTORE ARCHIVELOG FROM SEQUENCE …` to run, and the capture resumes on its own. `--sample missing_archived_log` / `synthetic_failures` show both findings |
| "the outbound server is DETACHED" | pattern D: no task attached (connector stopped, deleted, failed, or network; a **paused** connector stays `ATTACHED`, see step 6). `playground connector status`, `connector diagnose`, then the report again |
| "it lags during the nightly batch" | the report during the batch: flow control (C), spills and streams pool advice (A), large transactions (B). Reproduce with `playground connector benchmark --shape bulk` on the XStream example (see the [benchmark deep dive](/deep-dive-connector-benchmark.md)) |
| "is supplemental logging / ARCHIVELOG set?" | the `✅ Prerequisites` block of the digest (XStream, pattern G), or `SELECT log_mode, supplemental_log_data_min, supplemental_log_data_all FROM v$database;` as SYSDBA in any Oracle example |
| "the customer sent a report, what does it say?" | `analyze oracle-xstream-report -f <file> -p "…" --output-dir /tmp/case` (HTML to share), skill `kdp-xstream-report` for the write-up |
| "the same on a healthy database, to compare" | run `cdc-xstream-oracle19.sh`, then `analyze oracle-xstream-report -c oracle --output-dir /tmp/xstream` |
| "TLS / wallet to the database" | `cdc-xstream-oracle19-ssl.sh`, `-ssl-wallet`, `-mtls-wallet`; LogMiner: `cdc-oracle19-*-ssl.sh`, `-mtls`, `-mtls-db-auth` |
| "blocking snapshot with a signal" | `cdc-xstream-oracle19-blocking-snapshot.sh` (signal table) / `-kafka-signal` |
| "LogMiner connector lags or misses changes" | `cdc-oracle19-cdb-table.sh` (or `-pdb-table`), the connector logs with `playground container logs -c connect --errors`, `playground connector show-lag`, and its keys with `playground connector-plugin config-key --key <k> --connector-class io.confluent.connect.oracle.cdc.OracleCdcSourceConnector` (`redo.log.row.fetch.size`, `start.from`…) |
| "fully managed connector" | `ccloud/fm-cdc-xstream-oracle19-source` / `fm-cdc-oracle19-source`: the database is local, the same report commands work |

In a repro model based on the XStream example, end the script with the report, so that the run log shows the
findings:

```bash
playground analyze oracle-xstream-report -c oracle --output-dir /tmp/repro-xstream -p "<the customer's symptom>"
```

---

## 7. Cheat sheet

```bash
playground run -f connect/connect-cdc-xstream-oracle19-source/cdc-xstream-oracle19.sh      # XStream, outbound server XOUT
playground run -f connect/connect-cdc-oracle19-source/cdc-oracle19-cdb-table.sh             # LogMiner, CDB (or -pdb-table)
playground connector oracle-cdc-xstream debug                                               # raw XStream views
playground connector oracle-cdc-xstream generate-report                                    # /tmp/orclcdc_diag.html
playground analyze oracle-xstream-report [-c oracle | -f <report.html>… | --sample <name>…] [-p "<symptom, since when>"] [--json] [--top 10] [--output-dir <d>]
playground container exec -c oracle --command "bash -c \"ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog\"" << EOF
CONNECT sys/Admin123 AS SYSDBA
…
EOF
```

- LogMiner connector: the connector mines (task 0 → redo log topic → table tasks). XStream: Oracle mines (capture →
  queue → outbound server), one connector task attached to `XOUT`.
- XStream `RUNNING` + no record = look at the database: capture status / state, captured SCN as a date, outbound server
  `ATTACHED` / `DETACHED`.
- Prerequisites: `ARCHIVELOG`, supplemental logging, archived logs kept until mined (from the applied SCN for XStream),
  streams pool for XStream.
- `generate-report` and `-c` use the example's names (`oracle`, `sys/Admin123`, `C##CFLTADMIN`, `C##CFLTUSER`, `XOUT`).
- Sources: [`commands/connector/oracle-cdc-xstream/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/connector/oracle-cdc-xstream),
  [`analyze/oracle-xstream-report.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/analyze/oracle-xstream-report.sh),
  [`tools/xstream-analyzer/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/tools/xstream-analyzer),
  `create_or_get_oracle_image` in [`utils_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/utils_function.sh).

---

**Links**

- 🎬 Video session: [🅾️ Oracle XStream CDC lags or is idle](/sessions?id=🅾️-oracle-xstream-cdc-lags-or-is-idle)
- 🍪 Deep dives: [a connector that doesn't work](/deep-dive-connector-troubleshooting.md),
  [logs](/deep-dive-container-logs.md), [benchmark a connector](/deep-dive-connector-benchmark.md),
  [fully managed connectors](/deep-dive-fully-managed.md), [connector plugins](/deep-dive-connector-plugin.md) (`config-key`, `sourcecode`)
- 📖 Confluent docs: [Oracle XStream CDC Source](https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/overview.html)
  ([diagnostics script](https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/troubleshooting.html#connector-diagnostics-script)),
  [Oracle CDC Source](https://docs.confluent.io/kafka-connectors/oracle-cdc/current/overview.html),
  [Oracle XStream guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/xstrm/)
- 🧠 CLI reference: [playground analyze oracle-xstream-report](/playground%20analyze%20oracle-xstream-report),
  [playground connector oracle-cdc-xstream](/playground%20connector%20oracle-cdc-xstream)
