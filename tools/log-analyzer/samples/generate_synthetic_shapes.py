#!/usr/bin/env python3
"""Writes the synthetic samples of `playground analyze logs` for the input shapes found in customer files (never copied:
every line is written here, with neutral names: orders-cdc, db.example.com, 10.0.0.x):

  connect-workers/        --sample connect_workers
      worker-a/connect.log    a worker that takes over orders-cdc-0, an HDFS sink that rotates with empty offsets
                              and never commits (🔂 livelock, INFO lines only)
      worker-b/connect.log    every line logged twice (two appenders: ⚠️ duplicated lines collapsed), the graceful
                              stop of orders-cdc-0 that fails, and its errors that go on there afterwards (🧟 zombie task)
      thread-dumps/           2 dumps of each worker (2 JVMs in one folder, taken minutes apart): on worker B the
                              binlog keepalive thread waits for a ReentrantLock held by the binlog reader, RUNNABLE in
                              a TLS socket write, in both dumps (🧵 lock stall)
      connectors-status.txt   /connectors?expand=status saved with its shell prompt: the trace of a FAILED task of a
                              worker whose logs are not there becomes a record
  grafana-loki-export.txt --sample loki_export: Grafana Explore "Download as txt" of a Loki query, header, epoch and
                              UTC time before each line, newest first
  connector-cr/           --sample connector_cr: one CFK Connector custom resource next to the log of the worker saved
                              as .txt (read as logs, not as a CFK support bundle)

Run it again after a change (python3 -I tools/log-analyzer/samples/generate_synthetic_shapes.py): the output is the
same on every run.
"""
import calendar
import os
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DAY = "2026-11-10"
RUNTIME = "org.apache.kafka.connect.runtime"


def write(rel, text):
    path = os.path.join(HERE, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


def line(t, level, msg, logger, ctx=""):
    """a log4j line of Connect: [2026-11-10 10:00:00,000] INFO [ctx] msg (logger)"""
    return f"[{DAY} {t}] {level} {('[' + ctx + '] ') if ctx else ''}{msg} ({logger})"


def worker_start(worker, t0):
    w = f"Worker clientId=connect-{worker}, groupId=connect-cluster"
    return [line(f"{t0}:00,000", "INFO", "Kafka version: 8.1.2-ce", "org.apache.kafka.common.utils.AppInfoParser:124"),
            line(f"{t0}:00,001", "INFO", "Kafka commitId: 4f5cd2a0c1b8e3d9", "org.apache.kafka.common.utils.AppInfoParser:125"),
            line(f"{t0}:02,140", "INFO", "Kafka Connect worker initialization took 2140ms", "org.apache.kafka.connect.cli.AbstractConnectCli:144"),
            line(f"{t0}:03,021", "INFO", "Kafka Connect started", f"{RUNTIME}.Connect:57"),
            line(f"{t0}:04,028", "INFO", f"[{w}] Rebalance started", f"{RUNTIME}.distributed.WorkerCoordinator:242")]


def start_task(worker, t, connector, version, cls, task_cls, with_connector=True):
    w = f"Worker clientId=connect-{worker}, groupId=connect-cluster"
    out = []
    if with_connector:
        out += [line(f"{t},010", "INFO", f"[{w}] Starting connector {connector}", f"{RUNTIME}.distributed.DistributedHerder:2347"),
                line(f"{t},020", "INFO", f"Instantiated connector {connector} with version {version} of type class {cls}",
                     f"{RUNTIME}.Worker:322", f"{connector}|worker")]
    out += [line(f"{t},030", "INFO", f"[{w}] Starting task {connector}-0", f"{RUNTIME}.distributed.DistributedHerder:2032"),
            line(f"{t},040", "INFO", f"Instantiated task {connector}-0 with version {version} of type {task_cls}",
                 f"{RUNTIME}.Worker:644", f"{connector}|task-0")]
    return out


# ── connect-workers: 2 workers, their thread dumps, a REST status dump ──

BINLOG = "com.github.shyiko.mysql.binlog.BinaryLogClient"
CDC = ("orders-cdc", "3.1.2.Final", "io.debezium.connector.mysql.MySqlConnector", "io.debezium.connector.mysql.MySqlConnectorTask")


def worker_a():
    out = worker_start("10.0.0.11:8083", "10:00")
    out += start_task("10.0.0.11:8083", "10:00:06", "archive-sink", "2.0.3", "io.confluent.connect.hdfs3.Hdfs3SinkConnector",
                      "io.confluent.connect.hdfs3.Hdfs3SinkTask")
    out.append(line("10:00:08,512", "INFO", "Opening record writer for: hdfs://namenode.example.com:8020/topics/+tmp/events/partition=0/",
                    "io.confluent.connect.hdfs3.TopicPartitionWriter:528", "archive-sink|task-0"))
    rotations = [f"10:{m:02d}:00,{m * 7:03d}" for m in range(2, 41, 2)]
    events = [(t, line(t, "INFO", "Starting commit and rotation for topic partition events-0 with start offsets {} and end offsets {}",
                       "io.confluent.connect.hdfs3.TopicPartitionWriter:615", "archive-sink|task-0")) for t in rotations]
    w = "Worker clientId=connect-10.0.0.11:8083, groupId=connect-cluster"
    events += [("10:30:20,100", line("10:30:20,100", "INFO", f"[{w}] Rebalance started", f"{RUNTIME}.distributed.WorkerCoordinator:242"))]
    events += [(f"10:30:24,{i}", x) for i, x in enumerate(start_task("10.0.0.11:8083", "10:30:24", *CDC, with_connector=False))]
    events += [("10:30:26,300", line("10:30:26,300", "INFO", "Connected to binlog at db.example.com:3306, starting at binlog file 'mysql-bin.000042', pos=81234",
                                     "io.debezium.connector.mysql.MySqlStreamingChangeEventSource:1050", "orders-cdc|task-0"))]
    events += [("10:30:40,000", line("10:30:40,000", "WARN", "Server id 184054 is already used by another binlog client connected to db.example.com:3306, retrying",
                                     BINLOG + ":1020", "orders-cdc|task-0"))]
    out += [x for _, x in sorted(events)]
    return "\n".join(out) + "\n"


def worker_b():
    out = worker_start("10.0.0.12:8083", "10:00")
    out += start_task("10.0.0.12:8083", "10:00:06", *CDC)
    out.append(line("10:00:08,230", "INFO", "Connected to binlog at db.example.com:3306, starting at binlog file 'mysql-bin.000042', pos=4",
                    "io.debezium.connector.mysql.MySqlStreamingChangeEventSource:1050", "orders-cdc|task-0"))
    out.append(line("10:22:10,450", "WARN", "No event received from db.example.com:3306 for 60000 ms, keepalive thread reconnecting",
                    BINLOG + ":1130", "orders-cdc|task-0"))
    w = "Worker clientId=connect-10.0.0.12:8083, groupId=connect-cluster"
    out.append(line("10:30:19,800", "INFO", f"[{w}] Rebalance started", f"{RUNTIME}.distributed.WorkerCoordinator:242"))
    out.append(line("10:30:19,900", "INFO", "Stopping task orders-cdc-0", f"{RUNTIME}.Worker:1036", "orders-cdc|task-0"))
    out.append(line("10:30:24,905", "ERROR", "Graceful stop of task orders-cdc-0 failed.", f"{RUNTIME}.Worker:1393", "orders-cdc|task-0"))
    for m in range(32, 41, 2):
        out.append(line(f"10:{m:02d}:05,{m * 3:03d}", "ERROR", "Failed to reconnect to db.example.com:3306 after the keepalive timeout: Communications link failure",
                        BINLOG + ":1160", "orders-cdc|task-0"))
    # two appenders writing the same file (a console appender redirected to it and a file appender): each line twice
    return "".join(f"{x}\n{x}\n" for x in out)


def td_thread(name, num, nid, state, frames, cpu=100.0, elapsed=1000.0, locks=(), owned=None):
    """one thread of a jstack -l dump: frames are 'pkg.Class.method' strings, locks [(index after frame, line)]"""
    head = {"RUNNABLE": "runnable", "BLOCKED": "waiting for monitor entry"}.get(state, "waiting on condition")
    detail = {"WAITING": " (parking)", "TIMED_WAITING": " (sleeping)", "BLOCKED": " (on object monitor)"}.get(state, "")
    out = [f'"{name}" #{num} prio=5 os_prio=0 cpu={cpu:.2f}ms elapsed={elapsed:.2f}s tid=0x00007f00000{num:05x} '
           f'nid={nid} {head}  [0x00007f0000000000]', f"   java.lang.Thread.State: {state}{detail}"]
    lk = dict(locks)
    for i, f in enumerate(frames):
        out.append(f"\tat {f}(Unknown Source)")
        if i in lk:
            out.append(f"\t- {lk[i]}")
    if owned is not None:
        out += ["", "   Locked ownable synchronizers:"] + ([f"\t- {o}" for o in owned] or ["\t- None"])
    return "\n".join(out) + "\n"


def td_common(base_num, nid0, elapsed, n=12):
    """idle threads of a worker: a pool parked on a condition, a producer network thread in epollWait"""
    cond = ["jdk.internal.misc.Unsafe.park", "java.util.concurrent.locks.LockSupport.park",
            "java.util.concurrent.locks.AbstractQueuedSynchronizer$ConditionObject.await",
            "java.util.concurrent.LinkedBlockingQueue.take", "java.util.concurrent.ThreadPoolExecutor.getTask", "java.lang.Thread.run"]
    out = [td_thread(f"pool-1-thread-{i}", base_num + i, hex(nid0 + i), "WAITING", cond, elapsed=elapsed,
                     locks=[(0, "parking to wait for  <0x00000000bbbb0001> (a java.util.concurrent.locks.AbstractQueuedSynchronizer$ConditionObject)")],
                     owned=[]) for i in range(n)]
    out.append(td_thread("kafka-producer-network-thread | connector-producer-orders-cdc-0", base_num + 50, hex(nid0 + 50), "RUNNABLE",
                         ["sun.nio.ch.EPoll.wait", "sun.nio.ch.EPollSelectorImpl.doSelect", "org.apache.kafka.common.network.Selector.select",
                          "org.apache.kafka.clients.producer.internals.Sender.run", "java.lang.Thread.run"], elapsed=elapsed, owned=[]))
    return out


TD_LOCK = "<0x00000000aaaa0001> (a java.util.concurrent.locks.ReentrantLock$NonfairSync)"
TD_PARK = ["jdk.internal.misc.Unsafe.park", "java.util.concurrent.locks.LockSupport.park",
           "java.util.concurrent.locks.AbstractQueuedSynchronizer.acquire", "java.util.concurrent.locks.ReentrantLock$Sync.lock",
           "java.util.concurrent.locks.ReentrantLock.lock", "sun.security.ssl.SSLSocketImpl.closeNotify",
           "sun.security.ssl.SSLSocketImpl.shutdownOutput", "com.github.shyiko.mysql.binlog.network.protocol.PacketChannel.close",
           "com.github.shyiko.mysql.binlog.BinaryLogClient$5.run", "java.lang.Thread.run"]
TD_WRITE = ["sun.nio.ch.FileDispatcherImpl.write0", "sun.nio.ch.SocketDispatcher.write", "sun.nio.ch.NioSocketImpl.tryWrite",
            "sun.nio.ch.NioSocketImpl.implWrite", "java.net.Socket$SocketOutputStream.write",
            "sun.security.ssl.SSLSocketOutputRecord.flush", "sun.security.ssl.KeyUpdate$KeyUpdateProducer.produce",
            "sun.security.ssl.SSLSocketImpl.readApplicationRecord", "com.github.shyiko.mysql.binlog.io.ByteArrayInputStream.read",
            "com.github.shyiko.mysql.binlog.BinaryLogClient.listen", "java.lang.Thread.run"]


def td_dump(ts, threads):
    return f"{DAY} {ts}\nFull thread dump OpenJDK 64-Bit Server VM (17.0.15+6-LTS mixed mode, sharing):\n\n" + "\n".join(threads) + "\n"


def thread_dumps():
    """worker A: idle; worker B: the keepalive thread waits for the TLS lock of the binlog reader, stuck in a write (the
    task stopped at 10:30:24 still runs there). Thread numbers and OS ids differ: 2 JVMs"""
    out = {}
    for i, ts in enumerate(("10:36:00", "10:37:00")):
        el = 2160.0 + 60 * i
        out[f"worker-a-dump-{i + 1}.txt"] = td_dump(ts, td_common(10, 0x5000, el))
    for i, ts in enumerate(("10:36:30", "10:37:30")):
        el = 2190.0 + 60 * i
        th = td_common(30, 0x1000, el)
        th.append(td_thread("blc-keepalive-db.example.com:3306", 350, "0x2001", "WAITING", TD_PARK, cpu=11.0, elapsed=el,
                            locks=[(0, "parking to wait for  " + TD_LOCK)], owned=[]))
        th.append(td_thread("blc-db.example.com:3306", 371, "0x2002", "RUNNABLE", TD_WRITE, cpu=5000.0, elapsed=el, owned=[TD_LOCK]))
        out[f"worker-b-dump-{i + 1}.txt"] = td_dump(ts, th)
    return out


STATUS = """[admin@bastion ~]$ curl -s "http://connect.example.com:8083/connectors?expand=status" | jq .
{
  "archive-sink": {
    "status": {
      "name": "archive-sink",
      "connector": {"state": "RUNNING", "worker_id": "10.0.0.11:8083"},
      "tasks": [{"id": 0, "state": "RUNNING", "worker_id": "10.0.0.11:8083"}],
      "type": "sink"
    }
  },
  "orders-cdc": {
    "status": {
      "name": "orders-cdc",
      "connector": {"state": "RUNNING", "worker_id": "10.0.0.12:8083"},
      "tasks": [{"id": 0, "state": "RUNNING", "worker_id": "10.0.0.11:8083"}],
      "type": "source"
    }
  },
  "payments-sink": {
    "status": {
      "name": "payments-sink",
      "connector": {"state": "RUNNING", "worker_id": "10.0.0.13:8083"},
      "tasks": [
        {
          "id": 0,
          "state": "FAILED",
          "worker_id": "10.0.0.13:8083",
          "trace": "org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler\\n\\tat org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:230)\\n\\tat org.apache.kafka.connect.runtime.WorkerSinkTask.convertAndTransformRecord(WorkerSinkTask.java:518)\\n\\tat org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:337)\\nCaused by: org.apache.kafka.connect.errors.DataException: Failed to deserialize data for topic payments to Avro: \\n\\tat io.confluent.connect.avro.AvroConverter.toConnectData(AvroConverter.java:148)\\nCaused by: org.apache.kafka.common.errors.SerializationException: Unknown magic byte!\\n\\tat io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.getByteBuffer(AbstractKafkaSchemaSerDe.java:600)\\n"
        }
      ],
      "type": "sink"
    }
  }
}
[admin@bastion ~]$
"""


# ── grafana-loki-export.txt: an S3 sink denied by S3, exported from Grafana Explore, newest first ──

def loki_export():
    s3 = "io.confluent.connect.s3.S3SinkTask"
    events = [  # (UTC time, log line of the worker in its local time, UTC+1)
        ("09:30:00.000", f"[{DAY} 10:30:00,000] INFO [s3-sink|task-0] Started S3 connector task with assigned partitions [orders-0, orders-1] ({s3}:150)"),
        ("09:30:01.120", f"[{DAY} 10:30:01,120] INFO [s3-sink|task-0] WorkerSinkTask{{id=s3-sink-0}} Executing sink task ({RUNTIME}.WorkerSinkTask:213)"),
    ]
    for i, t in enumerate(("10:00:05", "10:01:05", "10:02:05", "10:03:05")):
        events.append((f"{t}.{i}00", f"[{DAY} 11:{t[3:]},{i}00] WARN [s3-sink|task-0] Failed to upload part 1 of orders/partition=0/orders+0+0000004200.avro, retrying "
                                    f"({i + 1}/4): Access Denied (Service: Amazon S3; Status Code: 403; Error Code: AccessDenied) "
                                    "(io.confluent.connect.s3.storage.S3OutputStream:178)"))
    events.append(("10:04:05.900", f"[{DAY} 11:04:05,900] ERROR [s3-sink|task-0] WorkerSinkTask{{id=s3-sink-0}} Task threw an uncaught and unrecoverable exception. "
                                   f"Task is being killed and will not recover until manually restarted ({RUNTIME}.WorkerTask:234)\n"
                                   "org.apache.kafka.connect.errors.ConnectException: Unable to upload part 1 of orders/partition=0/orders+0+0000004200.avro\n"
                                   "\tat io.confluent.connect.s3.storage.S3OutputStream.uploadPart(S3OutputStream.java:190)\n"
                                   "Caused by: com.amazonaws.services.s3.model.AmazonS3Exception: Access Denied (Service: Amazon S3; Status Code: 403; "
                                   "Error Code: AccessDenied; Request ID: 0000000000000000)\n"
                                   "\tat com.amazonaws.http.AmazonHttpClient$RequestExecutor.handleErrorResponse(AmazonHttpClient.java:1880)"))
    events.append(("10:04:06.000", f"[{DAY} 11:04:06,000] ERROR [s3-sink|task-0] WorkerSinkTask{{id=s3-sink-0}} Task is being killed and will not recover "
                                   f"until manually restarted ({RUNTIME}.WorkerTask:235)"))
    out = ['"10 lines shown — 0.02% (40min) of 1h"', 'Total bytes processed: "48.2  kB"',
           'Common labels: {"app":"connect","namespace":"confluent","pod":"connect-0","service_name":"connect"}', "", ""]
    for t, text in sorted(events, reverse=True):  # Grafana exports the newest line first
        epoch_ns = calendar.timegm(time.strptime(f"{DAY} {t[:8]}", "%Y-%m-%d %H:%M:%S")) * 10 ** 9 + int(t[9:]) * 10 ** 6
        out.append(f"{epoch_ns}\t{DAY}T{t}Z\t{text}")
    return "\n".join(out) + "\n"


# ── connector-cr: one CFK Connector custom resource and the log of the worker saved as .txt ──

CONNECTOR_CR = """apiVersion: platform.confluent.io/v1beta1
kind: Connector
metadata:
  name: orders-sink
  namespace: confluent
spec:
  class: io.confluent.connect.jdbc.JdbcSinkConnector
  taskMax: 1
  connectClusterRef:
    name: connect
  configs:
    connection.url: jdbc:postgresql://db.example.com:5432/orders
    connection.user: connect
    connection.password: ${file:/mnt/secrets/postgres/credentials.properties:password}
    topics: orders
    insert.mode: upsert
    pk.mode: record_key
    auto.create: "true"
status:
  state: CREATED
  connectorState: RUNNING
  tasksReady: 0/1
"""


def connector_cr_log():
    out = worker_start("connect-0.connect.confluent.svc.cluster.local:8083", "09:00")
    out += start_task("connect-0.connect.confluent.svc.cluster.local:8083", "09:00:06", "orders-sink", "10.8.4",
                      "io.confluent.connect.jdbc.JdbcSinkConnector", "io.confluent.connect.jdbc.sink.JdbcSinkTask")
    for m in range(5, 40, 5):
        out.append(line(f"09:{m:02d}:00,000", "INFO", "Completed write operation for 500 records to the database",
                        "io.confluent.connect.jdbc.sink.JdbcSinkTask:96", "orders-sink|task-0"))
    for i, t in enumerate(("09:40:09,100", "09:40:12,200", "09:40:18,300")):
        out.append(line(t, "WARN", f"Write of 500 records failed, remainingRetries={2 - i}", "io.confluent.connect.jdbc.sink.JdbcSinkTask:101",
                        "orders-sink|task-0"))
        out.append("org.postgresql.util.PSQLException: Connection to db.example.com:5432 refused. Check that the hostname and port are correct "
                   "and that the postmaster is accepting TCP/IP connections.")
        out.append("\tat org.postgresql.core.v3.ConnectionFactoryImpl.openConnectionImpl(ConnectionFactoryImpl.java:352)")
        out.append("Caused by: java.net.ConnectException: Connection refused")
        out.append("\tat java.base/sun.nio.ch.Net.pollConnect(Native Method)")
    out.append(line("09:40:30,400", "ERROR", "WorkerSinkTask{id=orders-sink-0} Task threw an uncaught and unrecoverable exception. Task is being "
                    "killed and will not recover until manually restarted", f"{RUNTIME}.WorkerTask:234", "orders-sink|task-0"))
    out.append("org.apache.kafka.connect.errors.ConnectException: java.sql.SQLException: Exception chain:")
    out.append("org.postgresql.util.PSQLException: Connection to db.example.com:5432 refused. Check that the hostname and port are correct "
               "and that the postmaster is accepting TCP/IP connections.")
    out.append("\tat io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:130)")
    return "\n".join(out) + "\n"


def main():
    write("connect-workers/worker-a/connect.log", worker_a())
    write("connect-workers/worker-b/connect.log", worker_b())
    for name, text in thread_dumps().items():
        write(f"connect-workers/thread-dumps/{name}", text)
    write("connect-workers/connectors-status.txt", STATUS)
    write("grafana-loki-export.txt", loki_export())
    write("connector-cr/orders-sink-connector.yaml", CONNECTOR_CR)
    write("connector-cr/connect-0.txt", connector_cr_log())


if __name__ == "__main__":
    main()
