"""
Known causes of log records, shared by the log analyzers of the playground:

- tools/log-analyzer/log_report.py (playground analyze logs, container logs --errors --html, get-ci-result --logs,
  connector diagnose, and tools/dlq-tool through its HINTS): the entries with a title are its "known causes",
  shown with their advice. Entries sharing a title are one known cause.
- cfk-analysis/analyzer.py (playground analyze logs on a CFK support bundle): every entry is a pattern of its
  classification, the category picks the remediation steps of cfk-analysis/recommendations.py.

Patterns are matched case-insensitively. In declaration order: the CFK analyzer keeps the first entry that matches a
record, so a specific cause comes before a generic one (`No space left on device` is a storage issue, not an
IOException). Unbounded `.*` are written `.{0,N}`: millions of records go through them.

`hint: False` marks a catch-all (any ConnectException, any Kafka exception): it sorts a record into a category for
the CFK report, but explains nothing, so the log report does not take it as a known cause (its root causes keep
the record).
"""

import json
import os
import re
import sys

KILLED_TASK_PATTERN = r"Task threw an uncaught and unrecoverable exception|Task is being killed and will not recover"
# the log report lists the exception chains of this known cause: hints() rewrites the patterns, so match it by title
KILLED_TASK_TITLE = "🧨 A connector task was killed"

KNOWN_CAUSES = [
    {"name": "oom_killed", "severity": "critical", "category": "Resource Issues",
     "pattern": r"OOMKilled|OutOfMemoryError|Out of memory",
     "title": "💥 OutOfMemoryError",
     "advice": "the JVM ran out of heap (or metaspace / direct memory): raise -Xmx (KAFKA_HEAP_OPTS) or lower the batch "
               "sizes, and look at what fills the heap with playground debug heap-dump + playground analyze heap-dump"},
    {"name": "license_error", "severity": "critical", "category": "License Issues",
     "pattern": r"license has expired|license is invalid|LicenseManagerException|license verification failed"
                r"|License manager.{0,40}error",
     "title": "📜 License error",
     "advice": "the Confluent license is expired, invalid or cannot be verified: check confluent.license and the "
               "_confluent-command topic"},
    # the log cleaner thread of a broker died (or gave up on a partition): before storage_error, its exception can be a
    # KafkaStorageException. Nothing else is logged after it: compacted topics grow until the disk is full
    {"name": "log_cleaner_died", "severity": "high", "category": "Storage Issues",
     "pattern": r"kafka-log-cleaner-thread-\d+\]?:? *Error due to|marked as uncleanable|LogCleaner.{0,80}Unexpected exception",
     "title": "🧽 Log cleaner stopped",
     "advice": "the log cleaner of the broker died or skipped a partition (the exception of the record says why): "
               "compacted topics (__consumer_offsets, connect-offsets, _schemas, changelogs) stop being compacted and "
               "grow until the disk is full. Fix the cause, then restart the broker to restart its cleaner; watch "
               "kafka.log:type=LogCleanerManager,name=time-since-last-run-ms and max-dirty-percent"},
    {"name": "storage_error", "severity": "critical", "category": "Storage Issues",
     "pattern": r"no space left on device|disk.{0,20}full|KafkaStorageException|log director(?:y|ies).{0,60}offline"
                r"|PersistentVolumeClaim.{0,80}pending",
     "title": "💾 Storage failure",
     "advice": "a disk is full or a log directory went offline: free or grow the volume, then restart the broker"},
    # the JVM default truststore (javax.net.ssl.trustStore) has no trusted certificate: a PKCS12 store read without
    # javax.net.ssl.trustStorePassword, an empty or missing file. Before tls_handshake: it is also an SSLException
    {"name": "empty_truststore", "severity": "high", "category": "JVM Truststore Issues",
     "pattern": r"trustAnchors parameter must be non-empty|Keystore was tampered with, or password was incorrect"
                r"|FileNotFoundException: \S*(?:truststore|keystore)\S*",
     "title": "🗝️ Empty or unreadable truststore",
     "advice": "the truststore has no trusted certificate (a PKCS12 store read without its password, a missing or empty "
               "file): set javax.net.ssl.trustStorePassword with javax.net.ssl.trustStore, or fix the path"},
    {"name": "tls_handshake", "severity": "high", "category": "Certificate/TLS Issues",
     "pattern": r"SSLHandshakeException|SSLException|SSL handshake failed|PKIX path|unable to find valid certification path"
                r"|No subject alternative names|certificate verify failed|x509:|tls: bad certificate"
                r"|tls handshake (?:error|failure|timeout)|bad_certificate|certificate_unknown|handshake_failure"
                r"|certificate (?:has )?expired",
     "title": "🔐 TLS handshake failure",
     "advice": "the truststore does not trust the server certificate, the hostname does not match it, or it expired"},
    # an AWS SDK error ("(Service: S3, Status Code: 403, Request ID: …"): the credentials or the IAM permissions of the
    # connector on the cloud service, not a Kafka ACL. Before rbac_error, which skips these 403
    {"name": "cloud_credentials", "severity": "high", "category": "Authentication Issues",
     "pattern": r"SignatureDoesNotMatch|request signature we calculated does not match|InvalidAccessKeyId"
                r"|security token included in the request is (?:invalid|expired)|ExpiredToken"
                r"|\(Service: [\w .-]{1,40}[,;] Status Code: 40[13]\b",
     "title": "☁️ Cloud credentials or permission refused",
     "advice": "the cloud service (AWS S3, Kinesis, Lambda…) refused the request of the connector: a wrong secret key "
               "(SignatureDoesNotMatch), an access key or session token deleted, rotated or expired, a clock skew of "
               "the worker, or an IAM / bucket policy that denies the action (403 AccessDenied): check the credentials "
               "of the connector (aws.access.key.id / aws.secret.access.key, or its credentials provider) and the IAM "
               "policy"},
    {"name": "authentication_failed", "severity": "high", "category": "Authentication Issues",
     "pattern": r"SaslAuthenticationException|AuthenticationException|authentication failed|failed authentication"
                r"|invalid credentials|ORA-01017|Access denied for user|Login failed for user|\b401 unauthorized\b"
                r"|\bunauthorized\b|http (?:status|code|error)[ :=]*401|Status code\s*:?\s*401",
     "title": "🔑 Authentication failure",
     "advice": "check the credentials (user, password, API key, keytab) of the client or of the external system"},
    {"name": "mds_error", "severity": "high", "category": "MDS/RBAC Issues",
     "pattern": r"MDS.{0,40}failed|metadata service.{0,40}error|TokenBasedSecurityStore.{0,80}Exception|RBAC.{0,40}token"
                r"|MdsException",
     "title": "🪪 MDS / RBAC token error",
     "advice": "the client cannot get or validate its token from the metadata service (MDS): check its URL, the "
               "token keypair and the credentials of the principal"},
    {"name": "rbac_error", "severity": "high", "category": "RBAC Issues",
     "pattern": r"forbidden: User .{0,80} cannot|is forbidden|(?:Topic|Group|Cluster|TransactionalId)?AuthorizationException"
                r"|not authorized to access|\b403 forbidden\b|http (?:status|code|error)[ :=]*403"
                r"|(?<![,;] )Status code\s*:?\s*403"
                r"|(?:Topic|Group|Cluster|Transactional Id) authorization failed"
                r"|error code:? ?40301|User is denied operation .{0,80} on (?:Subject|subject)",
     "title": "🚫 Authorization failure",
     "advice": "an ACL or an RBAC role binding is missing for the principal of the client"},
    {"name": "replication_error", "severity": "high", "category": "Replication Issues",
     "pattern": r"InvalidReplicationFactorException|NotEnoughReplicas(?:AfterAppend)?Exception"
                r"|replication factor.{0,60}(?:larger|greater) than|under.?min.?isr|replica fetcher.{0,60}(?:error|failed)"
                r"|replication.{0,40}failed",
     "title": "🧬 Not enough replicas",
     "advice": "fewer brokers or in-sync replicas than the replication factor / min.insync.replicas: check the brokers "
               "that are down and the replication factor of the internal topics"},
    {"name": "kraft_error", "severity": "high", "category": "KRaft Issues",
     "pattern": r"KRaft.{0,80}error|controller.{0,40}election.{0,40}failed|quorum.{0,40}(?:error|timeout|unavailable)"
                r"|NotControllerException|RaftClient.{0,80}(?:error|exception)|metadata log.{0,40}(?:corrupt|failed|error)",
     "title": "🗳️ KRaft quorum error",
     "advice": "the KRaft controllers have no leader or cannot reach each other: check controller.quorum.voters and "
               "the controllers that are down"},
    {"name": "zookeeper_error", "severity": "high", "category": "Zookeeper Issues",
     "pattern": r"zookeeper.{0,160}exception|SessionExpiredException|zookeeper.{0,80}session.{0,40}expired|KeeperException"
                r"|ConnectionLoss",
     "title": "🦓 ZooKeeper session error",
     "advice": "the ZooKeeper session expired or was lost: look for long GC pauses on the client and for ZooKeeper "
               "nodes that are down"},
    {"name": "plugin_not_found", "severity": "high", "category": "Plugin Issues",
     "pattern": r"Failed to find any class that implements Connector|Failed to find any class that implements Converter",
     "title": "🧩 Plugin not found",
     "advice": "the connector or converter class is not installed in the plugin.path of the worker (or has a typo)"},
    {"name": "class_loading", "severity": "high", "category": "Plugin Issues",
     "pattern": r"ClassNotFoundException|NoClassDefFoundError|NoSuchMethodError|NoSuchFieldError",
     "title": "📦 Class loading error",
     "advice": "a jar is missing from the plugin, or two versions of a library clash in the plugin path"},
    # Kafka Streams (the 🌊 Kafka Streams section of analyze logs and playground streams status explain the same errors,
    # tools/streams-analyzer/streams_report.py). Before the generic serialization and Kafka entries: a Kafka Streams
    # deserialization error is also a SerializationException
    {"name": "streams_copartition", "severity": "high", "category": "Kafka Streams Issues",
     "pattern": r"Topics not co-partitioned",
     "title": "🪢 Kafka Streams: topics not co-partitioned",
     "advice": "the source topics of a join do not have the same number of partitions: repartition one side or create "
               "them with the same partition count. Since Kafka Streams 3.2 two source topics joined directly are no "
               "longer refused and join results are silently missing for some keys (other/kafka-streams/join.sh)"},
    {"name": "streams_missing_source", "severity": "high", "category": "Kafka Streams Issues",
     "pattern": r"MissingSourceTopicException|One or more source topics were missing",
     "title": "🕳️ Kafka Streams: missing source topic",
     "advice": "a source topic of the topology does not exist, or the application cannot describe it (ACL): create it "
               "before starting the application"},
    {"name": "streams_fenced", "severity": "high", "category": "Kafka Streams Issues",
     "pattern": r"Detected that the thread is being fenced|Producer got fenced",
     "title": "🧟 Kafka Streams: producer fenced (exactly-once)",
     "advice": "another instance took over the tasks of this thread (paused, too slow, session lost): its transaction is "
               "aborted and the tasks migrate. Look at GC pauses, max.poll.interval.ms and transaction.timeout.ms "
               "(other/kafka-streams/eos.sh, playground streams status)"},
    {"name": "streams_task_migrated", "severity": "medium", "category": "Kafka Streams Issues",
     "pattern": r"TaskMigratedException",
     "title": "🚚 Kafka Streams: task migrated",
     "advice": "a stream thread lost the ownership of its tasks (rebalance during processing, fenced producer, kicked out "
               "of the group) and rejoins: frequent occurrences point at slow processing between polls "
               "(max.poll.interval.ms), GC pauses or unstable members (playground streams status counts the rebalances)"},
    {"name": "streams_deserialization", "severity": "high", "category": "Kafka Streams Issues",
     "pattern": r"Exception caught during Deserialization|deserialization error callback",
     "title": "🧪 Kafka Streams: deserialization error",
     "advice": "a record does not match the serdes (poison pill, wrong format): deserialization.exception.handler "
               "(default.deserialization.exception.handler before 4.0) stops the thread with LogAndFailExceptionHandler, "
               "skips it with LogAndContinueExceptionHandler (other/kafka-streams/serde-errors.sh)"},
    {"name": "streams_state_dir_lock", "severity": "high", "category": "Kafka Streams Issues",
     "pattern": r"Failed to lock the state directory|Failed to lock state directory|streams\.errors\.LockException",
     "title": "🔒 Kafka Streams: state directory locked",
     "advice": "two threads or instances use the same state.dir for a task (two instances on one volume, a previous "
               "instance still running): give each instance its own state.dir"},
    {"name": "streams_uncaught", "severity": "high", "category": "Kafka Streams Issues",
     "pattern": r"Encountered the following exception during processing|stream thread will shut down"
                r"|Replacing thread in the streams uncaught exception handler",
     "title": "💀 Kafka Streams: stream thread died",
     "advice": "an exception killed a stream thread: the StreamsUncaughtExceptionHandler replaces the thread, shuts down "
               "the client or the application. The cause is in the exception chain of the record"},
    {"name": "unknown_magic_byte", "severity": "high", "category": "Serialization Issues",
     "pattern": r"Unknown magic byte",
     "title": "🧲 Unknown magic byte",
     "advice": "the records were not written with the Schema Registry serializer the converter expects: check "
               "key.converter / value.converter against the producer (playground topic consume shows the real format)"},
    # the 3 most common Schema Registry errors, each with the playground schema command that explains it: before
    # serialization_error, the first match wins in the CFK analyzer (DataException: … error code: 40403 is a deleted schema)
    {"name": "schema_id_not_found", "severity": "high", "category": "Schema Registry Issues",
     "pattern": r"Error retrieving (?:Avro|JSON|Protobuf) (?:unknown )?schema(?: version)? for id|Schema \d+ not found"
                r"|error code:? ?40403",
     "title": "🔍 Schema id not found",
     "advice": "the schema id written in the records doesn't resolve any more: it was permanently deleted (a soft delete "
               "keeps ids readable), or the consumer reads another registry. playground schema history shows when "
               "and how it was deleted (💀), playground schema describe --id <id> who uses it"},
    {"name": "schema_incompatible", "severity": "high", "category": "Schema Registry Issues",
     "pattern": r"Schema being registered is incompatible with an earlier schema|error code:? ?409\b|error code:? ?40901",
     "title": "🛡️ Incompatible schema refused",
     "advice": "a producer (or source connector) registers a version the compatibility rule refuses: "
               "playground schema check-compatibility and playground schema diff --subject <s> --to @<new schema> show "
               "the field that breaks it and which rule would accept it"},
    {"name": "subject_not_found", "severity": "medium", "category": "Schema Registry Issues",
     "pattern": r"Subject .{0,80}not found|error code:? ?40401",
     "title": "📛 Subject not found",
     "advice": "the client looks up a subject that doesn't exist: the subject name strategy differs between producer "
               "and consumer, or auto.register.schemas=false / use.latest.version with an unregistered schema. "
               "playground schema list shows the real subject names"},
    {"name": "serialization_error", "severity": "medium", "category": "Serialization Issues",
     "pattern": r"Converting byte\[\] to Kafka Connect data failed|SerializationException|DataException",
     "title": "🔀 Serialization or conversion error",
     "advice": "the converter does not match the format of the records, or a record does not match the schema; "
               "errors.tolerance=all + a dead letter queue keeps the task running (playground topic dlq inspect)"},
    {"name": "record_too_large", "severity": "medium", "category": "Kafka Issues",
     "pattern": r"RecordTooLargeException|MESSAGE_TOO_LARGE|MSG_SIZE_TOO_LARGE|Message size too large|message\.max\.bytes",
     "title": "📏 Record too large",
     "advice": "raise max.request.size of the producer (producer.override.max.request.size for a source connector) and "
               "message.max.bytes / max.message.bytes on the broker or topic"},
    {"name": "unknown_topic", "severity": "medium", "category": "Kafka Issues",
     "pattern": r"UnknownTopicOrPartitionException|UNKNOWN_TOPIC_OR_PARTITION|Unknown topic or partition",
     "title": "❓ Unknown topic or partition",
     "advice": "the topic does not exist and is not auto-created: create it, or check its name"},
    {"name": "offset_out_of_range", "severity": "medium", "category": "Kafka Issues",
     "pattern": r"OffsetOutOfRangeException|OFFSET_OUT_OF_RANGE|Offset out of range",
     "title": "⏮️ Offset out of range",
     "advice": "the committed offset was deleted by retention: the consumer restarts from auto.offset.reset"},
    {"name": "task_killed", "severity": "high", "category": "Connect Issues",
     "pattern": KILLED_TASK_PATTERN,
     "title": KILLED_TASK_TITLE,
     "advice": "it stays FAILED until it is restarted: fix the cause (the exception chain of the record), then "
               "playground connector restart --connector <connector>"},
    # what a task's clients log when the task is stopped from another thread (restart, rebalance, a graceful stop that timed
    # out): the consumer closed by an interrupted thread ("Failed to close fetcher with a timeout(ms)=30000" +
    # InterruptException), the producer closed with records in flight (LogReporter "Producer is closed forcefully."). Many
    # of them, and no cause of their own: a consequence, not the problem
    {"name": "clients_aborted_on_stop", "severity": "low", "category": "Connect Issues",
     "pattern": r"Failed to close (?:fetcher|coordinator) with a timeout|Producer is closed forcefully",
     "title": "🧹 Clients aborted while a task stopped",
     "advice": "a consequence: the task was stopped (restart, rebalance, a graceful stop that timed out, a killed task) "
               "and its consumer or producer was closed while it was still working. A source task sends the records "
               "aborted again from its last committed offset. Look at why the task stopped (🧨, 🛑, 🔁 and the "
               "restarts) rather than at these errors"},
    # a host name that does not resolve. "No resolvable bootstrap urls given in bootstrap.servers": a Java client created
    # while none of its bootstrap servers resolves fails in its constructor (ConfigException), it is not retried: fatal to
    # the code that creates clients on the fly (the Oracle CDC source commits its redo log offsets with a new consumer)
    {"name": "dns_error", "severity": "high", "category": "Network Issues",
     "pattern": r"no such host|DNS resolution failed|dial tcp: lookup|UnknownHostException|Couldn't resolve server"
                r"|Failed to resolve '|Name or service not known|getaddrinfo (?:ENOTFOUND|EAI_AGAIN)"
                r"|Temporary failure in name resolution|No resolvable bootstrap urls",
     "title": "🌐 Host name not resolved (DNS)",
     "advice": "a host name did not resolve: a typo or a missing DNS record when it never works; a DNS outage when it "
               "stops on its own (the window and hosts below). A Java client created during the outage fails in its "
               "constructor (\"No resolvable bootstrap urls given in bootstrap.servers\", not retried), the clients "
               "already running reconnect. The JVM caches a failed lookup for networkaddress.cache.negative.ttl (10 s "
               "in java.security) and hands it to every client of the process: a lower value (2 to 5 s) shortens the "
               "impact of a short outage. With networkaddress.cache.negative.ttl set in java.security, "
               "-Dsun.net.inetaddr.negative.ttl is ignored: override it with -Djava.security.properties=<file>"},
    # librdkafka (C/C++, Python, Go, .NET, JavaScript clients) logs a FAIL when the broker closes an idle connection
    # (connections.max.idle.ms): "Disconnected (after 600013ms in state UP)". Before connection_refused
    {"name": "client_idle_disconnect", "severity": "low", "category": "Network Issues",
     "pattern": r"Disconnected \(after \d{5,}ms in state UP",
     "title": "💤 Idle connection closed by the broker",
     "advice": "usually harmless: the broker closes a connection idle for connections.max.idle.ms (10 minutes by "
               "default) and librdkafka reconnects when it needs it; log.connection.close=false silences it. A "
               "disconnection a few ms after connecting is not this one: look at security.protocol and the TLS / SASL "
               "settings"},
    # librdkafka: "Disconnected while requesting ApiVersion: might be caused by incorrect security.protocol configuration
    # (connecting to a SSL listener?)", "Disconnected: verify that security.protocol is correctly configured, broker
    # might require SASL authentication"
    {"name": "client_security_protocol", "severity": "high", "category": "Network Issues",
     "pattern": r"incorrect security\.protocol|verify that security\.protocol|broker might require SASL authentication"
                r"|connecting to a SSL listener|Unexpected handshake request with client mechanism"
                # a TLS or HTTP client on a PLAINTEXT listener: the broker reads its first bytes as a size (369296128 is
                # the start of a TLS record 0x16030100, 1195725856 "GET ")
                r"|Invalid receive \(size = \d{7,}",
     "title": "🛂 Wrong security.protocol or SASL mechanism",
     "advice": "the client does not speak the protocol of the listener: PLAINTEXT on an SSL or SASL listener, or another "
               "SASL mechanism: check security.protocol, sasl.mechanism(s) and the port against the listeners of the "
               "brokers (playground debug tcp-dump shows the handshake)"},
    # a producer record not acknowledged in time: librdkafka "Local: Message timed out" (message.timeout.ms), Java
    # "Expiring 3 record(s) for orders-0: 120001 ms has passed since batch creation" (delivery.timeout.ms). Before timeout
    {"name": "client_message_timed_out", "severity": "high", "category": "Kafka Issues",
     "pattern": r"Message timed out|MSG_TIMED_OUT|Expiring \d+ record\(s\) for",
     "title": "⌛ Records not delivered in time",
     "advice": "the producer gave up on records not acknowledged within message.timeout.ms (librdkafka) / "
               "delivery.timeout.ms (Java): records are lost unless the application retries them. The cause comes "
               "before it: brokers unreachable (connection errors), no leader for the partition, authorization, or a "
               "cluster too slow for the load"},
    # Java producer "Topic orders not present in metadata after 60000 ms." (max.block.ms), the same words in the Rust client
    {"name": "client_topic_not_in_metadata", "severity": "high", "category": "Kafka Issues",
     "pattern": r"not present in metadata after",
     "title": "🗺️ Topic not found in the metadata",
     "advice": "the producer did not get the partitions of the topic within max.block.ms: the topic does not exist and "
               "is not auto-created, the principal cannot describe it (ACL), or the brokers are unreachable or "
               "bootstrap.servers points at another cluster. Look at the connection errors before it, then playground "
               "topic describe --topic <topic>"},
    # an unknown or invalid client property: librdkafka "No such configuration property: \"bogus.property\"", "Invalid value
    # \"x\" for configuration property \"acks\"", Java ConfigException
    {"name": "client_invalid_config", "severity": "high", "category": "Kafka Issues",
     "pattern": r"No such configuration property|Invalid value .{0,200} for configuration property"
                r"|ConfigException: (?:Invalid value|Missing required configuration)",
     "title": "⚙️ Invalid client configuration",
     "advice": "a property is unknown to this client, misspelled, or has an invalid value: librdkafka clients (C/C++, "
               "Python, Go, .NET, JavaScript) do not take the Java-only properties, and a client too old does not know "
               "the newer ones: check the key and its values in the CONFIGURATION.md of the librdkafka version of the "
               "client (https://github.com/confluentinc/librdkafka/blob/master/CONFIGURATION.md)"},
    # librdkafka "Local: Queue full" / BufferError (queue.buffering.max.messages / .kbytes), Java BufferExhaustedException
    {"name": "client_queue_full", "severity": "medium", "category": "Kafka Issues",
     "pattern": r"Local: Queue full|QUEUE_FULL|BufferExhaustedException|Failed to allocate memory within the configured max"
                r" blocking time",
     "title": "📥 Producer buffer full",
     "advice": "the application produces faster than the records are delivered: brokers slow or unreachable, or "
               "delivery reports not served (librdkafka: call poll() / flush() regularly). Look at the errors before it, "
               "then queue.buffering.max.messages / queue.buffering.max.kbytes (librdkafka) or buffer.memory / "
               "max.block.ms (Java)"},
    # librdkafka "Application maximum poll interval (300000ms) exceeded by 123ms" (MAX_POLL_EXCEEDED), Java "consumer poll
    # timeout has expired", CommitFailedException ("…longer than the configured max.poll.interval.ms…"). Not the key alone:
    # the client config check "Configuration 'connections.max.idle.ms' with value '540000' is lower than configuration
    # 'max.poll.interval.ms'…" (Control Center logs it 48 times at startup) is not a consumer leaving its group
    {"name": "client_max_poll_exceeded", "severity": "high", "category": "Kafka Issues",
     "pattern": r"maximum poll interval|MAX_POLL_EXCEEDED|poll timeout has expired"
                r"|longer than the configured max\.poll\.interval\.ms",
     "title": "🐢 Consumer left its group: max.poll.interval.ms exceeded",
     "advice": "the application took longer than max.poll.interval.ms between two polls (slow processing, a blocking "
               "call, a GC pause): the consumer leaves the group, its partitions are reassigned and its commits fail. "
               "Process faster or in smaller batches (max.poll.records in Java), or raise max.poll.interval.ms"},
    # errors.tolerance=none (the default): the first record that fails in a stage kills the task
    {"name": "tolerance_exceeded", "severity": "high", "category": "Connect Issues",
     "pattern": r"Tolerance exceeded in error handler",
     "title": "🧯 errors.tolerance exceeded",
     "advice": "a record failed in the stage named by the exception (Executing stage 'VALUE_CONVERTER', 'KEY_CONVERTER', "
               "'TRANSFORMATION', 'TASK_PUT') and errors.tolerance=none (the default) stops the task: fix the cause in the "
               "chain below it, or set errors.tolerance=all with a dead letter queue (errors.deadletterqueue.topic.name, "
               "sink connectors) and read it with playground topic dlq inspect; playground connector smt test replays an "
               "SMT on a record"},
    # a transactional producer replaced by a newer one with the same transactional.id (Connect exactly-once source,
    # a transactional application), or its transaction aborted by the broker
    {"name": "producer_fenced", "severity": "high", "category": "Kafka Issues",
     "pattern": r"ProducerFencedException|InvalidProducerEpochException|Producer attempted an operation with an old epoch"
                r"|There is a newer producer with the same transactionalId",
     "title": "🤺 Producer fenced (transactions, exactly-once)",
     "advice": "another producer with the same transactional.id took over (the same task running on two workers after a "
               "rebalance, a zombie instance), or the transaction outlived transaction.timeout.ms and the broker aborted "
               "it: check that the task or application does not run twice, and the transaction timeout against the time "
               "a transaction takes; playground broker transactions list and playground broker transactions find-hanging show the open and hanging ones"},
    # a source task whose producer did not acknowledge its records within offset.flush.timeout.ms
    {"name": "offset_flush_timeout", "severity": "medium", "category": "Connect Issues",
     "pattern": r"Failed to flush, timed out while waiting for producer to flush outstanding"
                r"|Failed to commit offsets.{0,120}timed out|Timed out while waiting for producer to flush",
     "title": "⏳ Source offsets not committed in time",
     "advice": "the producer of the source task had records not yet acknowledged when offset.flush.timeout.ms (5 s by "
               "default) ended: brokers slow or unreachable, or bursts larger than the producer sends in that time. The "
               "records are sent again after a restart (duplicates): look at the producer errors around it, then raise "
               "offset.flush.timeout.ms or tune producer.override.batch.size / linger.ms"},
    # group membership lost or moving: a member joined or left, a session timeout, the coordinator moved
    {"name": "group_rebalance", "severity": "medium", "category": "Kafka Issues",
     "pattern": r"RebalanceInProgressException|UnknownMemberIdException|REBALANCE_IN_PROGRESS|UNKNOWN_MEMBER_ID"
                r"|Group coordinator .{0,120} is unavailable or invalid|Attempt to heartbeat failed since group is rebalancing"
                r"|CommitFailedException",
     "title": "🔁 Group rebalances or coordinator lost",
     "advice": "the consumer group (or the group of the Connect workers) rebalanced while its members worked, or its "
               "coordinator moved: each rebalance pauses the processing and can fail the commits. Count them "
               "(playground connector history for Connect, playground streams status for Kafka Streams) and look at the "
               "members that join and leave, session.timeout.ms, heartbeat.interval.ms and max.poll.interval.ms"},
    # an external system or a cloud API over its rate limit
    {"name": "throttled", "severity": "medium", "category": "Network Issues",
     "pattern": r"ThrottlingException|Rate exceeded|429 Too Many Requests|TooManyRequests|http (?:status|code|error)[ :=]*429"
                r"|Status code\s*:?\s*429|es_rejected_execution_exception|\bSlowDown\b|RequestLimitExceeded"
                r"|REQUEST_LIMIT_EXCEEDED",
     "title": "🚦 Throttled by the external system",
     "advice": "the external system or the cloud API refused requests over its rate limit (HTTP 429, AWS "
               "ThrottlingException / SlowDown, Elasticsearch es_rejected_execution, Salesforce REQUEST_LIMIT_EXCEEDED): "
               "the connector retries. Lower tasks.max or the batch size, raise the retry backoff of the connector, or ask "
               "for a higher quota"},
    # a task or connector still running after task.shutdown.graceful.timeout.ms (rebalance, restart, config update)
    {"name": "graceful_stop_failed", "severity": "medium", "category": "Connect Issues",
     "pattern": r"Graceful stop of (?:task|connector) .{0,160} failed|Failed to stop (?:task|connector) .{0,120} in time",
     "title": "🛑 Task or connector did not stop in time",
     "advice": "a task or a connector did not stop within task.shutdown.graceful.timeout.ms (5 s by default): it may still "
               "run in the background (a duplicate task, connections or locks held). A thread dump shows where it is "
               "blocked: playground debug thread-dump, then playground analyze thread-dump"},
    # CreateTopics / AlterConfigs refused by a policy of the cluster (create.topic.policy.class.name, Confluent Cloud limits)
    {"name": "policy_violation", "severity": "medium", "category": "Kafka Issues",
     "pattern": r"PolicyViolationException|POLICY_VIOLATION",
     "title": "🚧 Request refused by a broker policy",
     "advice": "a topic creation or a config change broke a policy of the cluster (partitions, retention, cleanup.policy, "
               "replication factor, Confluent Cloud limits): the exception names the setting. Use an allowed value "
               "(topic.creation.* of a source connector, the internal topics of Connect)"},
    # requests sent to a broker that no longer leads the partition
    {"name": "not_leader", "severity": "low", "category": "Kafka Issues",
     "pattern": r"NotLeaderOrFollowerException|NOT_LEADER_OR_FOLLOWER|NotLeaderForPartitionException|NOT_LEADER_FOR_PARTITION",
     "title": "👑 Partition leadership changed",
     "advice": "the client sent a request to a broker that no longer leads the partition: expected during a broker "
               "restart, a rolling upgrade or a reassignment, the client retries. Many of them over a long period point "
               "at brokers restarting or leaders moving: playground broker health, playground topic describe"},
    {"name": "connection_refused", "severity": "high", "category": "Network Issues",
     "pattern": r"connection refused|Connection reset by peer|NoRouteToHostException|No route to host|Broken pipe"
                r"|ECONNREFUSED|ECONNRESET|EHOSTUNREACH|(?<!\d)\d{1,5}/\d{1,5} brokers are down|ALL_BROKERS_DOWN"
                r"|connect timed out|Connection to node -?\d+ .{0,200} could not be established|Communications link failure",
     "title": "🔌 Connection failure",
     "advice": "the host is down or unreachable, or nothing listens on the port: check the host, port and network "
               "(playground debug tcp-dump shows what goes over the wire)"},
    {"name": "timeout", "severity": "medium", "category": "Network Issues",
     "pattern": r"\btimed out\b|deadline exceeded|i/o timeout|TimeoutException",
     "title": "⏱️ Timeouts",
     "advice": "the other side is slow or unreachable: look at the first occurrence, and at what happened just before"},
    {"name": "volume_mount", "severity": "high", "category": "Volume Issues",
     "pattern": r"failed to mount|MountVolume\.SetUp failed|Unable to attach or mount volumes",
     "title": "🧷 Volume mount failure",
     "advice": "Kubernetes cannot attach or mount a volume of the pod: look at the events of the pod and of its "
               "PersistentVolumeClaim"},
    {"name": "operator_error", "severity": "medium", "category": "Operator Issues",
     "pattern": r"reconcile error|Failed to reconcile|Reconciler error|operator error", "hint": False},
    {"name": "schema_registry_error", "severity": "medium", "category": "Schema Registry Issues",
     "pattern": r"SchemaRegistryException|RestClientException",
     "title": "📐 Schema Registry error",
     "advice": "a call to the Schema Registry failed: check its url and credentials in the converter or client "
               "(playground schema describe --subject <s> for the subject, playground schema history for its changes)"},
    {"name": "ksqldb_error", "severity": "medium", "category": "KsqlDB Issues",
     "pattern": r"\bKsqlException\b|KSQL_PARSING_EXCEPTION|KsqlStatementException", "hint": False},
    {"name": "connect_error", "severity": "medium", "category": "Connect Issues",
     "pattern": r"\bConnectException\b|\bRetriableException\b|connector .{0,40}is in FAILED state|WorkerSinkTask"
                r"|WorkerSourceTask",
     "hint": False},
    {"name": "controlcenter_error", "severity": "medium", "category": "Control Center Issues",
     "pattern": r"ControlCenter.{0,40}Exception|c3 .{0,40}failed to", "hint": False},
    {"name": "rest_proxy_error", "severity": "medium", "category": "REST Proxy Issues",
     "pattern": r"kafka-rest.{0,80}exception|kafkarest.{0,80}exception|REST API.{0,40}failed", "hint": False},
    {"name": "finalizer_stuck", "severity": "medium", "category": "Finalizer Issues",
     "pattern": r"finalizer.{0,80}blocking|deletion.{0,40}blocked", "hint": False},
    {"name": "reconcile_blocked", "severity": "low", "category": "Reconciliation Blocked",
     "pattern": r"block-reconcile|reconciliation.{0,40}blocked", "hint": False},
    {"name": "kafka_error", "severity": "medium", "category": "Kafka Issues",
     "pattern": r"org\.apache\.kafka\.\S+Exception|\bKafkaException\b", "hint": False},
    {"name": "java_error", "severity": "medium", "category": "Application Errors",
     "pattern": r"java\.lang\.NullPointerException|java\.io\.IOException|java\.lang\.IllegalStateException"
                r"|java\.lang\.IllegalArgumentException",
     "hint": False},
]

_SEVERITY_RANK = {"critical": 0, "high": 1, "medium": 2, "low": 3}

# order of the known causes in the log report (its verdict and findings follow it), the other titles come after, in
# declaration order
HINT_ORDER = [
    "💥 OutOfMemoryError", KILLED_TASK_TITLE, "🧯 errors.tolerance exceeded", "🧩 Plugin not found", "📦 Class loading error",
    "🔑 Authentication failure", "☁️ Cloud credentials or permission refused", "🚫 Authorization failure", "🔐 TLS handshake failure", "🧲 Unknown magic byte",
    "🔍 Schema id not found", "🛡️ Incompatible schema refused", "📛 Subject not found",
    "🔀 Serialization or conversion error", "🛂 Wrong security.protocol or SASL mechanism", "🌐 Host name not resolved (DNS)",
    "🔌 Connection failure",
    "⚙️ Invalid client configuration", "⌛ Records not delivered in time", "🗺️ Topic not found in the metadata", "🐢 Consumer left its group: max.poll.interval.ms exceeded", "🔁 Group rebalances or coordinator lost", "📥 Producer buffer full",
    "🤺 Producer fenced (transactions, exactly-once)", "⏳ Source offsets not committed in time", "🚦 Throttled by the external system",
    "🛑 Task or connector did not stop in time", "⏱️ Timeouts", "📏 Record too large", "🧹 Clients aborted while a task stopped",
    "❓ Unknown topic or partition", "⏮️ Offset out of range", "🚧 Request refused by a broker policy", "👑 Partition leadership changed",
]


# what to read about a known cause, by title: one or more Confluent support knowledge-base articles ("kb": url,
# "kb_title") and / or a docs.confluent.io page ("docs"). A list when the cause has several articles: an article with a
# "pattern" (case-insensitive regex) is shown only when a record of the cause matches it (a variant: ORA-01017 among
# the authentication failures, the S3 tiered storage among the cloud credentials), before the general ones,
# MAX_KB_ARTICLES at most. A general article with "fallback": True is shown only when no variant matched.
# Only URLs found in the knowledge base (support.confluent.io articles for signed-in users), never built by hand: a
# cause without a good article has no entry
KB = "https://support.confluent.io/hc/en-us/articles/"
LINKS = {
    "📜 License error": {"kb": KB + "16805773531284-What-s-causing-Invalid-License-Failed-to-start-Error-during-startup-of-an-commercial-Confluent-Platform-component",
        "kb_title": "\"Invalid License! - Failed to start\" at startup"},
    "💾 Storage failure": {"kb": KB + "30001064019092-How-to-bypass-LogDirFailureHandler-all-log-dirs-in-logs-have-failed-error-on-broker-startup",
        "kb_title": "\"all log dirs have failed\" on broker startup"},
    "🗝️ Empty or unreadable truststore": {"kb": KB + "19234809054484-How-to-investigate-trustAnchors-parameter-must-be-non-empty-Error-on-Kafka-Clients",
        "kb_title": "\"trustAnchors parameter must be non-empty\""},
    "🔐 TLS handshake failure": {"kb": KB + "360039950551-How-to-investigate-no-subject-alternative-names-matching-IP-address-during-SSL-Connection",
        "kb_title": "\"no subject alternative names matching IP address\""},
    "☁️ Cloud credentials or permission refused": [
        {"kb": KB + "34060762750868-What-s-causing-AWS-S3-Source-Sink-connectors-to-fail-with-Your-AWS-Access-Key-API-key-is-invalid-It-might-have-been-deleted-or-its-associated-IAM-role-or-user-is-deleted-Message",
         "kb_title": "AWS S3 connectors: \"Your AWS Access Key API key is invalid\"",
         "pattern": r"InvalidAccessKeyId|AWS Access Key|security token included in the request is invalid"},
        {"kb": KB + "13635998738196-How-to-bypass-Access-Denied-error-with-tiered-storage-enabled-kafka-cluster",
         "kb_title": "\"Access Denied\" on brokers with Tiered Storage (S3)", "pattern": r"kafka\.tier\.|TierObjectStore"},
    ],
    "🪪 MDS / RBAC token error": {"kb": KB + "360039432052-How-to-handle-JWT-rejected-due-to-invalid-signature-messages-with-RBAC",
        "kb_title": "JWT rejected due to invalid signature with RBAC"},
    "🚫 Authorization failure": [
        {"kb": KB + "20204008043668-User-is-denied-operation-Write-on-Subject",
         "kb_title": "Schema Registry: \"User is denied operation Write on Subject\"", "pattern": r"denied operation Write on Subject"},
        {"kb": KB + "48876768294676-How-to-handle-failed-Schema-creation-using-Confluent-for-Kubernetes-with-40301-ReadCompatibility-RBAC-error",
         "kb_title": "CFK Schema creation fails with 40301 ReadCompatibility (RBAC)", "pattern": r"denied operation ReadCompatibility"},
        {"kb": KB + "12299285647252-How-to-bypass-error-code-40301-when-using-schema-validation-feature",
         "kb_title": "Error code 40301 with broker-side schema validation", "pattern": r"User is denied operation on this server"},
        {"kb": KB + "115004560843-What-to-check-if-the-Confluent-Metrics-Reporter-not-working",
         "kb_title": "Confluent Metrics Reporter not working (_confluent-metrics ACLs)", "pattern": r"_confluent-metrics"},
        {"kb": KB + "360057093932-How-to-bypass-licensed-connector-fails-to-start-with-TopicAuthorizationException",
         "kb_title": "Licensed connector fails with TopicAuthorizationException (_confluent-command)", "pattern": r"_confluent-command"},
        {"kb": KB + "13193806015252-How-to-fix-the-error-Group-authorization-failed-FindCoordinator-response-error-Group-authorization-failed",
         "kb_title": "\"FindCoordinator response error: Group authorization failed\"", "pattern": r"GroupAuthorizationException|Group authorization failed"},
        {"kb": KB + "360059585631-What-ACL-s-or-Rolebindings-are-required-if-working-with-idempotent-transactional-producers",
         "kb_title": "ACLs or role bindings of idempotent / transactional producers", "pattern": r"TransactionalIdAuthorizationException|Transactional Id authorization failed"},
        {"kb": KB + "13813790598164-What-s-causing-ClusterAuthorizationException-after-upgrading-producers-to-Apache-Kafka-3-0",
         "kb_title": "ClusterAuthorizationException of producers since Apache Kafka 3.0 (idempotence)", "pattern": r"ClusterAuthorizationException|Cluster authorization failed"},
        {"kb": KB + "4417243864980-What-can-cause-authorization-exceptions-when-accessing-a-Topic-in-Confluent-Cloud",
         "kb_title": "Authorization exceptions on a topic of Confluent Cloud", "pattern": r"TopicAuthorizationException|TOPIC_AUTHORIZATION_FAILED|Not authorized to access topics"},
        {"kb": KB + "29997697793684-What-ACLs-are-required-for-a-Kafka-Connect-Cluster-connecting-to-Confluent-Cloud",
         "kb_title": "ACLs required by a Connect cluster on Confluent Cloud", "fallback": True},
    ],
    "🧬 Not enough replicas": {"kb": KB + "360046772492-How-to-interpret-NotEnoughReplicasException-within-Kafka-Broker-Logfile",
        "kb_title": "How to interpret NotEnoughReplicasException"},
    "🦓 ZooKeeper session error": {"kb": KB + "45279338995348-Why-does-a-Kafka-broker-log-Client-session-timed-out-have-not-heard-from-server-in-XXms-and-what-causes-ZooKeeper-session-timeouts",
        "kb_title": "What causes ZooKeeper session timeouts"},
    "🧩 Plugin not found": {"kb": KB + "360023070471-How-to-bypass-a-missing-class-error-while-starting-up-a-connector",
        "kb_title": "A missing class error while starting a connector"},
    "📦 Class loading error": {"kb": KB + "17808375385876-How-to-troubleshoot-ClassNotFoundException-NoClassDefFoundError-or-ClassCastException-exceptions-with-verbose-class",
        "kb_title": "ClassNotFoundException / NoClassDefFoundError with -verbose:class"},
    "🧟 Kafka Streams: producer fenced (exactly-once)": {"kb": KB + "360058606991-How-to-avoid-ProducerFencedException-within-kafka-streams",
        "kb_title": "How to avoid ProducerFencedException in Kafka Streams"},
    "💀 Kafka Streams: stream thread died": {"kb": KB + "360039499492-How-to-detect-failed-threads-in-Kafka-Streams",
        "kb_title": "How to detect failed threads in Kafka Streams"},
    "🧲 Unknown magic byte": {"kb": KB + "360042865291-What-s-causing-Unknown-magic-byte-error-when-consuming-avro-data",
        "kb_title": "What's causing \"Unknown magic byte\"",
        "docs": "https://docs.confluent.io/platform/current/schema-registry/fundamentals/serdes-develop/index.html"},
    "🔍 Schema id not found": [
        {"kb": KB + "23958101841172-What-can-cause-Schema-Not-Found-Error-although-the-schema-IDs-exists-on-Schema-Registry",
         "kb_title": "\"Schema not found\" although the schema id exists"},
        {"kb": KB + "29396031747604-How-to-recover-Hard-Deleted-Schemas-in-Schema-Registry",
         "kb_title": "How to recover hard-deleted schemas"},
    ],
    "🛡️ Incompatible schema refused": {"kb": KB + "360057560832-How-to-fix-Schema-is-incompatible-with-an-earlier-schema-for-subject",
        "kb_title": "\"Schema is incompatible with an earlier schema\""},
    "📏 Record too large": {"kb": KB + "360024032811-How-to-handle-large-messages-with-Kafka",
        "kb_title": "How to handle large messages with Kafka"},
    "⏮️ Offset out of range": {"kb": KB + "23123974254996-What-does-Error-Broker-Offset-out-of-range-mean",
        "kb_title": "What \"Offset out of range\" means"},
    "💤 Idle connection closed by the broker": {"kb": KB + "360041071431-How-to-fix-X-X-brokers-are-down-on-idle-consumer-producer",
        "kb_title": "\"X/X brokers are down\" on an idle client"},
    "🛂 Wrong security.protocol or SASL mechanism": {"kb": KB + "360052182012-What-can-cause-Timed-out-waiting-for-a-node-assignment-Java-Client-and-CLI-Exceptions",
        "kb_title": "\"Timed out waiting for a node assignment\""},
    "⌛ Records not delivered in time": {"kb": KB + "32304589191444-How-to-resolve-the-TimeoutException-expiring-records-for-topic-producer-error",
        "kb_title": "\"TimeoutException: expiring records for topic\""},
    "📥 Producer buffer full": {"kb": KB + "360053146092-How-to-bypass-BufferError-Local-Queue-full-in-librdkafka-producers",
        "kb_title": "\"Local: Queue full\" in librdkafka producers"},
    "🐢 Consumer left its group: max.poll.interval.ms exceeded": {"kb": KB + "38115693778068-What-s-causing-Consumer-lag-and-or-Commit-of-offsets-timing-out-with-Consumers-or-Sink-Connectors",
        "kb_title": "Consumer lag and offset commits timing out (sink connectors)"},
    "⏳ Source offsets not committed in time": {"kb": KB + "360039220372-How-to-deal-with-failed-to-flush-timeouts-in-Kafka-Connect-Source-Connector",
        "kb_title": "\"failed to flush\" timeouts of source connectors"},
    "🔁 Group rebalances or coordinator lost": {"kb": KB + "15522504533652-What-s-causing-Consumer-Rebalance-taking-a-long-time-to-complete",
        "kb_title": "Consumer rebalances taking a long time"},
    "👑 Partition leadership changed": {"kb": KB + "4411550541716-How-to-diagnose-NotLeaderOrFollowerException",
        "kb_title": "How to diagnose NotLeaderOrFollowerException"},
    "💥 OutOfMemoryError": [
        {"kb": KB + "17288051968916-How-to-bypass-java-lang-OutOfMemoryError-unable-to-create-native-thread",
         "kb_title": "\"OutOfMemoryError: unable to create native thread\"", "pattern": r"unable to create native thread"},
        {"kb": KB + "360040326831-JVM-runs-into-OOM-if-Java-client-uses-a-SSL-SASL-SSL-port-without-setting-the-security-protocol",
         "kb_title": "OOM of a Java client on an SSL / SASL_SSL port without security.protocol",
         "pattern": r"OutOfMemoryError: Java heap space[\s\S]{0,3000}(?:MemoryPool|NetworkReceive\.readFrom)"},
        {"kb": KB + "19410224820756-How-to-bypass-java-lang-OutOfMemoryError-thrown-by-UncaughtExceptionHandler",
         "kb_title": "\"OutOfMemoryError thrown from the UncaughtExceptionHandler\" (heap size)", "pattern": r"thrown from the UncaughtExceptionHandler"},
        {"kb": KB + "35064226035348-What-can-cause-Kubernetes-pod-continuously-restart-after-deploying-a-new-producer-application",
         "kb_title": "Kubernetes pod restarting: OOMKilled (exit code 137)", "pattern": r"OOMKilled"},
        {"kb": KB + "360020979972-How-to-address-out-of-memory-due-to-maximum-mmap-count-exceeded",
         "kb_title": "Out of memory: maximum mmap count exceeded", "pattern": r"max_map_count|Map failed"},
        {"kb": KB + "4532705835028-How-to-enable-verbose-GC-Garbage-Collection-logging-and-create-a-heapdump-on-out-of-memory-exceptions",
         "kb_title": "Verbose GC logging and a heap dump on OutOfMemoryError"},
    ],
    "🧨 A connector task was killed": {"kb": KB + "21305161068820-How-to-restart-Kafka-connectors-tasks",
        "kb_title": "How to restart connectors and tasks (after fixing the exception)"},
    "🧯 errors.tolerance exceeded": [
        {"kb": KB + "360041511391-Error-Handling-Behaviour-in-JDBC-Source-Sink-Connector-And-other-Sink-Connectors",
         "kb_title": "Error handling of sink connectors: what errors.tolerance and the DLQ cover"},
        {"kb": KB + "360031115091-How-to-skip-messages-in-Kafka-Connect-or-reset-a-connector-to-the-earliest-offset-for-sink-connectors",
         "kb_title": "How to skip messages or reset the offsets of a sink connector"},
    ],
    "🔑 Authentication failure": [
        {"kb": KB + "36653405787284-What-can-cause-SASL-authentication-error-Authentication-failed-Error-in-librdkafka-clients",
         "kb_title": "\"SASL authentication error: Authentication failed\" (librdkafka)", "pattern": r"SASL authentication error"},
        {"kb": KB + "4814459539348-How-to-fix-LDAP-Connection-Reset-exceptions",
         "kb_title": "LDAP \"Connection reset\" behind \"Invalid username or password\"", "pattern": r"Failed to obtain user DN"},
        {"kb": KB + "34412366383508-How-to-bypass-Could-not-connect-to-the-database-Error-using-Oracle-CDC-source-connector-on-Confluent-Cloud",
         "kb_title": "Oracle CDC: \"Could not connect to the database\" (ORA-01017)", "pattern": r"ORA-01017"},
        {"kb": KB + "36389454770836-What-s-causing-The-connector-failed-since-it-cannot-open-database-DB-name-due-to-login-failed-using-Microsoft-Sql-Server-Source-Connector-on-Confluent-Cloud",
         "kb_title": "SQL Server: \"cannot open database ... login failed\"", "pattern": r"Login failed for user"},
        {"kb": KB + "33949564732948-What-s-causing-unable-to-connect-to-the-database-due-to-a-connection-issue-Error-using-PostgreSQL-CDC-Source-V2-Connector-on-Confluent-Cloud",
         "kb_title": "PostgreSQL CDC: \"password authentication failed\"", "pattern": r"password authentication failed for user"},
        {"kb": KB + "23119096873876-How-to-configure-Confluent-Supported-Libraries-to-use-Schema-Registry-with-an-API-Key",
         "kb_title": "Schema Registry API key of the clients (\"Unauthorized; error code: 401\")", "pattern": r"Unauthorized; error code:? ?401"},
        {"kb": KB + "27052383612948-What-to-check-if-a-connector-on-Confluent-Cloud-fails-with-authentication-issues",
         "kb_title": "What to check when a Confluent Cloud connector fails to authenticate", "fallback": True},
    ],
    "🔀 Serialization or conversion error": {"kb": KB + "360052951911-What-is-JsonConverter-s-schemas-enable-configuration-responsible-for-in-Kafka-Connect",
        "kb_title": "What JsonConverter schemas.enable does", "pattern": r"schemas\.enable|JsonConverter"},
    "🔌 Connection failure": [
        {"kb": KB + "4764336830484-What-might-cause-intermittent-Connection-refused-error-when-running-multiple-Connect-worker-nodes",
         "kb_title": "\"Connection refused\" between Connect workers (rest.advertised.host.name)", "pattern": r"forward(?:ing)? REST request"},
        {"kb": KB + "360052984771-What-are-potential-causes-of-transient-network-issues-on-Confluent-Cloud",
         "kb_title": "Transient network issues on Confluent Cloud", "pattern": r"terminated during authentication"},
    ],
    "🌐 Host name not resolved (DNS)": {"kb": KB + "4408266460308-How-to-resolve-ConfigException-No-resolvable-bootstrap-urls-given-in-bootstrap-servers",
        "kb_title": "\"ConfigException: No resolvable bootstrap urls given in bootstrap.servers\"", "pattern": r"No resolvable bootstrap urls"},
    "⚙️ Invalid client configuration": {"kb": KB + "20921646333716-What-might-cause-Invalid-value-for-configuration-bootstrap-servers-Empty-list-Error",
        "kb_title": "\"Invalid value [] for configuration bootstrap.servers: Empty list\"", "pattern": r"bootstrap\.servers: Empty list"},
    "🗺️ Topic not found in the metadata": {"kb": KB + "360054951292-How-to-bypass-Producer-throws-TimeoutException-while-performing-a-rolling-restart-on-the-Kafka-brokers",
        "kb_title": "Producer TimeoutException \"not present in metadata\" (max.block.ms)"},
    "🚦 Throttled by the external system": {"kb": KB + "360061739912-How-to-reduce-S3-Sink-connector-rate-to-avoid-AWS-rate-limit",
        "kb_title": "How to reduce the rate of the S3 sink connector (SlowDown)", "pattern": r"SlowDown|reduce your request rate"},
    "🛑 Task or connector did not stop in time": {"kb": KB + "6254480439316-What-s-causing-JDBC-connector-leaking-connections-with-database",
        "kb_title": "Graceful stop failed: connections left open (task.shutdown.graceful.timeout.ms)"},
    "⏱️ Timeouts": [
        {"kb": KB + "35776254625812-How-to-handle-TimeoutException-while-awaiting-InitProducerId",
         "kb_title": "TimeoutException while awaiting InitProducerId", "pattern": r"awaiting InitProducerId"},
        {"kb": KB + "360053074272-What-s-causing-Kafka-client-request-disconnect-or-timeout-errors",
         "kb_title": "Kafka client request disconnects or timeouts", "pattern": r"org\.apache\.kafka|librdkafka|rdkafka|Disconnecting from node"},
    ],
    "❓ Unknown topic or partition": [
        {"kb": KB + "360052618911-What-s-causing-UNKNOWN-TOPIC-OR-PARTITION-in-Connect-Worker-Logs-after-a-source-connector-deletion",
         "kb_title": "UNKNOWN_TOPIC_OR_PARTITION after a source connector deletion", "pattern": r"connector-producer-"},
        {"kb": KB + "40464792724756-How-to-handle-Executing-consumer-group-command-failed-due-to-Error-using-kafka-consumer-groups",
         "kb_title": "kafka-consumer-groups: \"Executing consumer group command failed\"", "pattern": r"Executing consumer group command failed"},
    ],
    "🚧 Request refused by a broker policy": [
        {"kb": KB + "35697098367380-How-to-address-PolicyViolationException-Unable-to-perform-excessively-large-batch-operation-Error",
         "kb_title": "\"Unable to perform excessively large batch operation\"", "pattern": r"excessively large batch operation"},
        {"kb": KB + "360022670532-How-to-bypass-Control-Center-max-message-bytes-exceeded-maximum-limit-error-when-connecting-to-Confluent-Cloud",
         "kb_title": "Topic config over the Confluent Cloud limit (\"exceeded max limit\")", "pattern": r"exceeded max limit"},
    ],
    "🗳️ KRaft quorum error": {"kb": KB + "41381243741588-How-resolve-Renouncing-the-leadership-due-to-a-metadata-log-event-Error-using-KRaft",
        "kb_title": "KRaft: \"Renouncing the leadership due to a metadata log event\"", "pattern": r"Renouncing the leadership"},
    "🧷 Volume mount failure": {"kb": KB + "13538321968660-What-s-causing-Kafka-roll-get-blocked-with-Confluent-for-Kubernetes-2-5",
        "kb_title": "CFK: Kafka roll blocked, volume mount of a missing secret", "pattern": r"secret .{0,160}not found"},
    "📐 Schema Registry error": [
        {"kb": KB + "6778965930260-What-might-cause-Schema-Registry-timeout-while-registering-new-schema-using-Schema-Linking-and-RBAC",
         "kb_title": "\"Register operation timed out\" (Schema Linking, RBAC)", "pattern": r"Register operation timed out"},
        {"kb": KB + "13916684245268-How-to-use-Schema-Validation-with-Kafka-REST-Proxy",
         "kb_title": "Record rejected by RecordSchemaValidator (schema validation)", "pattern": r"RecordSchemaValidator"},
        {"kb": KB + "30831560767124-JSON-Schema-regression-on-Confluent-Platform-7-6-1",
         "kb_title": "\"Invalid JSON Schema; error code: 42201\" since CP 7.6.1", "pattern": r"Invalid JSON Schema"},
        {"kb": KB + "25462925027860-How-to-troubleshoot-Schema-Exporter-42205-errors-existing-subjects-and-overwrite-schema-ID-conflicts",
         "kb_title": "Schema Exporter: error code 42205", "pattern": r"error code:? ?42205"},
    ],
}


MAX_KB_ARTICLES = 3


def _select(entries, texts):
    """The entries whose pattern matches one of `texts` (the variants), then those without a pattern, except the
    "fallback" ones when a variant matched (a general article too far from the variants: Confluent Cloud only…)"""
    variants, general = [], []
    for entry in entries:
        pattern = entry.get("pattern")
        if not pattern:
            general.append(entry)
        elif any(re.search(pattern, t, re.IGNORECASE) for t in texts):
            variants.append(entry)
    return variants + [e for e in general if not (variants and e.get("fallback"))]


def links(title, texts=()):
    """What to read about the known cause `title`, whose records are `texts`: {"kb", "kb_title" (the first article),
    "kb_articles": [{"title", "url"}], "docs"} (the keys it has), or {}"""
    value = LINKS.get(title)
    if not value:
        return {}
    entries = value if isinstance(value, list) else [value]
    texts = list(texts)[:500]
    out = {}
    articles = [{"title": e.get("kb_title") or "knowledge base article", "url": e["kb"]}
                for e in _select(entries, texts) if e.get("kb")][:MAX_KB_ARTICLES]
    if articles:
        out.update(kb=articles[0]["url"], kb_title=articles[0]["title"], kb_articles=articles)
    docs = [e["docs"] for e in entries if e.get("docs")]
    if docs:
        out["docs"] = docs[0]
    return out


# the internal runbooks of Confluent support (GTS Confluence pages, support.confluent.io articles restricted to
# "Confluent - Internal") of the known causes, kept in the private reproduction-models repository, never here:
#     {"links": {"<known cause title>": [{"title": "...", "url": "https://...", "pattern": "optional regex"}]}}
# $PLAYGROUND_LOG_RUNBOOKS_FILE gives another file. Shown with a 🔒 in the text summary, the HTML report and --json
# (known_causes[].internal_links), never in the summary for a ticket (it can leave Confluent)
_PRIVATE_RUNBOOKS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "reproduction-models",
                                 "_miscellaneous", "log-analysis", "runbooks-internal.json")
_internal = None


def _load_internal():
    global _internal
    if _internal is None:
        _internal = {}
        path = os.environ.get("PLAYGROUND_LOG_RUNBOOKS_FILE") or _PRIVATE_RUNBOOKS
        if os.path.isfile(path):
            try:
                with open(path, encoding="utf-8") as f:
                    data = json.load(f)
                for title, items in (data.get("links") or {}).items():
                    if isinstance(items, list):
                        _internal[title] = [dict({"title": str(l.get("title") or l["url"]), "url": str(l["url"])},
                                                 **({"pattern": str(l["pattern"])} if l.get("pattern") else {}))
                                            for l in items if isinstance(l, dict) and str(l.get("url", "")).startswith("https://")]
            except (OSError, ValueError, AttributeError) as e:
                print(f"warning: cannot read the internal runbooks {path}: {e}", file=sys.stderr)
    return _internal


def internal_links(title, texts=()):
    """Internal runbooks of the known cause `title`, whose records are `texts`: [{"title", "url"}], [] without the
    private file. A runbook with a "pattern" only when a record matches it, as the KB articles"""
    texts = list(texts)[:500]
    return [{"title": l["title"], "url": l["url"]} for l in _select(_load_internal().get(title) or [], texts)]


def hints():
    """Known causes of the log report: (case-insensitive regex, SEVERITY, title, advice), one per title (the patterns of
    the entries sharing a title are joined, the highest severity wins), in the order of their first entry"""
    by_title = {}
    for c in KNOWN_CAUSES:
        if c.get("hint", True) is False:
            continue
        h = by_title.setdefault(c["title"], {"patterns": [], "severity": c["severity"], "advice": c["advice"]})
        h["patterns"].append(c["pattern"])
        if _SEVERITY_RANK[c["severity"]] < _SEVERITY_RANK[h["severity"]]:
            h["severity"] = c["severity"]
    titles = [t for t in HINT_ORDER if t in by_title] + [t for t in by_title if t not in HINT_ORDER]
    return [("(?i)" + "|".join(f"(?:{p})" for p in by_title[t]["patterns"]), by_title[t]["severity"].upper(), t,
             by_title[t]["advice"]) for t in titles]


def error_patterns():
    """Patterns of the CFK analyzer: {name: {pattern, severity, category}}, in declaration order"""
    return {c["name"]: {"pattern": c["pattern"], "severity": c["severity"], "category": c["category"]}
            for c in KNOWN_CAUSES}


# 🙈 records that say nothing about a problem, whatever the deployment: left out of the log report (counted, and listed
# in a 🙈 Known harmless section), unless --include-harmless. Keep it short and specific: a record hidden here is never
# seen by the reader, so no WARN that is a real misconfiguration in production (replication factor 1, a deprecated key)
HARMLESS = [
    (r"Unable to submit events without credentials \(io\.confluent\.telemetry",
     "telemetry events to Confluent without a Confluent Cloud API key: telemetry is not set up"),
    (r"No client metrics available in request, skipping export", "telemetry: no client metrics to export yet"),
    (r"Ignoring redefinition of existing telemetry label", "telemetry: a label defined twice"),
    (r"no telemetry exporters are enabled", "telemetry is not set up"),
    (r"A provider [\w.$]+ registered in SERVER runtime does not implement any provider interfaces applicable in the SERVER runtime",
     "Jersey: a REST resource registered as a provider at startup"),
    # a dedicated KRaft controller: Self-Balancing runs on the brokers ("DataBalancer is disabled -- ignoring" on the same node)
    (r"Bootstrap server endpoint was not provided in engine initialization context",
     "Self-Balancing started on a KRaft controller node, which has no client listener (the balancer runs on the brokers)"),
    (r"but DataBalancer is disabled -- ignoring", "Self-Balancing is disabled on this node"),
    (r"Topic View deletion guard disabled because endpointUrl is: null", "topic view deletion guard not configured"),
    (r"REST security extensions are not configured", "REST security plugins not installed (RBAC is not used)"),
    (r"Auto topic creation failed for _confluent-command with error 'TOPIC_ALREADY_EXISTS'",
     "an internal topic created by another component first, at startup"),
    (r"Processing exception handler is not enabled for the GlobalThread",
     "Kafka Streams recommendation logged by every Streams application of 4.1+ (Control Center included)"),
]
_HARMLESS_RX = [(re.compile(p), reason) for p, reason in HARMLESS]


def harmless(text):
    """the reason why the record `text` is known harmless, else None"""
    for rx, reason in _HARMLESS_RX:
        if rx.search(text):
            return reason
    return None
