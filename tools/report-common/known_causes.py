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
                r"|License manager.{0,40}error"
                # the license of a connector that could not be checked ("Invalid value …LicenseValidator$Failure: Could not
                # verify '${secret:…}' for configuration confluent.license")
                r"|LicenseValidator\$Failure",
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
    # an SSLException that only wraps a socket error (an LDAPS or HTTPS connection, already open, that times out, is
    # reset or closed) is not a TLS problem: it goes to ⏱️ / 🔌 like the same error on a plaintext connection
    {"name": "tls_handshake", "severity": "high", "category": "Certificate/TLS Issues",
     "pattern": r"SSLHandshakeException"
                r"|SSLException(?!: (?:Connection (?:reset|timed out|closed|or outbound has closed)|Read timed out"
                r"|Broken pipe|Socket closed))"
                r"|SSL handshake failed|PKIX path|unable to find valid certification path"
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
    # a Kerberos client without a valid ticket (a connector writing to HDFS / Hive, a SASL GSSAPI client): its keytab,
    # principal, ticket renewal or krb5.conf, not a wrong password of another system. Before authentication_failed
    {"name": "kerberos_no_ticket", "severity": "high", "category": "Authentication Issues",
     "pattern": r"Failed to find any Kerberos tgt|GSS initiate failed|No valid credentials provided \(Mechanism level"
                r"|Clock skew too great|Unable to obtain password from user",
     "title": "🎫 Kerberos ticket not found or not valid",
     "advice": "the client has no valid Kerberos ticket (TGT): the keytab or the principal of the client is wrong or "
               "unreadable (connect.hdfs.keytab / connect.hdfs.principal of an HDFS / Hive connector, sasl.jaas.config "
               "of a GSSAPI client), the ticket expired and was not renewed (a password rotated, renew_lifetime of "
               "krb5.conf), krb5.conf is not found (java.security.krb5.conf) or the clock of the host is off: run kinit "
               "-kt <keytab> <principal> then klist on the worker"},
    {"name": "authentication_failed", "severity": "high", "category": "Authentication Issues",
     "pattern": r"SaslAuthenticationException|AuthenticationException|authentication failed"
                r"|failed authentication(?![^\n]{0,300}Client SASL mechanism '[^']+' not enabled)"
                r"|invalid credentials|ORA-01017|Access denied for user|Login failed for user|\b401 unauthorized\b"
                r"|\bunauthorized\b|http (?:status|code|error)[ :=]*401|Status code\s*:?\s*401",
     "title": "🔑 Authentication failure",
     "advice": "check the credentials (user, password, API key, keytab) of the client or of the external system"},
    # an OAUTHBEARER login that cannot get its token (the callback handler of the client fails: the token endpoint, the
    # metadata server or the credentials) or a token the broker cannot validate (JWKS keys, issuer, audience, expiry)
    {"name": "oauth_token", "severity": "high", "category": "Authentication Issues",
     "pattern": r"(?:Login|Sasl)Exception: An internal error occurred while retrieving token from callback handler"
                r"|InvalidJwtException|UnresolvableKeyException: Unable to find a suitable verification key",
     "title": "🎟️ OAuth token cannot be obtained or validated",
     "advice": "SASL/OAUTHBEARER: either the client cannot get its token (its callback handler fails: the token endpoint "
               "or the metadata server is unreachable, or the client id / secret / user is wrong: look at the error just "
               "before), or the broker cannot validate it (InvalidJwtException, no verification key: the JWKS endpoint "
               "of the broker, the expected issuer and audience, a key rotated at the identity provider)"},
    {"name": "mds_error", "severity": "high", "category": "MDS/RBAC Issues",
     "pattern": r"MDS.{0,40}failed|metadata service.{0,40}error|TokenBasedSecurityStore.{0,80}Exception|RBAC.{0,40}token"
                r"|MdsException"
                # the MDS client of the token login (TokenUserLoginCallbackHandler, metadataServerUrls): its exceptions,
                # "Unexpected exception sending HTTP Request (io.confluent.security.auth.client.rest.RestClient)", and the
                # refresh of the MDS URLs
                r"|security\.auth\.client\.rest\.exceptions\.RestClientException|\(io\.confluent\.security\.auth\.client\.rest\.\w+(?::\d+)?\)"
                r"|Error while refreshing active metadata server urls|Failed to fetch MDS URLs",
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
    # the Connect Secret Registry (ConnectSecretRegistryExtension) cannot join its group: two members advertise the same
    # URL. Either two workers share rest.advertised.host.name / port, or one worker joins twice: since CP 7.9.11 and 8.4
    # (ce-kafka "Refactor REST extension registration", CC-43384), Connect calls register() of each REST extension a
    # second time for the admin resources when admin.listeners is a separate listener, and the extension initializes
    # the registry again ("Initializing REST with URI" twice in one start). The worker then fails to start
    {"name": "secret_registry_duplicate_urls", "severity": "critical", "category": "Connect Issues",
     "pattern": r"secret registry group contained multiple members advertising the same URL"
                r"|Found duplicate URLs for secret registry group members",
     "title": "🪞 Secret registry: duplicate URLs, Connect does not start",
     "advice": "two members of the secret registry group advertise the same URL, so ConnectSecretRegistryExtension times "
               "out (\"Timed out waiting for join group to complete\") and the worker exits. Count the \"Initializing REST "
               "with URI\" lines of one start: two in the same worker on CP 7.9.11+ / 8.4+ with a separate admin.listeners "
               "means the extension is registered twice (regular and admin REST resources): remove admin.listeners (admin "
               "endpoints back on the main listeners) or set it empty (admin endpoints disabled) until a fixed release. One "
               "per worker: two workers share rest.advertised.host.name / rest.advertised.port, give each its own"},
    # the worker process exits during its startup (AbstractConnectCli): the Caused by chain says why, and a service
    # manager (systemd, Kubernetes) restarting it makes a restart loop with the same error every few minutes
    {"name": "connect_failed_to_start", "severity": "critical", "category": "Connect Issues",
     "pattern": r"ERROR Failed to start Connect\b|ERROR Stopping due to error \(org\.apache\.kafka\.connect",
     "title": "🚫 Connect worker failed to start",
     "advice": "the Connect worker exited during its startup, before its REST API was up (Control Center and the REST "
               "calls see no connector): the Caused by chain of the record says why. When it repeats, the service manager "
               "(systemd, Kubernetes) restarts the worker in a loop: fix the cause first, restarts do not help"},
    # a connector received the literal ${provider:path:key} of a config provider instead of its value: the provider is not
    # in config.providers of the worker, the path or key does not exist, or the provider was not ready (secret registry)
    {"name": "config_provider_unresolved", "severity": "high", "category": "Connect Issues",
     "pattern": r"(?:Exception|error|invalid|failed)[^\n]{0,300}\$\{(?:secret|file|directory|env|vault|keyvault|aws"
                r"|azure|gcp|securepass)[\w-]{0,20}:[^}\s]{1,200}",
     "title": "🧷 Config provider placeholder not resolved",
     "advice": "a connector used the literal ${provider:path:key} placeholder of a config provider instead of its value "
               "(for example as a password or a token): check that the provider is in config.providers of every worker, "
               "with its config.providers.<name>.class, and that the path and key exist; with the Connect Secret Registry "
               "(${secret:…}), check that it started on the worker"},
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
     "pattern": r"Converting byte\[\] to Kafka Connect data failed|SerializationException"
                # (not an SMT that throws: 🪄, nor a tombstone skipped by a sink: 🫥)
                r"|^(?![\s\S]*(?:Executing stage 'TRANSFORMATION'|Skipping null value record))[\s\S]*?DataException",
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
                r"|Client SASL mechanism '[^']+' not enabled|UnsupportedSaslMechanismException"
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
                # (not the license of a connector or a ${provider:…} placeholder not resolved: 📜 and 🧷 explain them, with
                # their own advice)
                r"|ConfigException: (?:Invalid value(?![^\n]{0,400}(?:LicenseValidator\$Failure|\$\{[\w-]{1,30}:"
                r"|for configuration confluent\.license))|Missing required configuration)",
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
    # a single message transform (SMT) that throws: "Executing stage 'TRANSFORMATION' with class '…Flatten$Value'".
    # Flatten "does not support ARRAY" on a worker of Apache Kafka 3.1 or later (KAFKA-12305 added arrays, kept as is) is
    # an older connect-transforms jar on the plugin path that shadows the one of the worker
    {"name": "transformation_failed", "severity": "medium", "category": "Connect Issues",
     "pattern": r"Executing stage 'TRANSFORMATION'|Flatten transformation does not support ARRAY",
     "title": "🪄 Transformation (SMT) failed",
     "advice": "a single message transform threw on a record (the class is in the Executing stage line): its config does "
               "not fit the records, or the record has a field type it does not handle (playground connector smt test "
               "replays it on a record). Flatten \"does not support ARRAY\" on Apache Kafka 3.1 or later (CP 7.1+) is an "
               "old connect-transforms jar on the plugin path that shadows the one of the worker: compare the "
               "connector-plugins of the workers (GET /connector-plugins?connectorsOnly=false)"},
    # errors.log.enable=true: the LogReporter logs every record that failed in a stage, "Error encountered in task
    # orders-0. Executing stage 'KAFKA_PRODUCE' with class …". With errors.tolerance=all the record is skipped
    {"name": "record_failed_in_stage", "severity": "medium", "category": "Connect Issues",
     "pattern": r"Error encountered in task \S+\. Executing stage '",
     "title": "⏭️ Records failed in a stage (errors.log.enable)",
     "advice": "each line is a record that failed in the stage it names (KAFKA_PRODUCE, TASK_PUT, VALUE_CONVERTER, "
               "TRANSFORMATION…). With errors.tolerance=all the task skips it and keeps running: a sink sends it to its "
               "dead letter queue when one is set (playground topic dlq inspect), a source drops it and its offset still "
               "moves on (data loss). With errors.tolerance=none, a 🧯 errors.tolerance exceeded follows and the task fails"},
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
    # an HTTP sink (or any REST client of a connector) that gets 5xx: "Status code : 504, Reason Phrase : Gateway Timeout"
    {"name": "http_server_error", "severity": "medium", "category": "Network Issues",
     "pattern": r"Status code\s*:?\s*5\d\d\b|http (?:status|code|error)[ :=]*5\d\d\b|\b50[234] (?:Bad Gateway|Service Unavailable"
                r"|Gateway Timeout)\b",
     "title": "🌩️ HTTP 5xx from the external system",
     "advice": "the endpoint (or a gateway, load balancer or proxy in front of it) answered 500, 502, 503 or 504: look at its "
               "side for the same times. A 504 or a timeout does not say whether the request was processed: the retries "
               "of the connector (retry.backoff.ms, max.retries) can send it twice to an endpoint that is not idempotent"},
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
    # a sink that gets records with a null value (tombstones): skipped with behavior.on.null.values=ignore (the ERROR
    # comes from errors.log.enable / report.null.values.to.dlq), the task killed with fail
    {"name": "null_value_record", "severity": "medium", "category": "Connect Issues",
     "pattern": r"Skipping null value record|Null valued records are not writeable",
     "title": "🫥 Null value (tombstone) records skipped by the sink",
     "advice": "the sink received records with a null value (tombstones, a deleted key): behavior.on.null.values=ignore "
               "skips them (the ERROR line of each one comes from errors.log.enable / report.null.values.to.dlq: "
               "report.null.values.to.dlq=false stops it), fail kills the task. A consumer lag that never goes to 0 "
               "behind trailing tombstones is a bug of the storage sinks fixed in a later version (🩹 below when the "
               "plugin is known)"},
    # the JDBC sink did not find the table (or a column) and may not create it
    {"name": "jdbc_table_missing", "severity": "high", "category": "Connect Issues",
     "pattern": r"TableAlterOrCreateException|is missing and auto-creation is disabled|auto-evolution is disabled",
     "title": "🗄️ JDBC sink: table or column missing (auto.create / auto.evolve off)",
     "advice": "the JDBC sink did not find the table (or a column of the record) and auto.create / auto.evolve is false: "
               "create the table or the column, or set auto.create=true / auto.evolve=true; check table.name.format, "
               "the case and quoting of the name (quote.sql.identifiers) and that the database user sees that schema"},
    # debug traces of a plugin logged at ERROR ("ERROR DEBUG_ADD_RECORD: …"): a modified or debug build, not failures
    {"name": "debug_traces_at_error", "severity": "low", "category": "Application Errors",
     "pattern": r"\bERROR\b[^\n]{0,200}?\sDEBUG_[A-Z0-9]{2,}\w*(?:\[\d+\])?:",
     "title": "🪵 Debug traces logged at ERROR",
     "advice": "these lines are debug traces (DEBUG_… messages, usually not in the upstream code: a modified or debug "
               "build of the plugin) logged at ERROR: not failures, but they flood the logs, hide the real errors and "
               "shorten the window the rotated files keep. Ask which build of the plugin runs, and to remove the traces "
               "or log them at DEBUG"},
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
    # IBM i (AS400) with the IBM Toolbox for Java (jt400) JDBC driver. With secure=true, jt400 20.0.8 and later first ask the
    # server mapper (as-svrmap, TCP 449) for the port of the TLS host connection server (as-hostcnn-s, 9480, IBM i 7.6),
    # whatever port the URL gives: a refused 449 or an IBM i without that server falls back to the database port, but a
    # 449 (or 9480) silently dropped by a firewall times out ("Connect timed out" at PortMapper.getSocketConnection
    # under AS400ImplRemote.hostcnnConnect) and the database port is never tried. Before connection_refused
    {"name": "jt400_port_mapper_unreachable", "severity": "high", "category": "Network Issues",
     "pattern": r"com\.ibm\.as400\.access\.(?:PortMapper\.getSocketConnection|AS400ImplRemote\.hostcnnConnect)",
     "title": "🖥️ IBM i (jt400): server mapper port 449 unreachable",
     "advice": "the jt400 driver could not reach the IBM i server mapper (TCP 449): with secure=true, jt400 20.0.8 and later "
               "contact it before the database port of the URL, to look up the TLS host connection server (as-hostcnn-s, "
               "9480, IBM i 7.6). Allow TCP 449 (and 9480 on IBM i 7.6 with the host connection server) from the Connect "
               "workers to the IBM i: they go in no connector setting. A refused 449 falls back to the database port, a "
               "dropped one times out. jt400 20.0.7 and earlier do not do this lookup"},
    # jt400 that loses the connection during its first exchange (random seed): a plain connection to the TLS database port
    # (9471) without secure=true, or a TLS one (secure=true) to the plain port 8471
    {"name": "jt400_connection_dropped", "severity": "high", "category": "Network Issues",
     "pattern": r"com\.ibm\.as400\.access\.(?:ConnectionDroppedException|AS400XChgRandSeedReplyDS)",
     "title": "🖥️ IBM i (jt400): connection dropped at the first exchange",
     "advice": "the IBM i (or a firewall, proxy or load balancer in between) closed the connection during the first exchange "
               "of jt400: most often the TLS / plain port does not match secure= in the URL (9471 is the TLS database "
               "port and needs secure=true, 8471 the plain one; the IBM i administrator can have changed them). Check the "
               "port and secure=, then that the IBM i certificate CA is in the truststore of the Connect worker JVM"},
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
     "pattern": r"SchemaRegistryException|(?<!security\.auth\.client\.rest\.exceptions\.)RestClientException",
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
    "💥 OutOfMemoryError", "🪞 Secret registry: duplicate URLs, Connect does not start", "🚫 Connect worker failed to start",
    KILLED_TASK_TITLE, "🧷 Config provider placeholder not resolved", "🧯 errors.tolerance exceeded", "🧩 Plugin not found", "📦 Class loading error",
    "🧬 Not enough replicas",
    "🔑 Authentication failure", "🪪 MDS / RBAC token error", "🎟️ OAuth token cannot be obtained or validated", "🎫 Kerberos ticket not found or not valid", "☁️ Cloud credentials or permission refused", "🚫 Authorization failure",
    "🗝️ Empty or unreadable truststore", "🔐 TLS handshake failure", "🧲 Unknown magic byte",
    "🔍 Schema id not found", "🛡️ Incompatible schema refused", "📛 Subject not found",
    "🪄 Transformation (SMT) failed", "🔀 Serialization or conversion error", "🛂 Wrong security.protocol or SASL mechanism", "🌐 Host name not resolved (DNS)",
    "🔌 Connection failure", "🗄️ JDBC sink: table or column missing (auto.create / auto.evolve off)",
    "⚙️ Invalid client configuration", "⌛ Records not delivered in time", "🗺️ Topic not found in the metadata", "🐢 Consumer left its group: max.poll.interval.ms exceeded", "🔁 Group rebalances or coordinator lost", "📥 Producer buffer full",
    "🤺 Producer fenced (transactions, exactly-once)", "⏳ Source offsets not committed in time", "🚦 Throttled by the external system", "🌩️ HTTP 5xx from the external system",
    "⏭️ Records failed in a stage (errors.log.enable)",
    "🫥 Null value (tombstone) records skipped by the sink",
    "🛑 Task or connector did not stop in time", "⏱️ Timeouts", "📏 Record too large", "🧹 Clients aborted while a task stopped",
    "❓ Unknown topic or partition", "⏮️ Offset out of range", "🚧 Request refused by a broker policy", "👑 Partition leadership changed",
    "🪵 Debug traces logged at ERROR",
]


# a host of Confluent Cloud (pkc-xxxxx.<region>.<cloud>.confluent.cloud, psrc-…, the Cloud API)
CCLOUD_PATTERN = r"\.confluent\.cloud\b"


# what to read about a known cause, by title: its docs.confluent.io page ("docs"). Its Confluent support
# knowledge-base articles (for signed-in users) are not in this public repository: they come from the private
# kb-links.json (kb_links()), with their variants ("pattern"), fallbacks and Confluent Cloud flags, merged by links()
LINKS = {
    "🧲 Unknown magic byte": {"docs": "https://docs.confluent.io/platform/current/schema-registry/fundamentals/serdes-develop/index.html"},
}


MAX_KB_ARTICLES = 3


def _select(entries, texts, ccloud=False):
    """The entries whose pattern matches one of `texts` (the variants), then those without a pattern, except the
    "fallback" ones when a variant matched (a general article too far from the variants: Confluent Cloud only…), and
    the "ccloud" ones when the input (True) or the records of the cause ("records") do not point at Confluent Cloud"""
    variants, general = [], []
    for entry in entries:
        need = entry.get("ccloud")
        if need == "records" and not any(re.search(CCLOUD_PATTERN, t, re.IGNORECASE) for t in texts):
            continue
        if need and need != "records" and not ccloud:
            continue
        pattern = entry.get("pattern")
        if not pattern:
            general.append(entry)
        elif any(re.search(pattern, t, re.IGNORECASE) for t in texts):
            variants.append(entry)
    return variants + [e for e in general if not (variants and e.get("fallback"))]


# 📚 the knowledge base by error message (kb_index.json): the support.confluent.io articles that explain one precise
# log message, each with the signature of that message (a regex, its longest literal run used as a quick filter) and,
# when the title names a product (HTTP Sink, JDBC…), a context regex the records must match too. Articles for signed-in
# users: a catalog kept in the private reproduction-models repository, never here ($PLAYGROUND_KB_INDEX_FILE gives
# another file). Without it (a fork, CI), no article is looked up. An article of the curated links (KB_LINKS) keeps its
# own rule there and is never looked up
_PRIVATE_LOG_ANALYSIS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "reproduction-models",
                                     "_miscellaneous", "log-analysis")
_KB_INDEX = os.path.join(_PRIVATE_LOG_ANALYSIS, "kb_index.json")
_kb_index = None


def _literal(pattern):
    """the longest literal run of a signature of kb_index.json, lowercased"""
    parts = re.split(r"\.\{0,160\}", pattern)
    return max((re.sub(r"\\(.)", r"\1", p.replace(r"\s+", " ")) for p in parts), key=len, default="").strip().lower()


# a signature of one or two words names a class: kept only when it is a precise Kafka / Confluent exception or error
# (NotLeaderForPartitionException, UnknownProducerIdException…), never a generic one that appears in any stack trace (a
# NullPointerException is not the NullPointerException of one ksqlDB query) nor a bare class name (KafkaConfigBackingStore)
_GENERIC_EXCEPTIONS = {
    "nullpointerexception", "concurrentmodificationexception", "classnotfoundexception", "illegalstateexception",
    "illegalargumentexception", "ioexception", "timeoutexception", "runtimeexception", "exception", "throwable",
    "sockettimeoutexception", "connectexception", "interruptedexception", "unsupportedoperationexception",
    "noclassdeffounderror", "linkageerror", "classcastexception", "arrayindexoutofboundsexception", "numberformatexception",
    "sqlexception", "wakeupexception", "kafkaexception", "dataexception", "retriableexception", "serializationexception",
    "executionexception", "completionexception", "invocationtargetexception", "nosuchmethoderror", "error"}


def _specific_signature(literal):
    """a signature worth linking an article for: a message of 3 words or more, or a precise exception / error name"""
    if literal.count(" ") >= 2:
        return True
    name = literal.strip().rstrip(":").split(" ")[0].rsplit(".", 1)[-1]
    return (name.endswith(("exception", "error")) and name not in _GENERIC_EXCEPTIONS
            and not literal.startswith(("java.", "javax.", "jdk.", "sun.")))


def _load_kb_index():
    global _kb_index
    if _kb_index is None:
        _kb_index = []
        path = os.environ.get("PLAYGROUND_KB_INDEX_FILE") or _KB_INDEX
        articles = []
        if os.path.isfile(path):
            try:
                with open(path, encoding="utf-8") as f:
                    articles = json.load(f).get("articles") or []
            except (OSError, ValueError, AttributeError) as ex:
                print(f"warning: cannot read the knowledge-base index {path}: {ex}", file=sys.stderr)
        for a in articles:
            try:
                pats = [(_literal(x), re.compile(x, re.IGNORECASE)) for x in a.get("patterns") or []]
                ctx = re.compile(a["context"], re.IGNORECASE) if a.get("context") else None
            except re.error:
                continue
            pats = [(lit, rx) for lit, rx in pats if len(lit) >= 8 and _specific_signature(lit)]
            if pats and str(a.get("url", "")).startswith("https://"):
                _kb_index.append((pats, ctx, {"title": a.get("title") or a["url"], "url": a["url"]}))
    return _kb_index


def article_id(url):
    """the id of a support.confluent.io article, or the url"""
    m = re.search(r"/articles/(\d+)", url or "")
    return m.group(1) if m else url


def kb_for_texts(texts, exclude=(), limit=MAX_KB_ARTICLES):
    """the articles of the knowledge-base index that quote an error of `texts` (records): [{"title", "url"}], the most
    specific signature first, an article naming a product only when the records mention it too, never an article of
    the curated links (it keeps its own rule) nor one of `exclude`"""
    texts = [t[:8000] for t in list(texts)[:200] if t]
    if not texts:
        return []
    lows = [re.sub(r"\s+", " ", t).lower() for t in texts]
    joined = "\n".join(lows)
    skip = {article_id(u) for u in exclude} | {article_id(e.get("kb")) for v in kb_links().values() for e in v if e.get("kb")}
    hits = []
    for pats, ctx, art in _load_kb_index():
        if article_id(art["url"]) in skip:
            continue
        for lit, rx in pats:
            if lit in joined and any(lit in low and rx.search(t) for t, low in zip(texts, lows)):
                if ctx is None or any(ctx.search(t) for t in texts):
                    hits.append((len(lit), art))
                break
    hits.sort(key=lambda h: -h[0])
    out, seen = [], set()
    for _, art in hits:
        if art["url"] not in seen:
            seen.add(art["url"])
            out.append(dict(art))
    return out[:limit]


# 📚 the curated articles of each known cause (kb-links.json, private, next to kb_index.json; $PLAYGROUND_KB_LINKS_FILE
# gives another file): {"links": {"<known cause title>": [{"kb": url, "kb_title": "...", "pattern": "optional regex of a
# variant", "fallback": true, "ccloud": true | "records"}]}}, the same keys as the docs entries of LINKS below. Articles
# for signed-in users: never in this public repository. Without the file, the known causes keep their docs pages only
_KB_LINKS = os.path.join(_PRIVATE_LOG_ANALYSIS, "kb-links.json")
_kb_links = None


def kb_links():
    """{known cause title: [entries with "kb"]} of the private kb-links.json, {} without it"""
    global _kb_links
    if _kb_links is None:
        _kb_links = {}
        path = os.environ.get("PLAYGROUND_KB_LINKS_FILE") or _KB_LINKS
        if os.path.isfile(path):
            try:
                with open(path, encoding="utf-8") as f:
                    data = json.load(f)
                for title, items in (data.get("links") or {}).items():
                    items = items if isinstance(items, list) else [items]
                    _kb_links[title] = [x for x in items if isinstance(x, dict) and str(x.get("kb", "")).startswith("https://")]
            except (OSError, ValueError, AttributeError) as ex:
                print(f"warning: cannot read the knowledge-base links {path}: {ex}", file=sys.stderr)
    return _kb_links


def links(title, texts=(), ccloud=False):
    """What to read about the known cause `title`, whose records are `texts`: {"kb", "kb_title" (the first article),
    "kb_articles": [{"title", "url"}], "docs"} (the keys it has), or {}. ccloud: the input points at Confluent Cloud
    (the articles marked "ccloud" are shown)"""
    value = LINKS.get(title)
    entries = ((value if isinstance(value, list) else [value]) if value else []) + kb_links().get(title, [])
    texts = list(texts)[:500]
    out = {}
    # the articles of the known cause first (written for it, with their context), then the ones whose exact message is
    # in the records (📚 kb_errors.json) in the room left
    articles = [{"title": e.get("kb_title") or "knowledge base article", "url": e["kb"]}
                for e in _select(entries, texts, ccloud) if e.get("kb")]
    seen = {a["url"] for a in articles}
    articles = (articles + [a for a in kb_for_texts(texts) if a["url"] not in seen])[:MAX_KB_ARTICLES]
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
    # (the CFK JSON log lines have no logger after the message)
    (r"Unable to submit events without credentials(?: \(io\.confluent\.telemetry|\s*$|\s*\n)",
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
    # found in 3 to 5 unrelated support bundles each, never a cause
    (r"Renouncing the leadership due to a metadata log event",
     "a KRaft controller hands over the leadership (a controller change, in 🔄 Restarts and rebalances)"),
    (r"Performing controller activation\. Loaded ZK migration state of NONE", "a KRaft controller becomes active (no ZooKeeper migration)"),
    (r"Catching up to assignment's config offset", "a Connect worker reads the configs of its new assignment after a rebalance"),
    (r"Jolokia Access Control is not enabled", "the Jolokia agent of the image without an access policy"),
    (r"\bEmpty contextPath\b", "Jetty: a REST handler mounted at the root"),
    (r"Ignoring notification of change event DEAD_BROKER .{0,80}while DataBalancer is not started",
     "Self-Balancing not started yet on this node"),
    (r"No value specified for metadata\.encoder\.secret", "no secret to encode sensitive dynamic broker configs (not used)"),
    (r"Not initializing since the Jaas config file is not provided", "no JAAS file for this component (not using JAAS)"),
    (r"Switching to END_SESSION because sequences have incremented due to a log switch",
     "Oracle CDC: a redo log switch, the session moves on (normal)"),
]
_HARMLESS_RX = [(re.compile(p), reason) for p, reason in HARMLESS]


def harmless(text):
    """the reason why the record `text` is known harmless, else None"""
    for rx, reason in _HARMLESS_RX:
        if rx.search(text):
            return reason
    return None
