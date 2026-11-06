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
    {"name": "dns_error", "severity": "high", "category": "Network Issues",
     "pattern": r"no such host|DNS resolution failed|dial tcp: lookup|UnknownHostException|Couldn't resolve server"
                r"|Failed to resolve '|Name or service not known|getaddrinfo (?:ENOTFOUND|EAI_AGAIN)",
     "title": "🔌 Connection failure",
     "advice": "the host is down, unreachable or the name does not resolve: check the host, port and network "
               "(playground debug tcp-dump shows what goes over the wire)"},
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
    # timeout has expired", CommitFailedException ("…longer than the configured max.poll.interval.ms…")
    {"name": "client_max_poll_exceeded", "severity": "high", "category": "Kafka Issues",
     "pattern": r"maximum poll interval|MAX_POLL_EXCEEDED|poll timeout has expired|max\.poll\.interval\.ms",
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
     "advice": "the host is down, unreachable or the name does not resolve: check the host, port and network "
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
    "🔀 Serialization or conversion error", "🛂 Wrong security.protocol or SASL mechanism", "🔌 Connection failure",
    "⚙️ Invalid client configuration", "⌛ Records not delivered in time", "🗺️ Topic not found in the metadata", "🐢 Consumer left its group: max.poll.interval.ms exceeded", "🔁 Group rebalances or coordinator lost", "📥 Producer buffer full",
    "🤺 Producer fenced (transactions, exactly-once)", "⏳ Source offsets not committed in time", "🚦 Throttled by the external system",
    "🛑 Task or connector did not stop in time", "⏱️ Timeouts", "📏 Record too large",
    "❓ Unknown topic or partition", "⏮️ Offset out of range", "🚧 Request refused by a broker policy", "👑 Partition leadership changed",
]


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
