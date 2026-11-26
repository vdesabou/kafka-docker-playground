#!/usr/bin/env python3
"""Best-practice warnings for a Kafka Connect connector config (playground connector lint).

Reads the connector config as a flat JSON object (already normalized by the CLI from CFK / Strimzi / terraform /
.properties / expand=info), and optionally a context JSON gathered from the running environment:

    {"brokers": 1, "partitions": {"topic": 3}, "worker_override_policy": "All", "environment": "plaintext"}

Prints a table and a verdict (or --json), exits 1 when there is at least one warning (HIGH, MEDIUM or LOW), 0 when
there are only INFO notes or nothing. Standard library only, so it runs with python3 -I.
"""
import argparse
import json
import re
import sys

SEVERITIES = ("HIGH", "MEDIUM", "LOW", "INFO")
EMPTY = ("", "null", "[]", None)
MASKED = re.compile(r"^(\*+|\[hidden\])$|••")
URL_WITH_PASSWORD = re.compile(r"://[^/\s:@]+:(?!\$\{)[^@\s/]+@")
EXTERNALIZED = re.compile(r"^\$\{[^}]+\}$")
# keys holding a secret: last segment, or a known suffix
SECRET_LAST = {"password", "passwd", "secret", "token", "credentials"}
SECRET_SUFFIXES = ("secret.access.key", "secret.key", "private.key", "api.secret", "client.secret", "credentials.json",
                   "access.token", "auth.token", "bearer.token", "sas.token", "account.key", "connection.string",
                   "keystore.key", "key.password")
SR_CONVERTERS = ("AvroConverter", "ProtobufConverter", "JsonSchemaConverter")
SINGLE_TASK_CLASSES = {
    "io.debezium.connector.mysql.MySqlConnector": "Debezium MySQL",
    "io.debezium.connector.postgresql.PostgresConnector": "Debezium PostgreSQL",
    "io.debezium.connector.oracle.OracleConnector": "Debezium Oracle",
}
# connector.client.config.override.policy=Principal only allows these
PRINCIPAL_ALLOWED = {"sasl.jaas.config", "sasl.mechanism", "security.protocol"}


FM_MARKERS = ("kafka.auth.mode", "kafka.api.key", "kafka.api.secret", "kafka.service.account.id", "input.data.format",
              "output.data.format", "input.key.format", "output.key.format")


def is_fully_managed(cfg):
    """a Confluent Cloud fully managed config: one of its kafka.* / *.data.format keys, or a class like S3_SINK (a
    short class name like FileStreamSink is a valid alias on a self-managed worker)"""
    cls = cfg.get("connector.class", "")
    return any(k in cfg for k in FM_MARKERS) or bool(re.fullmatch(r"[A-Z0-9]+(_[A-Z0-9]+)+", cls))


def kind_of(cfg):
    cls = cfg.get("connector.class", "")
    if cfg.get("topics") not in EMPTY or cfg.get("topics.regex") not in EMPTY:
        return "sink"
    if re.search(r"sink", cls, re.I):
        return "sink"
    if re.search(r"source", cls, re.I) or cls in SINGLE_TASK_CLASSES:
        return "source"
    return "unknown"


def to_int(value, default=None):
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return default


def is_secret_key(key):
    k = key.lower()
    if k.endswith(".location") or k.endswith(".type") or k.endswith(".file") or k.endswith(".path"):
        return False
    if k == "sasl.jaas.config":
        return True
    last = k.split(".")[-1]
    return last in SECRET_LAST or k.endswith(SECRET_SUFFIXES)


def lint(cfg, ctx):
    findings = []

    def add(severity, key, value, message, fix):
        findings.append({"severity": severity, "key": key, "value": "" if value is None else str(value),
                         "message": message, "fix": fix})

    kind = kind_of(cfg)
    fm = is_fully_managed(cfg)
    brokers = to_int(ctx.get("brokers"))
    partitions = ctx.get("partitions") or {}
    policy = ctx.get("worker_override_policy")

    tolerance = str(cfg.get("errors.tolerance", "none")).strip().lower()
    dlq = cfg.get("errors.deadletterqueue.topic.name")
    has_dlq = dlq not in EMPTY and str(dlq).strip() != ""
    log_enable = str(cfg.get("errors.log.enable", "false")).strip().lower() == "true"

    # --- error handling -------------------------------------------------------------------------------------------
    # fully managed sinks get a dead letter queue (dlq-<lcc id>) by default and have no errors.log.enable
    if tolerance == "all" and kind == "sink" and not has_dlq and not fm:
        add("MEDIUM", "errors.tolerance", "all",
            "bad records are skipped and lost: no dead letter queue (errors.deadletterqueue.topic.name)",
            "set errors.deadletterqueue.topic.name to keep them, read it with playground topic dlq inspect")
    if tolerance == "all" and not log_enable and not (kind == "sink" and has_dlq) and not fm:
        add("LOW", "errors.log.enable", cfg.get("errors.log.enable", "false (default)"),
            "with errors.tolerance=all the records skipped are not even logged",
            "set errors.log.enable=true and errors.log.include.messages=true")
    if has_dlq and kind == "sink" and tolerance != "all":
        add("MEDIUM", "errors.deadletterqueue.topic.name", dlq,
            f"the dead letter queue is never written: errors.tolerance={tolerance}, the task fails on the first bad record",
            "set errors.tolerance=all, or remove the dead letter queue")
    if has_dlq and kind == "source":
        add("LOW", "errors.deadletterqueue.topic.name", dlq,
            "source connectors have no dead letter queue: the key is ignored",
            "remove it; errors.tolerance=all + errors.log.enable=true is what a source can do")
    if has_dlq and kind == "sink":
        rf_raw = cfg.get("errors.deadletterqueue.topic.replication.factor")
        rf = to_int(rf_raw, 3)
        if brokers is not None and rf > brokers:
            add("HIGH", "errors.deadletterqueue.topic.replication.factor", rf_raw if rf_raw is not None else "3 (default)",
                f"the dead letter queue needs {rf} replicas but the cluster has {brokers} broker(s): its creation fails "
                "and the task fails at startup",
                f"set errors.deadletterqueue.topic.replication.factor={brokers} (or create the topic beforehand)")
        elif rf == 1 and rf_raw is not None:
            add("LOW", "errors.deadletterqueue.topic.replication.factor", "1",
                "the dead letter queue has one replica: its records are lost with that broker",
                "use 3 in production")

    # --- other replication factors ------------------------------------------------------------------------------
    if brokers is not None:
        for key, value in cfg.items():
            if key == "errors.deadletterqueue.topic.replication.factor" or not key.endswith("replication.factor"):
                continue
            rf = to_int(value)
            if rf is not None and rf > brokers:
                add("HIGH", key, value,
                    f"{rf} replicas asked but the cluster has {brokers} broker(s): the topic cannot be created",
                    f"set {key}={brokers}")

    # --- tasks ---------------------------------------------------------------------------------------------------
    tasks_max = to_int(cfg.get("tasks.max"), 1)
    if kind == "sink" and partitions and cfg.get("topics") not in EMPTY:
        known = [partitions.get(t.strip()) for t in str(cfg["topics"]).split(",") if t.strip()]
        if known and all(isinstance(n, int) and n > 0 for n in known):
            total = sum(known)
            if tasks_max > total:
                add("LOW", "tasks.max", tasks_max,
                    f"{tasks_max} tasks for {total} partition(s): {tasks_max - total} task(s) stay idle",
                    f"set tasks.max={total} or add partitions (playground topic add-partitions)")
    cls = cfg.get("connector.class", "")
    if cls in SINGLE_TASK_CLASSES and tasks_max > 1:
        add("INFO", "tasks.max", tasks_max, f"{SINGLE_TASK_CLASSES[cls]} always runs a single task",
            "tasks.max=1")

    # --- client overrides ----------------------------------------------------------------------------------------
    overrides = [k for k in cfg if k.startswith(("consumer.override.", "producer.override.", "admin.override."))]
    if overrides:
        if policy is not None and policy.lower() == "none":
            add("HIGH", overrides[0], cfg[overrides[0]],
                f"{len(overrides)} client override(s) but the worker has connector.client.config.override.policy=None: "
                "the connector is rejected",
                "set connector.client.config.override.policy=All on the workers, or move the settings to the worker")
        elif policy is not None and policy.lower() == "principal":
            refused = [k for k in overrides if k.split(".override.", 1)[1] not in PRINCIPAL_ALLOWED]
            if refused:
                add("HIGH", refused[0], cfg[refused[0]],
                    f"policy Principal of the worker only allows overriding {', '.join(sorted(PRINCIPAL_ALLOWED))}: "
                    f"{len(refused)} override(s) refused",
                    "set connector.client.config.override.policy=All on the workers")
        elif policy is None and not fm:
            add("INFO", overrides[0], cfg[overrides[0]],
                f"{len(overrides)} client override(s): they need connector.client.config.override.policy=All (default "
                "since Kafka 3.0) or Principal (security keys only) on the workers",
                "check the worker config")
        if kind == "source":
            for k in overrides:
                if k.startswith("consumer.override."):
                    add("LOW", k, cfg[k], "a source connector has no consumer: the key is ignored", "remove it")
    records = to_int(cfg.get("consumer.override.max.poll.records"), 0)
    interval = to_int(cfg.get("consumer.override.max.poll.interval.ms"), 300000)
    if kind == "sink" and records >= 5000 and interval <= 300000:
        add("MEDIUM", "consumer.override.max.poll.records", records,
            f"{records} records per poll with max.poll.interval.ms={interval}: a slow put() makes the consumer leave its "
            "group (rebalances, commits failing)",
            "lower consumer.override.max.poll.records or raise consumer.override.max.poll.interval.ms")
    if str(cfg.get("consumer.override.auto.offset.reset", "")).lower() == "latest":
        add("LOW", "consumer.override.auto.offset.reset", "latest",
            "without committed offsets (new connector, offsets deleted) the records already in the topic are skipped",
            "remove it: Connect sinks default to earliest")
    acks = cfg.get("producer.override.acks")
    if acks not in EMPTY and str(acks).lower() not in ("all", "-1"):
        add("MEDIUM", "producer.override.acks", acks,
            "the producer does not wait for all the in-sync replicas: records can be lost when a broker fails",
            "remove it: Connect defaults to acks=all")

    # --- converters ----------------------------------------------------------------------------------------------
    if not fm:
        for prefix in ("key.converter", "value.converter"):
            conv = str(cfg.get(prefix, ""))
            if not conv:
                continue
            short = conv.split(".")[-1]
            if short in SR_CONVERTERS and cfg.get(f"{prefix}.schema.registry.url") in EMPTY:
                add("MEDIUM", f"{prefix}.schema.registry.url", "",
                    f"{prefix}={short} is set on the connector without {prefix}.schema.registry.url: a converter set on "
                    "the connector does not inherit the converter settings of the worker",
                    f"add {prefix}.schema.registry.url (and its {prefix}.basic.auth.* / ssl settings) to the connector")
            if short == "JsonConverter" and cfg.get(f"{prefix}.schema.registry.url") not in EMPTY:
                add("MEDIUM", prefix, conv,
                    "org.apache.kafka.connect.json.JsonConverter ignores Schema Registry: the schema.registry.url is "
                    "unused and records with a schema id fail with 'Unknown magic byte' style errors",
                    f"{prefix}=io.confluent.connect.json.JsonSchemaConverter for JSON Schema with Schema Registry")
            if short == "JsonConverter" and kind == "sink" and \
                    str(cfg.get(f"{prefix}.schemas.enable", "true")).lower() == "true":
                add("INFO", f"{prefix}.schemas.enable", cfg.get(f"{prefix}.schemas.enable", "true (default)"),
                    "JsonConverter expects a {\"schema\": …, \"payload\": …} envelope; plain JSON fails with "
                    "'JsonConverter with schemas.enable requires \"schema\" and \"payload\" fields'",
                    f"set {prefix}.schemas.enable=false for plain JSON; playground topic check-format tells which")

    # --- secrets -------------------------------------------------------------------------------------------------
    if not fm:
        for key, value in cfg.items():
            if value in EMPTY:
                continue
            v = str(value).strip()
            if not is_secret_key(key):
                if URL_WITH_PASSWORD.search(v):
                    add("LOW", key, "****", "password in clear text in a connection URL of the connector config",
                        "use a config provider: ${file:/path:key}, ${secret:…} or ${vault:…}")
                continue
            if not v or EXTERNALIZED.match(v) or MASKED.search(v):
                continue
            if key.lower() == "sasl.jaas.config" and not re.search(r"password\s*=\s*\"(?!\$\{)", v):
                continue
            add("LOW", key, "****", "secret in clear text in the connector config (visible in GET /connectors and in "
                "the config topic)", "use a config provider: ${file:/path:key}, ${secret:…} or ${vault:…}")

    order = {s: i for i, s in enumerate(SEVERITIES)}
    findings.sort(key=lambda f: (order[f["severity"]], f["key"]))
    return {"kind": kind, "fully_managed": fm, "findings": findings,
            "warning_count": sum(1 for f in findings if f["severity"] != "INFO"),
            "info_count": sum(1 for f in findings if f["severity"] == "INFO"),
            "environment_checks": bool(ctx), "context": ctx}


ICONS = {"HIGH": "🔴", "MEDIUM": "🟠", "LOW": "🟡", "INFO": "🔵"}


def print_text(name, cls, result):
    findings = result["findings"]
    print(f"🧪 {name} ({cls or 'no connector.class'}, {result['kind']})")
    if not result["environment_checks"]:
        print("   environment checks skipped (no running environment or --offline): replication factors, partitions, "
              "worker override policy")
    if not findings:
        print("✅ no warning")
        return
    width = max(len(f["key"]) for f in findings)
    for f in findings:
        value = f" = {f['value']}" if f["value"] != "" else ""
        print(f"{ICONS[f['severity']]} {f['severity']:<6} {f['key']:<{width}}{value}")
        print(f"   {'':<6} why: {f['message']}")
        print(f"   {'':<6} fix: {f['fix']}")
    if result["warning_count"]:
        print(f"❌ {result['warning_count']} warning(s), {result['info_count']} note(s)")
    else:
        print(f"✅ no warning, {result['info_count']} note(s)")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--config", required=True, help="file with the connector config as a flat JSON object")
    ap.add_argument("--context", help="file with the environment context JSON")
    ap.add_argument("--name", default="connector")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    with open(a.config) as f:
        cfg = json.load(f)
    if not isinstance(cfg, dict):
        print("config is not a JSON object", file=sys.stderr)
        return 2
    cfg = {str(k): ("" if v is None else (v if isinstance(v, str) else json.dumps(v) if isinstance(v, (dict, list)) else str(v).lower() if isinstance(v, bool) else str(v)))
           for k, v in cfg.items()}
    ctx = {}
    if a.context:
        with open(a.context) as f:
            ctx = json.load(f) or {}
    result = lint(cfg, ctx)
    if a.json:
        out = {"connector": a.name, "connector_class": cfg.get("connector.class", "")}
        out.update(result)
        out["ok"] = result["warning_count"] == 0
        print(json.dumps(out, indent=2))
    else:
        print_text(a.name, cfg.get("connector.class", ""), result)
    return 1 if result["warning_count"] else 0


if __name__ == "__main__":
    sys.exit(main())
