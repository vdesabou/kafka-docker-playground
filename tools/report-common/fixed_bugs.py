"""
Known bugs of connector plugins and Confluent Platform with the versions that fix them, for playground analyze logs
(🩹): a record that matches the pattern of a bug, logged by a connector whose plugin version the logs give (🏷️
"Instantiated connector … with version …"), gets a verdict: affected (upgrade to …), fixed in its version (another
cause, or a regression), or unknown version.

Each entry comes from the changelog of the plugin (playground connector-plugin changelog -c <plugin> --grep <ref>) and
the pull request of the fix, which gives the exception and the frames to match (never a guess from the changelog line
alone). A fix is backported to several minor lines: fixed_in has the first fixed version of each line, the lines newer
than all of them include the fix.

  title    what the bug is, as a known cause title
  plugin   owner/name of the plugin (connector-plugin changelog -c)
  classes  regex of the connector classes of the plugin (the class of the 🔌 card)
  pattern  regex matched (case-sensitive) against the record and its raw context lines
  fixed_in first fixed version of each minor line
  ref      the Jira / pull request ids of the changelog
  advice   what to do besides upgrading
  introduced_in (optional) for a regression, the first affected version of each minor line, as the changelog gives
           it: a version before it (or a line older than all of them) is not affected (verdict "fixed": another cause)

An entry is only kept when the release note names a symptom visible in the logs (an exception and its message, a
quoted error, an ORA- code) and the fixed versions: a vague "fixed an issue with …" is no 🩹. The pattern matches the
record of that symptom (the message, or the exception with a frame of the class the fix changed), never a common
exception class alone (the connector classes keep the others to that plugin).

A bug of Confluent Platform (the Kafka Connect runtime, MirrorMaker 2 or the broker, from Apache Kafka) has
"runtime": "cp" instead of classes: fixed_in has Confluent Platform versions (from playground cp-changelog), and the
verdict comes from the CP version of the process that logged the record ("Kafka version: x.y.z-ce" / -ccs of the same
file, else the only one of the input).
"""

import re
from typing import List, Optional, Tuple

FIXED_BUGS = [
    {"title": "🩹 JDBC sink task killed by a driver NullPointerException in the schema lookup",
     "plugin": "confluentinc/kafka-connect-jdbc",
     "classes": r"\.JdbcSinkConnector$|\.JdbcSinkTask$",
     # confluentinc/kafka-connect-jdbc#1707: a RuntimeException of the driver in Connection.getSchema() / getCatalog()
     # (Redshift / pgjdbc protocol desync) escaped the retry path of put() and killed the task
     "pattern": r"(?:NullPointerException|IllegalStateException)[\s\S]{0,6000}JdbcDbWriter\.get(?:Schema|Catalog)Safe"
                r"|Received resultset tuples, but no field structure for them",
     "fixed_in": ["10.8.13", "10.9.10"],
     "ref": "CC-46266 (PR-1707)",
     "advice": "the connection is broken after this error: fixed versions close it and retry (max.retries, "
               "retry.backoff.ms) instead of killing the task; until then, restart the task"},
    {"title": "🩹 S3 sink NullPointerException when a transform renames the topic",
     "plugin": "confluentinc/kafka-connect-s3",
     "classes": r"\.S3SinkConnector$|\.S3SinkTask$",
     # confluentinc/kafka-connect-storage-cloud#888: a RegexRouter / TopicRegexRouter changes the topic of the record, no
     # TopicPartitionWriter exists for it, put() threw a NullPointerException (now "No writer found for topic partition")
     "pattern": r"NullPointerException[\s\S]{0,6000}S3SinkTask\.put\b",
     "fixed_in": ["10.6.11", "11.0.8"],
     "ref": "CC-35613 (PR-888)",
     "advice": "a transform that changes the topic name (RegexRouter, TopicRegexRouter) is not supported by the S3 sink: "
               "remove it, and use topics.dir / a partitioner to choose the path; fixed versions fail with a clear "
               "message (or send the record to the DLQ)"},
    {"title": "🩹 Elasticsearch sink NullPointerException when a task stops before it started",
     "plugin": "confluentinc/kafka-connect-elasticsearch",
     "classes": r"\.ElasticsearchSinkConnector$|\.ElasticsearchSinkTask$",
     # confluentinc/kafka-connect-elasticsearch#939: stop() dereferenced the client of a task whose start() failed
     "pattern": r"NullPointerException[\s\S]{0,6000}ElasticsearchSinkTask\.stop\b",
     "fixed_in": ["15.0.7", "15.1.4"],
     "ref": "PR-939",
     "advice": "this NullPointerException hides the real error: the start() of a task failed first (ConfigException, "
               "ConnectException of the topic to resource map): read the error before it"},
    {"title": "🩹 Oracle CDC ConfigException on redo.log.consumer.bootstrap.servers at startup (CP 8.2)",
     "plugin": "confluentinc/kafka-connect-oracle-cdc",
     "classes": r"\.OracleCdcSourceConnector$|\.OracleCdcSourceTask$",
     "pattern": r"ConfigException[\s\S]{0,400}redo\.log\.consumer\.bootstrap\.servers",
     "fixed_in": ["2.13.11", "2.14.12", "2.15.1"],
     "ref": "CC-39664",
     "advice": "a Connect worker of Confluent Platform 8.2 rejected the redo log consumer configuration of older versions"},
    {"title": "🩹 S3 sink: offsets of skipped records never committed (consumer lag stuck, replay on restart)",
     "plugin": "confluentinc/kafka-connect-s3",
     "classes": r"\.S3SinkConnector$|\.S3SinkTask$",
     # confluentinc/kafka-connect-storage-cloud#972: preCommit() only committed the offset of the last record written to
     # S3, so the records skipped at the end of a partition (tombstones with behavior.on.null.values=ignore, records
     # dropped by errors.tolerance=all or a transform) were never committed: the lag stays, every restart replays them
     "pattern": r"Skipping null value record",
     "fixed_in": ["10.6.20", "11.0.21", "12.0.11", "12.1.14"],
     "ref": "CC-43920 (PR-972)",
     "advice": "the consumer lag of the partitions that end with skipped records (tombstones) never goes to 0 and each "
               "restart re-reads and re-logs them: no data is missing. It clears on a partition when a record with a "
               "value is written after them"},
    {"title": "🩹 Connect runtime: NullPointerException in recordTaskRemoved hides why a task failed to start",
     "runtime": "cp",
     "plugin": "Confluent Platform (Kafka Connect runtime)",
     # apache/kafka#21717 (KAFKA-19697): when a second task of the same connector fails to start on a worker, the clean-up
     # of the task metrics throws a NullPointerException, which replaces the real error in the task status
     "pattern": r"NullPointerException[\s\S]{0,6000}ConnectorStatusMetricsGroup\.recordTaskRemoved",
     "fixed_in": ["7.9.8", "8.0.6", "8.1.4", "8.2.2"],
     "ref": "KAFKA-19697 (PR-21717)",
     "advice": "the NullPointerException is not the cause: the task failed to start for another reason (logged just "
               "before it on the same worker: the converter, the config, the plugin). Upgrading only makes /status show "
               "that reason"},
    # ---- from the release notes (playground connector-plugin changelog / cp-changelog), checked in the code of the fix
    {"title": "🩹 Oracle CDC NullPointerException with header: fields and discarded long running transactions",
     "plugin": "confluentinc/kafka-connect-oracle-cdc",
     "classes": r"\.OracleCdcSourceConnector$|\.OracleCdcSourceTask$",
     # confluentinc/kafka-connect-oracle-cdc#440: isRemoveTransactionRecord() read the value of a header that a record
     # with other headers (header: prefix in output.*.field) does not have
     "pattern": r"NullPointerException[\s\S]{0,6000}TransactionAwareBlockingQueue\.isRemoveTransactionRecord",
     "fixed_in": ["2.10.6", "2.11.4", "2.12.2"],
     "ref": "CC-27327",
     "advice": "happens when a header: prefix is used in output.*.field together with the discard of long running "
               "transactions: until the upgrade, remove the header: fields or the discard option"},
    {"title": "🩹 Oracle CDC 2.11.0 SQLException: Invalid column name while reading redo log records",
     "plugin": "confluentinc/kafka-connect-oracle-cdc",
     "classes": r"\.OracleCdcSourceConnector$|\.OracleCdcSourceTask$",
     # confluentinc/kafka-connect-oracle-cdc#405: a regression of 2.11.0 read SQL_UNDO / USERNAME, columns the LogMiner
     # query does not select, for the records without a table (materialized views, internal tables)
     "pattern": r"Invalid column name[\s\S]{0,6000}OracleRedoLogReader",
     "fixed_in": ["2.11.1"],
     "introduced_in": ["2.11.0"],
     "ref": "CC-24832",
     "advice": "a regression of 2.11.0 only: the task fails on redo records of objects it does not capture "
               "(materialized views); no workaround but the upgrade"},
    {"title": "🩹 Oracle CDC ORA-08181 specified number is not a valid system change number (RAC)",
     "plugin": "confluentinc/kafka-connect-oracle-cdc",
     "classes": r"\.OracleCdcSourceConnector$|\.OracleCdcSourceTask$",
     # confluentinc/kafka-connect-oracle-cdc#392: on RAC, the current SCN and the next query ran on different
     # connections (instances)
     "pattern": r"ORA-08181",
     "fixed_in": ["2.7.11", "2.8.9", "2.9.7", "2.10.3"],
     "ref": "CC-24395",
     "advice": "on a RAC database the connector read the current SCN on one instance and used it on another: harmless "
               "retries on most versions, fixed by the upgrade"},
    {"title": "🩹 Oracle CDC ORA-01289 cannot add duplicate logfile",
     "plugin": "confluentinc/kafka-connect-oracle-cdc",
     "classes": r"\.OracleCdcSourceConnector$|\.OracleCdcSourceTask$",
     # CC-22889 (archived redo logs in several destinations: 2.7.8, 2.8.4, 2.9.2), then CC-24126 (online redo logs under
     # load, also an intermittent data loss: confluentinc/kafka-connect-oracle-cdc#399): fixed_in has the versions with both
     "pattern": r"ORA-01289",
     "fixed_in": ["2.8.8", "2.9.6", "2.10.2"],
     "ref": "CC-24126 (and CC-22889)",
     "advice": "the connector added the same redo log file twice to the LogMiner session (archived logs in several "
               "destinations, or online logs under load, where events could also be lost): upgrade, and check for "
               "missing events since the first error"},
    {"title": "🩹 Oracle CDC ORA-00310 archived log contains sequence … required (regression of 2.7.8 / 2.8.4 / 2.9.2)",
     "plugin": "confluentinc/kafka-connect-oracle-cdc",
     "classes": r"\.OracleCdcSourceConnector$|\.OracleCdcSourceTask$",
     "pattern": r"ORA-00310",
     "fixed_in": ["2.7.10", "2.8.6", "2.9.4"],
     "introduced_in": ["2.7.8", "2.8.4", "2.9.2"],
     "ref": "CC-23454",
     "advice": "a regression when processing archived redo logs; on other versions ORA-00310 means the archived log "
               "file at that path is not the one expected (reused or overwritten log destination): check "
               "V$ARCHIVED_LOG for the sequence"},
    {"title": "🩹 Oracle CDC StringIndexOutOfBoundsException on a column default value with spaces",
     "plugin": "confluentinc/kafka-connect-oracle-cdc",
     "classes": r"\.OracleCdcSourceConnector$|\.OracleCdcSourceTask$",
     # confluentinc/kafka-connect-oracle-cdc#318: the parser of the table schema split the default value on spaces
     "pattern": r"StringIndexOutOfBoundsException[\s\S]{0,6000}cdc\.database\.TableSchema",
     "fixed_in": ["2.7.2"],
     "ref": "CC-21021",
     "advice": "a captured table has a column whose default value contains a space: the status of its snapshot could "
               "not be read"},
    {"title": "🩹 Oracle CDC task failed on ORA-01284 / ORA-01291 instead of retrying",
     "plugin": "confluentinc/kafka-connect-oracle-cdc",
     "classes": r"\.OracleCdcSourceConnector$|\.OracleCdcSourceTask$",
     # confluentinc/kafka-connect-oracle-cdc#332: adding a redo log file to the LogMiner session is retried on ORA-01284
     "pattern": r"ORA-0128[4]\b|ORA-01291\b",
     "fixed_in": ["2.7.6", "2.8.2"],
     "ref": "CC-20296",
     "advice": "fixed versions retry these errors; when they persist, the redo log file is really missing or "
               "unreadable (archived logs deleted by RMAN before the connector read them): check the archive retention"},
    {"title": "🩹 Oracle XStream CDC: IllegalStateException schema history couldn't be recovered after a rebalance",
     "plugin": "confluentinc/kafka-connect-oracle-xstream-cdc-source",
     "classes": r"\.OracleXStreamSourceConnector$|\.OracleXStreamSourceTask$",
     "pattern": r"schema history couldn't be recovered",
     "fixed_in": ["1.5.0"],
     "ref": "CC-41772",
     "advice": "a race condition during a Connect rebalance; on fixed versions, the schema history topic is really "
               "missing, emptied by retention or shared with another connector: check its retention (infinite) and name"},
    {"title": "🩹 Oracle XStream CDC: ORA-26824 logged as an error when the task stops",
     "plugin": "confluentinc/kafka-connect-oracle-xstream-cdc-source",
     "classes": r"\.OracleXStreamSourceConnector$|\.OracleXStreamSourceTask$",
     # confluentinc/kafka-connect-oracle-xstream-cdc-source#219: the exception that ends the callback loop at stop was
     # reported as the error of the task
     "pattern": r"ORA-26824",
     "fixed_in": ["1.4.0"],
     "ref": "CC-38986",
     "advice": "harmless when logged while the task stops (rebalance, restart, delete); at any other time, read the "
               "state of the outbound server"},
    {"title": "🩹 Oracle XStream CDC: snapshot fails with NegativeArraySizeException (Oracle JDBC fetch size limit)",
     "plugin": "confluentinc/kafka-connect-oracle-xstream-cdc-source",
     "classes": r"\.OracleXStreamSourceConnector$|\.OracleXStreamSourceTask$",
     "pattern": r"NegativeArraySizeException",
     "fixed_in": ["1.4.0"],
     "ref": "CC-38806",
     "advice": "the Oracle JDBC driver cannot allocate the rows of a fetch of wide rows: fixed versions retry the "
               "snapshot query with a smaller fetch size; until then, lower snapshot.fetch.size"},
    {"title": "🩹 S3 sink task killed by an Avro SchemaParseException / Parquet InvalidSchemaException despite errors.tolerance",
     "plugin": "confluentinc/kafka-connect-s3",
     "classes": r"\.S3SinkConnector$|\.S3SinkTask$",
     # confluentinc/kafka-connect-storage-cloud#745: TopicPartitionWriter only sent DataException to the error handler
     "pattern": r"(?:SchemaParseException|InvalidSchemaException)[\s\S]{0,6000}s3\.TopicPartitionWriter",
     "fixed_in": ["10.5.12"],
     "ref": "CC-24623",
     "advice": "the schema of a record is not valid for the Avro / Parquet format (a field name with '-' or starting "
               "with a digit, an empty struct): fixed versions honor errors.tolerance (and the DLQ); fix the schema"},
    {"title": "🩹 JDBC sink: Underflow Exception trying to bind a tiny FLOAT / DOUBLE (Oracle)",
     "plugin": "confluentinc/kafka-connect-jdbc",
     "classes": r"\.JdbcSinkConnector$|\.JdbcSinkTask$",
     # confluentinc/kafka-connect-jdbc#1338: OracleDatabaseDialect binds FLOAT32 / FLOAT64 as BINARY_FLOAT / DOUBLE
     "pattern": r"[Uu]nderflow [Ee]xception trying to bind",
     "fixed_in": ["10.7.2"],
     "ref": "PR-1338",
     "advice": "a float or double value close to 0 (Double.MIN_VALUE) cannot be bound as an Oracle NUMBER by older "
               "versions"},
    {"title": "🩹 IBM MQ source rejected in bindings mode: neither mq.hostname nor mq.connection.list",
     "plugin": "confluentinc/kafka-connect-ibmmq",
     "classes": r"\.IbmMQSourceConnector$|\.IbmMQSourceTask$",
     # confluentinc/kafka-connect-jms#618: the validation added in 12.2.6 required one of them, also with
     # mq.transport.type=bindings (a local queue manager, no host)
     "pattern": r"Invalid connection configuration provided, mq\.hostname false mq\.connection\.list false",
     "fixed_in": ["12.2.15", "13.0.7"],
     "introduced_in": ["12.2.6"],
     "ref": "CC-39408",
     "advice": "with mq.transport.type=bindings no host is needed: affected versions refuse the configuration "
               "(upgrade); with the client transport, set mq.hostname or mq.connection.list"},
    {"title": "🩹 Salesforce Bulk API source fails at startup when Salesforce rejects its new session",
     "plugin": "confluentinc/kafka-connect-salesforce-bulk-api",
     "classes": r"\.SalesforceBulkApiSourceConnector$|\.SalesforceBulkApiSourceTask$",
     # confluentinc/kafka-connect-salesforce (CC-45739): the describe of the object at start was not retried on
     # INVALID_SESSION_ID / SERVER_UNAVAILABLE / UNKNOWN_EXCEPTION
     "pattern": r"Error while describing \S+[\s\S]{0,6000}(?:INVALID_SESSION_ID|SERVER_UNAVAILABLE|UNKNOWN_EXCEPTION)",
     "fixed_in": ["3.0.19", "3.1.13"],
     "ref": "CC-45739",
     "advice": "a transient rejection by Salesforce of a session just created: restart the task; fixed versions retry "
               "within request.max.retries.time.ms"},
    {"title": "🩹 Salesforce CDC / PushTopic / Platform Event source killed by a transient error while reloading metadata",
     "plugin": "confluentinc/kafka-connect-salesforce",
     "classes": r"\.Salesforce(?:Cdc|PushTopic|PlatformEvent)Source(?:Connector|Task)$",
     # confluentinc/kafka-connect-salesforce#910: the describe calls after a reconnection were not retried on HTTP 429,
     # 500 and 503 (REQUEST_LIMIT_EXCEEDED, UNKNOWN_EXCEPTION, SERVER_UNAVAILABLE)
     "pattern": r"Failed to get metadata from salesforce[\s\S]{0,6000}(?:REQUEST_LIMIT_EXCEEDED|UNKNOWN_EXCEPTION|SERVER_UNAVAILABLE)",
     "fixed_in": ["3.0.17", "3.1.11"],
     "ref": "CC-43770",
     "advice": "a single transient Salesforce error after a reconnection failed the task: restart it; fixed versions "
               "retry with backoff"},
    {"title": "🩹 Salesforce connectors: gRPC ClassCastException (ContextStorageOverride) on Confluent Platform 8.2+",
     "plugin": "confluentinc/kafka-connect-salesforce",
     "classes": r"\.Salesforce\w+(?:Connector|Task)$",
     # confluentinc/kafka-connect-salesforce (CC-39760): the gRPC of the plugin clashed with the one of the CP 8.2 runtime
     "pattern": r"ClassCastException[\s\S]{0,600}io\.grpc\.override\.ContextStorageOverride",
     "fixed_in": ["3.0.9", "3.1.3"],
     "ref": "CC-39760",
     "advice": "the plugin bundles a gRPC that conflicts with the one of a Confluent Platform 8.2 (or later) worker"},
    {"title": "🩹 ServiceNow connectors: gRPC Context initialization failure on Confluent Platform 8.2+",
     "plugin": "confluentinc/kafka-connect-servicenow",
     "classes": r"\.ServiceNow(?:Source|Sink)(?:Connector|Task)$",
     # confluentinc/kafka-connect-servicenow#256: same gRPC ContextStorageOverride conflict
     "pattern": r"ClassCastException[\s\S]{0,600}io\.grpc\.override\.ContextStorageOverride",
     "fixed_in": ["2.6.3"],
     "ref": "CC-39665",
     "advice": "the plugin bundles a gRPC that conflicts with the one of a Confluent Platform 8.2 (or later) worker"},
    {"title": "🩹 BigQuery sink: gRPC ClassCastException (ContextStorageOverride) on Confluent Platform 8.2+",
     "plugin": "wepay/kafka-connect-bigquery",
     "classes": r"\.BigQuerySink(?:Connector|Task)$",
     # confluentinc/kafka-connect-bigquery (PR-471): gRPC excluded from the Google libraries, the runtime's is used
     "pattern": r"ClassCastException[\s\S]{0,600}io\.grpc\.override\.ContextStorageOverride",
     "fixed_in": ["2.5.9"],
     "ref": "PR-471",
     "advice": "the plugin bundles a gRPC that conflicts with the one of a Confluent Platform 8.2 (or later) worker"},
    {"title": "🩹 BigQuery sink: MERGE failed on Could not serialize access to table (upsert / delete)",
     "plugin": "wepay/kafka-connect-bigquery",
     "classes": r"\.BigQuerySink(?:Connector|Task)$",
     # confluentinc/kafka-connect-bigquery#239: MergeQueries did not retry the concurrent update error of BigQuery
     "pattern": r"Could not serialize access to[\s\S]{0,6000}MergeQueries",
     "fixed_in": ["2.5.0"],
     "ref": "PR-239",
     "advice": "with upsert.enabled / delete.enabled, two MERGE statements on the same table conflicted; fixed "
               "versions retry (30 times): if it persists, another job writes the table at the same time"},
    {"title": "🩹 BigQuery sink: MERGE failed on a transient jobInternalError",
     "plugin": "wepay/kafka-connect-bigquery",
     "classes": r"\.BigQuerySink(?:Connector|Task)$",
     # confluentinc/kafka-connect-bigquery#363
     "pattern": r"jobInternalError[\s\S]{0,6000}MergeQueries",
     "fixed_in": ["2.5.4"],
     "ref": "PR-363",
     "advice": "a transient BigQuery error of the MERGE job (upsert / delete mode) failed the task: restart it; fixed "
               "versions retry (bigQueryRetry, bigQueryRetryWait)"},
    {"title": "🩹 HDFS 3 sink plugin fails to load on Confluent Platform 8.4: NoClassDefFoundError AppInfoParser",
     "plugin": "confluentinc/kafka-connect-hdfs3",
     "classes": r"\.Hdfs3Sink(?:Connector|Task)$|hdfs3\.tools\.SchemaSource(?:Connector|Task)$",
     # confluentinc/kafka-connect-hdfs3#309: SchemaSourceConnector.version() called AppInfoParser, moved to
     # ...utils.internals in Apache Kafka 4.x: the plugin scan fails (and a standalone worker exits)
     "pattern": r"NoClassDefFoundError: org/apache/kafka/common/utils/AppInfoParser[\s\S]{0,6000}hdfs3"
                r"|hdfs3\.tools\.SchemaSourceConnector[\s\S]{0,6000}NoClassDefFoundError: org/apache/kafka/common/utils/AppInfoParser",
     "fixed_in": ["1.2.28", "2.0.23", "3.0.21"],
     "ref": "CC-44958",
     "advice": "the plugin version is older than the Confluent Platform 8.4 worker it runs on"},
    {"title": "🩹 Azure Blob Storage sink: NoClassDefFoundError of a Jackson annotation with the JsonConverter",
     "plugin": "confluentinc/kafka-connect-azure-blob-storage",
     "classes": r"\.AzureBlobStorageSink(?:Connector|Task)$",
     # confluentinc/kafka-connect-azure-blob-storage#185: jackson-annotations was missing from the plugin
     "pattern": r"NoClassDefFoundError: com/fasterxml/jackson/annotation/",
     "fixed_in": ["1.6.9"],
     "ref": "CCMSG-1811",
     "advice": "jackson-annotations is missing from the plugin folder of older versions"},
    {"title": "🩹 Azure Data Lake Gen2 sink: NoClassDefFoundError of a Jackson annotation with the JsonConverter",
     "plugin": "confluentinc/kafka-connect-azure-data-lake-gen2-storage",
     "classes": r"\.AzureDataLakeGen2Sink(?:Connector|Task)$",
     "pattern": r"NoClassDefFoundError: com/fasterxml/jackson/annotation/",
     "fixed_in": ["1.6.9"],
     "ref": "CCMSG-1811",
     "advice": "jackson-annotations is missing from the plugin folder of older versions"},
    {"title": "🩹 Kinesis source NullPointerException in getCredentialsProvider without an access key",
     "plugin": "confluentinc/kafka-connect-kinesis",
     "classes": r"\.KinesisSource(?:Connector|Task)$",
     "pattern": r"NullPointerException[\s\S]{0,6000}KinesisSourceConnectorConfig\.getCredentialsProvider",
     "fixed_in": ["1.1.14", "1.2.4", "1.3.4"],
     "ref": "CCMSG-765",
     "advice": "aws.access.key.id is not set (credentials from a provider chain): older versions fail; until the "
               "upgrade, set it to an empty string"},
    {"title": "🩹 SFTP CSV source NullPointerException when reconnecting (reconfigureFileReader)",
     "plugin": "confluentinc/kafka-connect-sftp",
     "classes": r"\.SftpCsvSource(?:Connector|Task)$",
     # confluentinc/kafka-connect-sftp#194: after a reconnection with no file open, the CSV reader was reconfigured
     "pattern": r"NullPointerException[\s\S]{0,6000}SftpCsvSourceTask\.reconfigureFileReader",
     "fixed_in": ["3.2.6"],
     "ref": "RCCA-20439",
     "advice": "the SFTP connection dropped while no file was being read: restart the task"},
    {"title": "🩹 SFTP source NullPointerException in read() while handling a file that failed",
     "plugin": "confluentinc/kafka-connect-sftp",
     "classes": r"\.Sftp\w*Source(?:Connector|Task)$",
     # confluentinc/kafka-connect-sftp#112: the error path of read() used the name of a file that was not open
     "pattern": r"NullPointerException[\s\S]{0,6000}AbstractSftpSourceTask\.read\b",
     "fixed_in": ["3.2.0"],
     "ref": "RCCA-9970",
     "advice": "the NullPointerException hides the real error of reading the file (connection, parse): read the WARN "
               "before it"},
    {"title": "🩹 MirrorMaker 2 NullPointerException in MirrorCheckpointTask.syncGroupOffset (group offset reset to -1)",
     "runtime": "cp",
     "plugin": "Confluent Platform (Kafka Connect runtime)",
     # apache/kafka#14587 (KAFKA-15607): a target group offset reset to -1 (non Java clients) has no OffsetAndMetadata
     "pattern": r"NullPointerException[\s\S]{0,6000}MirrorCheckpointTask\.syncGroupOffset",
     "fixed_in": ["7.5.3", "7.6.0"],
     "ref": "KAFKA-15607 (PR-14587)",
     "advice": "a consumer group of the target cluster has an offset reset to -1 (a non Java client such as sarama): "
               "the offset sync of MirrorCheckpointConnector stops for it"},
    {"title": "🩹 MirrorMaker 2 NullPointerException in MirrorCheckpointTask.checkpoint (null committed offset)",
     "runtime": "cp",
     "plugin": "Confluent Platform (Kafka Connect runtime)",
     # apache/kafka#13052 (KAFKA-14545)
     "pattern": r"NullPointerException[\s\S]{0,6000}MirrorCheckpointTask\.checkpoint\(",
     "fixed_in": ["7.5.0"],
     "ref": "KAFKA-14545 (PR-13052)",
     "advice": "a source consumer group has a partition without committed offset: no checkpoint is emitted for the "
               "whole group"},
    {"title": "🩹 Connect runtime: harmless WARN Ignoring offset partition key … actual type: null",
     "runtime": "cp",
     "plugin": "Confluent Platform (Kafka Connect runtime)",
     # apache/kafka#15562 (KAFKA-16392): a source offset with a null partition (a tombstone written to reset offsets)
     "pattern": r"Ignoring offset partition key with an unexpected format for the second element in the partition key "
                r"list\. Expected type: java\.util\.Map, actual type: null",
     "fixed_in": ["7.6.1", "7.7.0"],
     "ref": "KAFKA-16392 (PR-15562)",
     "advice": "harmless: an offset of the offsets topic was deleted (tombstone, offsets reset or connector deleted); "
               "fixed versions no longer log it"},
    {"title": "🩹 Broker InvalidRequestException ADD_PARTITIONS_TO_TXN version 4 not enabled during a rolling upgrade",
     "runtime": "cp",
     "plugin": "Confluent Platform (Kafka broker)",
     # apache/kafka#15971 (KAFKA-16992): an upgraded broker sent the transaction verification request with a version
     # the brokers not yet upgraded do not enable
     "pattern": r"ADD_PARTITIONS_TO_TXN with version 4 which is not enabled",
     "fixed_in": ["7.6.2", "7.7.0"],
     "ref": "KAFKA-16992 (PR-15971)",
     "advice": "transactional producers fail while the brokers run mixed versions during a rolling upgrade: it stops "
               "once every broker runs the new version; upgrade to a fixed version"},
    {"title": "🩹 Connect worker fails at startup on InvalidReplicationFactorException creating its internal topics",
     "runtime": "cp",
     "plugin": "Confluent Platform (Kafka Connect runtime)",
     # apache/kafka#11565 (KAFKA-13504): the creation of connect-configs / -offsets / -status is retried while the
     # brokers start, instead of failing the worker at once
     "pattern": r"InvalidReplicationFactorException[\s\S]{0,6000}KafkaBasedLog\.start",
     "fixed_in": ["7.6.0"],
     "ref": "KAFKA-13504 (PR-11565)",
     "advice": "fewer brokers were available than the replication factor of an internal topic "
               "(config/offset/status.storage.replication.factor): affected versions give up at once while the brokers "
               "start; on fixed versions, the replication factor is really larger than the number of brokers"},
]


def parse_version(v: str) -> Optional[Tuple[int, ...]]:
    m = re.match(r"^v?(\d+(?:\.\d+)*)", v or "")
    return tuple(int(x) for x in m.group(1).split(".")) if m else None


def introduced(version: Tuple[int, ...], introduced_in: List[str]) -> bool:
    """a regression: is `version` at or after the first affected version of its minor line (a line older than every
    affected line is not affected, a line newer than one of them is)"""
    intro = sorted(p for f in introduced_in for p in [parse_version(f)] if p)
    for p in intro:
        if p[:2] == version[:2]:
            return version >= p
    return any(p[:2] < version[:2] for p in intro)


def verdict(version: str, fixed_in: List[str], introduced_in: Optional[List[str]] = None) -> Tuple[str, Optional[str]]:
    """(affected | fixed | unknown, the version to upgrade to): the first fixed version of the minor line of `version`;
    a line older than every fixed line is affected (upgrade to the first fixed version above it), a line newer than all
    of them has the fix. A regression (introduced_in: given, or the one of the FIXED_BUGS entry whose fixed_in list this
    is) does not affect a version before it: "fixed" (not this bug)"""
    v = parse_version(version)
    fixed = sorted((p, f) for f in fixed_in for p in [parse_version(f)] if p)
    if not v or not fixed:
        return "unknown", None
    if introduced_in is None:
        introduced_in = next((b.get("introduced_in") for b in FIXED_BUGS if b["fixed_in"] is fixed_in), None)
    if introduced_in and not introduced(v, introduced_in):
        return "fixed", None
    line = v[:2]
    for p, f in fixed:
        if p[:2] == line:
            return ("fixed", None) if v >= p else ("affected", f)
    above = [f for p, f in fixed if p[:2] > line]
    if above:
        return "affected", above[0]
    return "fixed", None
