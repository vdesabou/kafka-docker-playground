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
                r"|not authorized to access|\b403 forbidden\b|http (?:status|code|error)[ :=]*403|Status code\s*:?\s*403",
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
    {"name": "unknown_magic_byte", "severity": "high", "category": "Serialization Issues",
     "pattern": r"Unknown magic byte",
     "title": "🧲 Unknown magic byte",
     "advice": "the records were not written with the Schema Registry serializer the converter expects: check "
               "key.converter / value.converter against the producer (playground topic consume shows the real format)"},
    {"name": "serialization_error", "severity": "medium", "category": "Serialization Issues",
     "pattern": r"Converting byte\[\] to Kafka Connect data failed|SerializationException|DataException",
     "title": "🔀 Serialization or conversion error",
     "advice": "the converter does not match the format of the records, or a record does not match the schema; "
               "errors.tolerance=all + a dead letter queue keeps the task running (playground topic dlq inspect)"},
    {"name": "record_too_large", "severity": "medium", "category": "Kafka Issues",
     "pattern": r"RecordTooLargeException|MESSAGE_TOO_LARGE|message\.max\.bytes",
     "title": "📏 Record too large",
     "advice": "raise max.request.size of the producer (producer.override.max.request.size for a source connector) and "
               "message.max.bytes / max.message.bytes on the broker or topic"},
    {"name": "unknown_topic", "severity": "medium", "category": "Kafka Issues",
     "pattern": r"UnknownTopicOrPartitionException|UNKNOWN_TOPIC_OR_PARTITION",
     "title": "❓ Unknown topic or partition",
     "advice": "the topic does not exist and is not auto-created: create it, or check its name"},
    {"name": "offset_out_of_range", "severity": "medium", "category": "Kafka Issues",
     "pattern": r"OffsetOutOfRangeException|OFFSET_OUT_OF_RANGE",
     "title": "⏮️ Offset out of range",
     "advice": "the committed offset was deleted by retention: the consumer restarts from auto.offset.reset"},
    {"name": "task_killed", "severity": "high", "category": "Connect Issues",
     "pattern": KILLED_TASK_PATTERN,
     "title": KILLED_TASK_TITLE,
     "advice": "it stays FAILED until it is restarted: fix the cause (the exception chain of the record), then "
               "playground connector restart --connector <connector>"},
    {"name": "dns_error", "severity": "high", "category": "Network Issues",
     "pattern": r"no such host|DNS resolution failed|dial tcp: lookup|UnknownHostException|Couldn't resolve server",
     "title": "🔌 Connection failure",
     "advice": "the host is down, unreachable or the name does not resolve: check the host, port and network "
               "(playground debug tcp-dump shows what goes over the wire)"},
    {"name": "connection_refused", "severity": "high", "category": "Network Issues",
     "pattern": r"connection refused|Connection reset by peer|NoRouteToHostException|No route to host|Broken pipe"
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
    # the 3 most common Schema Registry errors first, each with the playground schema command that explains it
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
    "💥 OutOfMemoryError", KILLED_TASK_TITLE, "🧩 Plugin not found", "📦 Class loading error",
    "🔑 Authentication failure", "🚫 Authorization failure", "🔐 TLS handshake failure", "🧲 Unknown magic byte",
    "🔍 Schema id not found", "🛡️ Incompatible schema refused", "📛 Subject not found",
    "🔀 Serialization or conversion error", "🔌 Connection failure", "⏱️ Timeouts", "📏 Record too large",
    "❓ Unknown topic or partition", "⏮️ Offset out of range",
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
