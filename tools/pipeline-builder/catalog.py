#!/usr/bin/env python3
"""Facts about the connector examples of kafka-docker-playground, for building pipelines.

One parser for 'playground repro bootstrap --pipeline' and the pipeline builder page, so that both see the
same topics, converters and compatibility warnings.

  catalog.py describe <example.sh>                     facts of one example (JSON)
  catalog.py check --source <a.sh> --sink <b.sh>...     compatibility findings for a pipeline (JSON)
  catalog.py catalog --root <repo> [--output <file>]    facts of every connect/ and ccloud/fm-* source and sink example
  catalog.py mermaid --source <a.sh> --sink <b.sh>... [--topic t] [--step ksqldb]   flow diagram (Mermaid)
  catalog.py html --root <repo> --output <file.html> [--site]   the pipeline builder page, catalog inside
  catalog.py pages --root <repo> --output-dir <dir> [--site]   the pipeline builder and the examples explorer pages
  catalog.py explore --root <repo>                     the data of the examples explorer (JSON)

Standard library only. The example scripts are read as text, never executed.
"""

import argparse
import datetime
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RULES_FILE = os.path.join(HERE, "rules.json")

# converters of the connect worker of the playground environments (environment/*/docker-compose.yml)
DEFAULT_KEY_CONVERTER = "org.apache.kafka.connect.storage.StringConverter"
DEFAULT_VALUE_CONVERTER = "io.confluent.connect.avro.AvroConverter"

CREATE_RE = re.compile(r"playground\s+connector\s+create-or-update\b(.*?)<<-?\s*['\"]?(\w+)['\"]?")
KV_RE = re.compile(r'^\s*"((?:[^"\\]|\\.)+)"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,?\s*$')
CONNECTOR_FLAG_RE = re.compile(r"(?:--connector|-c)[\s=]+(\"?)(\$\{?\w+\}?|[\w.\-]+)\1")
ASSIGN_RE = re.compile(r"^\s*(?:export\s+)?(\w+)=(\"?)([^\"\s;]*)\2\s*$")
CONSUME_RE = re.compile(
    r"(?:playground\s+topic\s+(?:consume|wait-for-records|get-number-records)|kafka-(?:avro-|protobuf-|json-schema-)?console-consumer)"
    r"[^\n]*?(?:--topic|\s-t)[\s=]+(['\"]?)([^\s'\"]+)\1")
PRODUCE_RE = re.compile(
    r"kafka-console-producer|kafka-avro-console-producer|kafka-json-schema-console-producer|kafka-protobuf-console-producer"
    r"|playground\s+topic\s+produce")
CRED_RE = re.compile(r"^\s*handle_(\w+?)_credentials\b", re.M)
REQUIRED_ENV_RE = re.compile(r'if\s+\[\s+-z\s+"\$(\w+)"\s+\]')
CCLOUD_RE = re.compile(r"^\s*bootstrap_ccloud_environment\b(.*)$", re.M)
START_RE = re.compile(r"playground\s+start-environment\b.*--docker-compose-override-file\s+\"?\$\{PWD\}/([^\"\s]+)\"?")
ENV_RE = re.compile(r'PLAYGROUND_ENVIRONMENT:-"?([A-Za-z0-9_-]+)')
GUARD_RE = re.compile(r"connect_cp_version_greater_than_8.*version_gt\s+\$CONNECTOR_TAG\s+\"([0-9.]+)\"")


def credentials(text):
    """the accounts an example needs: handle_<x>_credentials (aws), an Azure login, a GCP keyfile, a Confluent Cloud cluster."""
    found = set(CRED_RE.findall(text))
    if re.search(r"login_and_maybe_set_azure_subscription|\baz login\b", text):
        found.add("azure")
    if re.search(r"GCP_KEYFILE|keyfile\.json", text):
        found.add("gcp")
    if re.search(r"^\s*bootstrap_ccloud_environment\b", text, re.M) or re.search(r"start-environment\b.*--environment\s+ccloud\b", text):
        found.add("ccloud")
    if re.search(r"\.aws/credentials|\$\{?AWS_ACCESS_KEY_ID", text):
        found.add("aws")
    return sorted(found)


def required_env(text):
    """the variables the user must provide: 'if [ -z "$VAR" ]' followed by the 'VAR is not set. Export it…' error, not a
    check of a value the script computed (if [ -z "$QUEUE_SIZE" ] … Failed to retrieve queue size)."""
    lines = text.splitlines()
    found = set()
    for i, line in enumerate(lines):
        for var in REQUIRED_ENV_RE.findall(line):
            if any("is not set" in l for l in lines[i:i + 4]):
                found.add(var)
    # VAR=${VAR:-$1}: a value to export, or to pass as argument (the Databricks token...)
    for var in re.findall(r"^\s*(\w+)=\$\{(\w+):-\$\d\}", text, re.M):
        if var[0] == var[1]:
            found.add(var[0])
    return sorted(found)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def unescape(value):
    # values of an unquoted heredoc: \$ and \" are bash escapes
    return value.replace('\\"', '"').replace("\\$", "$").replace("\\\\", "\\")


def assignments(text):
    result = {}
    for line in text.splitlines():
        m = ASSIGN_RE.match(line)
        if m and m.group(1) not in result:
            result[m.group(1)] = m.group(3)
    return result


def resolve(value, variables):
    """$VAR / ${VAR} of a simple assignment of the script, else the value as written."""
    def repl(m):
        name = m.group(1) or m.group(2)
        v = variables.get(name)
        return v if v is not None and name not in v else m.group(0)
    return re.sub(r"\$\{(\w+)\}|\$(\w+)", repl, value)


def heredocs(lines):
    """(start line index, end line index, flags text, config dict) of each 'connector create-or-update' heredoc."""
    i = 0
    while i < len(lines):
        m = CREATE_RE.search(lines[i])
        if not m:
            i += 1
            continue
        delim = m.group(2)
        j = i + 1
        while j < len(lines) and lines[j].strip() != delim:
            j += 1
        if j >= len(lines):
            break
        config = {}
        for line in lines[i + 1:j]:
            kv = KV_RE.match(line)
            if kv and not kv.group(1).startswith("_"):
                config[kv.group(1)] = unescape(kv.group(2))
        yield i, j, m.group(1), config
        i = j + 1


def connector_kind(cls, dir_kind):
    lc = cls.lower()
    if "sink" in lc:
        return "sink"
    if "source" in lc or lc.startswith("io.debezium.connector") or "cdc" in lc:
        return "source"
    return dir_kind


# the databases 'playground db' knows (db_engine_from_name in scripts/cli/src/lib/db_function.sh)
DB_RE = re.compile(r"mongo(?!-express|ku)|mariadb|mysql|percona|postgres|postgis|timescale|mssql|sqlserver|azure-sql-edge|db2|oracle|db-prebuilt", re.I)


ENGINES = [("mongodb", r"mongo"), ("mysql", r"mariadb|mysql|percona"), ("postgres", r"postgres|postgis|timescale"),
           ("sqlserver", r"mssql|sqlserver|azure-sql-edge"), ("db2", r"db2"), ("oracle", r"oracle|db-prebuilt")]


def db_engine(*names):
    """engine of a database container from its image or name, as db_engine_from_name of playground db."""
    for n in names:
        for engine, regex in ENGINES:
            if n and re.search(regex, n, re.I):
                return engine
    return ""


def compose_databases(path, with_engine=False):
    """container names of the database services of a docker compose override (name or image known by playground db)."""
    dbs = []
    if not path or not os.path.isfile(path):
        return dbs
    service, info = None, {}
    in_services = False

    def flush():
        if service and service != "connect":
            name = info.get("container_name") or service
            if DB_RE.search(info.get("image", "")) or DB_RE.search(service):
                dbs.append((name, db_engine(info.get("image", ""), service)) if with_engine else name)
    for raw in read(path).splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip())
        line = raw.strip()
        if indent == 0:
            flush()
            service, info = None, {}
            in_services = line.startswith("services:")
            continue
        if not in_services:
            continue
        if indent == 2 and line.endswith(":"):
            flush()
            service, info = line[:-1].strip("'\""), {}
            continue
        if indent == 4 and ":" in line:
            k, _, v = line.partition(":")
            if k in ("image", "container_name"):
                info[k] = v.strip().strip("'\"")
    flush()
    return dbs


def compose_facts(path):
    """services and host ports of a docker compose override, with a small indentation based reader."""
    services, ports = [], []
    if not path or not os.path.isfile(path):
        return services, ports
    in_services = False
    service = None
    in_ports = False
    for raw in read(path).splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip())
        line = raw.strip()
        if indent == 0:
            in_services = line.startswith("services:")
            service = None
            continue
        if not in_services:
            continue
        if indent == 2 and line.endswith(":"):
            service = line[:-1].strip("'\"")
            services.append(service)
            in_ports = False
            continue
        if indent == 4:
            in_ports = line.startswith("ports:")
            continue
        if in_ports and line.startswith("-") and service:
            p = line[1:].strip().strip("'\"")
            parts = p.split(":")
            if len(parts) >= 2:
                host = parts[-2]
                ports.append({"service": service, "host_port": host})
    return services, ports


def describe(path, root=None):
    path = os.path.abspath(path)
    if root is None:
        root = os.path.abspath(os.path.join(HERE, "..", ".."))
    text = read(path)
    lines = text.splitlines()
    variables = assignments(text)
    rel = os.path.relpath(path, root)
    directory = os.path.dirname(path)
    dir_name = os.path.basename(directory)
    dir_kind = "source" if dir_name.endswith("-source") else "sink" if dir_name.endswith("-sink") else None
    managed = rel.startswith("ccloud/fm-")

    title = ""
    readme = os.path.join(directory, "README.md")
    if os.path.isfile(readme):
        for line in read(readme).splitlines():
            if re.match(r"^#\s+", line):
                title = re.sub(r"^#\s+", "", line).strip()
                break

    connectors = []
    for start, end, flags, config in heredocs(lines):
        name = ""
        m = CONNECTOR_FLAG_RE.search(flags)
        if m:
            name = resolve(m.group(2), variables)
        cls = config.get("connector.class", "")
        connectors.append({
            "name": name,
            "class": cls,
            "kind": connector_kind(cls, dir_kind),
            "config": config,
            "line": start + 1,
        })

    kind = dir_kind
    main = None
    for c in connectors:
        if kind and c["kind"] == kind:
            main = c
            break
    if main is None and connectors:
        main = connectors[0]
        kind = kind or main["kind"]

    config = main["config"] if main else {}
    cls = main["class"] if main else ""

    # topics: what the source example checks (the real names, after the SMTs), then what its config says
    topics_out, topics_in, topic_hints = [], [], []
    if kind == "source":
        for m in CONSUME_RE.finditer(text):
            # a topic name built from variables stays as written: the generated model defines them before the sink
            t = resolve(m.group(2), variables)
            if "$" in t:
                t = m.group(2)
            if t not in topics_out:
                topics_out.append(t)
        for key in ("kafka.topic", "topic", "topics", "kafka.topic.name", "topic.name", "topic.prefix",
                    "database.server.name", "topic.namespace.map"):
            v = config.get(key)
            if v:
                topic_hints.append({"key": key, "value": resolve(v, variables)})
                if key in ("kafka.topic", "topic", "kafka.topic.name", "topic.name") and "$" not in v:
                    t = resolve(v, variables)
                    if "$" not in t and t not in topics_out:
                        topics_out.append(t)
    topics_regex = None
    if kind == "sink":
        if config.get("topics"):
            topics_in = [t.strip() for t in resolve(config["topics"], variables).split(",") if t.strip()]
        topics_regex = config.get("topics.regex")

    key_converter = config.get("key.converter", "")
    value_converter = config.get("value.converter", "")

    def schemas_enable(prefix, converter):
        v = config.get(prefix + ".converter.schemas.enable")
        if v:
            return v
        return "true" if converter.endswith("JsonConverter") else ""

    envelope = None
    transforms = config.get("transforms", "")
    smt_types = " ".join(v for k, v in config.items() if re.match(r"^transforms\.[^.]+\.type$", k))
    if cls.startswith("io.debezium.connector") and "ExtractNewRecordState" not in smt_types:
        envelope = "debezium"
    if managed and re.search(r"CdcSource", cls) and config.get("after.state.only", "") == "false":
        envelope = "debezium"

    compose_file = None
    m = START_RE.search(text)
    if m:
        compose_file = os.path.relpath(os.path.join(directory, m.group(1)), root)
    services, ports = compose_facts(os.path.join(root, compose_file) if compose_file else None)
    databases = compose_databases(os.path.join(root, compose_file) if compose_file else None)
    database_engines = [e for _, e in compose_databases(os.path.join(root, compose_file) if compose_file else None, True)]

    cloud = None
    m = CCLOUD_RE.search(text)
    if m:
        args = [a.strip("'\"") for a in m.group(1).split()]
        cloud = {"args": m.group(1).strip(), "cloud": args[0] if args else "", "region": args[1] if len(args) > 1 else ""}

    guard = GUARD_RE.search(text)
    env = ENV_RE.search(text)
    data_format = config.get("output.data.format") if kind == "source" else config.get("input.data.format")

    return {
        "path": rel,
        "dir": os.path.dirname(rel),
        "name": os.path.splitext(os.path.basename(rel))[0],
        "title": title,
        "kind": kind,
        "managed": managed,
        "connector": {"name": main["name"], "class": cls, "line": main["line"]} if main else None,
        "connectors": [{"name": c["name"], "class": c["class"], "kind": c["kind"]} for c in connectors],
        "config": config,
        "topics_out": topics_out,
        "topic_hints": topic_hints,
        "topics_in": topics_in,
        "topics_regex": topics_regex,
        "key_converter": key_converter,
        "value_converter": value_converter,
        "key_converter_effective": key_converter or ("" if managed else DEFAULT_KEY_CONVERTER),
        "value_converter_effective": value_converter or ("" if managed else DEFAULT_VALUE_CONVERTER),
        "key_schemas_enable": schemas_enable("key", key_converter),
        "value_schemas_enable": schemas_enable("value", value_converter),
        "data_format": data_format or "",
        "envelope": envelope,
        "transforms": transforms,
        "compose_file": compose_file,
        "services": services,
        "ports": ports,
        "databases": databases,
        "database_engines": database_engines,
        "credentials": credentials(text),
        "required_env": required_env(text),
        "cloud": cloud,
        "environment": env.group(1) if env else ("ccloud" if cloud else ""),
        "producer": bool(PRODUCE_RE.search(text)),
        "cp8_connector_tag_above": guard.group(1) if guard else None,
    }


# ---------------------------------------------------------------- rules

def load_rules():
    with open(RULES_FILE, encoding="utf-8") as f:
        return json.load(f)["rules"]


def field(facts, path):
    """value of source.class, sink.config.pk.mode... as a string ('' when missing)."""
    side, _, rest = path.partition(".")
    obj = facts.get(side) or {}
    if rest.startswith("config."):
        v = (obj.get("config") or {}).get(rest[len("config."):], "")
    elif rest == "class":
        v = (obj.get("connector") or {}).get("class", "")
    else:
        v = obj.get(rest, "")
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)


def matches(conditions, facts):
    return all(re.search(regex, field(facts, path)) for path, regex in conditions.items())


def check(source, sinks, rules=None):
    rules = rules if rules is not None else load_rules()
    findings = []
    for sink in sinks:
        facts = {"source": source, "sink": sink}
        for rule in rules:
            if not matches(rule.get("when", {}), facts):
                continue
            unless = rule.get("unless", [])
            if isinstance(unless, dict):
                unless = [unless]
            if any(matches(u, facts) for u in unless):
                continue
            findings.append({
                "rule": rule["id"],
                "severity": rule["severity"],
                "sink": sink["path"],
                "message": rule["message"],
                "add_to_sink": rule.get("add_to_sink", {}),
            })
    # docker compose: the same service, or the same host port, in two examples
    if not source.get("managed"):
        owners = {}
        for ex in [source] + list(sinks):
            for s in ex.get("services", []):
                if s != "connect":
                    owners.setdefault(("service", s), []).append(ex["path"])
            for p in ex.get("ports", []):
                owners.setdefault(("port", p["host_port"]), []).append(ex["path"] + " (" + p["service"] + ")")
        for (what, name), paths in owners.items():
            if len(set(paths)) > 1:
                findings.append({
                    "rule": "compose-" + what + "-conflict",
                    "severity": "warn",
                    "sink": "",
                    "message": ("service '%s' is defined by several examples: %s. The definition of the source wins when "
                                "they differ" if what == "service" else
                                "host port %s is published by several examples: %s") % (name, ", ".join(sorted(set(paths)))),
                    "add_to_sink": {},
                })
    return findings


def mermaid(source, sinks, topic, step=None):
    def node_id(i):
        return "n%d" % i

    def label(ex):
        c = ex.get("connector") or {}
        return "%s<br/>%s" % (ex["dir"].split("/")[-1], c.get("class", "").split(".")[-1])

    out = ["flowchart LR"]
    if source:
        out.append('  src["%s"]' % label(source))
    out.append('  topic[("%s")]' % topic)
    if source:
        out.append("  src --> topic")
    last = "topic"
    if step:
        out.append('  step{{"%s"}}' % step)
        out.append('  topic2[("%s")]' % (topic + "_" + step))
        out.append("  topic --> step --> topic2")
        last = "topic2"
    for i, sink in enumerate(sinks):
        out.append('  %s["%s"]' % (node_id(i), label(sink)))
        out.append("  %s --> %s" % (last, node_id(i)))
    return "\n".join(out)


PIPELINE_HEADER_RE = re.compile(r"^# 🔗 pipeline: (\S+)(?: -> (ksqldb|flink))? -> (.+?) \(topic (.+)\)\s*$")


def from_model(model, root):
    """source, sinks, topic and step of the '# 🔗 pipeline:' line written in the header of a model by bootstrap."""
    for line in read(model).splitlines()[:40]:
        m = PIPELINE_HEADER_RE.match(line)
        if m:
            sinks = [s.strip() for s in m.group(3).split(",") if s.strip()]
            return (describe(os.path.join(root, m.group(1)), root), [describe(os.path.join(root, s), root) for s in sinks],
                    m.group(4), m.group(2))
    return None


# ---------------------------------------------------------------- catalog

CONTENT_LINE_RE = re.compile(r"images/icons/([^\"\s)]+)[^\[]*\[([^\]]+)\](?:\([^)]*\))?(.*)\s:([a-z0-9/_.\-]+):\s*$")


def content_icons(root):
    """{example folder: (icon file, display name)} from the examples page (docs/content-template.md)."""
    return {d: (icon, name) for d, (icon, name, _) in content_entries(root).items()}


def content_entries(root):
    """{example folder: (icon file, display name, note)} from the examples page (docs/content-template.md); the note is
    the text after the link: (also with 🌐 proxy), (also with 🔑 SSL and mTLS)…"""
    found = {}
    path = os.path.join(root, "docs", "content-template.md")
    if os.path.isfile(path):
        for line in read(path).splitlines():
            m = CONTENT_LINE_RE.search(line)
            if m and m.group(4) not in found:
                note = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", m.group(3)).strip().strip(":").strip()
                note = re.sub(r"^\((.*)\)$", r"\1", note)
                found[m.group(4)] = (m.group(1), m.group(2).strip(), note)
    return found

def catalog(root):
    icons = content_icons(root)
    # the icon of a class, for the examples missing from the examples page (tools/report-common/connector_icons.json)
    class_icons = {}
    try:
        with open(os.path.join(root, "tools", "report-common", "connector_icons.json"), encoding="utf-8") as f:
            class_icons = json.load(f).get("classes", {})
    except (OSError, ValueError):
        pass
    examples = []
    folders = []
    for parent in ("connect", "ccloud"):
        base = os.path.join(root, parent)
        if not os.path.isdir(base):
            continue
        for d in sorted(os.listdir(base)):
            if parent == "ccloud" and not d.startswith("fm-"):
                continue
            if not (d.endswith("-source") or d.endswith("-sink")):
                continue
            folders.append(os.path.join(base, d))
    for folder in folders:
        for f in sorted(os.listdir(folder)):
            if not f.endswith(".sh") or f == "stop.sh":
                continue
            path = os.path.join(folder, f)
            try:
                text = read(path)
            except OSError:
                continue
            if "scripts/utils.sh" not in text:
                continue
            try:
                facts = describe(path, root)
            except Exception as e:  # one odd example must not break the catalog
                print("⚠️ %s: %s" % (path, e), file=sys.stderr)
                continue
            # the full config is only needed by bootstrap: keep the keys the rules and the page use
            keep = re.compile(r"^(connector\.class|topics|topics\.regex|kafka\.topic|topic\.prefix|transforms.*|"
                              r"(key|value)\.converter.*|pk\.mode|pk\.fields|delete\.enabled|key\.ignore|format\.class|"
                              r"input\.data\.format|output\.data\.format|output\.key\.format|after\.state\.only|"
                              r"insert\.mode|schema\.ignore|tasks\.max|flush\.size)$")
            facts["config"] = {k: v for k, v in facts["config"].items() if keep.match(k)}
            facts["icon"], facts["display"] = icons.get(facts["dir"], ("", ""))
            if not facts["icon"] and facts["connector"]:
                facts["icon"] = class_icons.get(facts["connector"]["class"].split(".")[-1], "")
            examples.append(facts)
    return {
        "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "default_key_converter": DEFAULT_KEY_CONVERTER,
        "default_value_converter": DEFAULT_VALUE_CONVERTER,
        "rules": load_rules(),
        "examples": examples,
    }


# ---------------------------------------------------------------- examples explorer

EXPLORER_FOLDERS = ["connect", "ccloud", "ksqldb", "flink", "schema-registry", "rest-proxy", "multi-data-center",
                    "other", "operator", "academy", "environment"]
HONORS_ENV_RE = re.compile(r'PLAYGROUND_ENVIRONMENT=\$\{PLAYGROUND_ENVIRONMENT:-')
DOCS_URL_RE = re.compile(r"Quickly test[^\n]*?\((https?://[^)\s]+)\)")


def topics_of(rel, title, env, body):
    """the topics of 'playground find-example --category security|broker|cfk|client' (find_examples in cli_function.sh)."""
    path = (rel + "\n" + title).lower()
    body = body.lower()
    conn = re.match(r"^(connect/|academy/|ccloud/fm-)", rel) is not None
    topics = []
    if ((not conn and re.search(r"(rbac|ldap|kerberos|sasl|ssl|mtls|oauth|oidc|audit|secret|security|authentication|csfle|certificate|redactor)", path))
            or (not conn and re.search(r"(^|[^a-z])(acls?|tls|krb5?)([^a-z]|$)", path))
            or re.match(r"^(sasl|2way-ssl|kerberos|ssl_kerberos|ldap|rbac|cfk-rbac)", env)
            or "playground rbac " in body or (not conn and "playground tools cert " in body)):
        topics.append("security")
    if (re.search(r"(cluster-linking|mirrormaker|replicator|offsets-migrator)", path) or rel.startswith("multi-data-center/")
            or (not conn and not rel.startswith("ksqldb/") and re.search(
                r"(broker|topic-policy|transaction|kraft|zookeeper|tiered-storage|quota|reassign|leader-election|rebalancer|log-compaction)", path))
            or "playground broker " in body):
        topics.append("broker")
    if re.search(r"(cfk|kubernetes|k8s|(^|[^a-z])operator)", path) or env.startswith("cfk"):
        topics.append("cfk")
    if re.search(r"(client|producer|consumer|kafkajs|dotnet|librdkafka|kcat|golang|python)", path):
        topics.append("client")
    return topics


AREAS_BY_HEADING = [("🔗 Connect", "connect"), ("🖥️ Brokers, clients and observability", "core"),
                    ("🌊 Streams, schemas and non-Java clients", "streams"), ("🛡️ Platform, security and Cloud infra", "platform")]
AREA_OF_CATEGORY = {"source": "connect", "sink": "connect", "smt": "connect", "connect": "connect", "fully-managed": "connect",
                    "custom-connector": "connect", "ksqldb": "streams", "flink": "streams", "schema-registry": "streams",
                    "rest-proxy": "streams", "multi-data-center": "core", "environment": "platform"}


def content_areas(root):
    """{example folder: area} from the '## <area>' sections of the examples page (docs/content-template.md), the areas
    of https://kafka-docker-playground.io/#/areas."""
    areas = {}
    path = os.path.join(root, "docs", "content-template.md")
    if not os.path.isfile(path):
        return areas
    current = None
    for line in read(path).splitlines():
        if line.startswith("## "):
            current = next((key for heading, key in AREAS_BY_HEADING if line[3:].strip() == heading), None)
            continue
        m = re.search(r"\s:([a-z0-9/_.\-]+):\s*$", line)
        if m and current and m.group(1) not in areas:
            areas[m.group(1)] = current
    return areas


def compose_plugins(path):
    """owner/name of the plugins of CONNECT_PLUGIN_PATH (/usr/share/confluent-hub-components/<owner>-<name>)."""
    plugins = []
    if not path or not os.path.isfile(path):
        return plugins
    for m in re.finditer(r"confluent-hub-components/([a-z0-9._]+)-([a-z0-9._-]+)", read(path), re.I):
        owner, name = m.group(1), m.group(2)
        if owner in ("java", "filestream") or name == "hub-components":
            continue
        if owner + "/" + name not in plugins:
            plugins.append(owner + "/" + name)
    return plugins


def http_json(url, timeout=15):
    import urllib.request
    req = urllib.request.Request(url, headers={"User-Agent": "kafka-docker-playground-docs"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


DOCKER_HUB_TAGS = "https://hub.docker.com/v2/repositories/confluentinc/cp-server-connect/tags"
# Docker Hub refuses anonymous requests beyond the first 1000 tags of a query: a filter matching more is split into
# narrower ones (as 'playground generate-tag-list' does)
DOCKER_HUB_MAX_TAGS = 1000


def docker_hub_tags(name, depth=0):
    """the names of the tags of cp-server-connect containing <name>, every page, split when the query matches too many."""
    from concurrent.futures import ThreadPoolExecutor
    try:
        first = http_json("%s?page_size=100&page=1&name=%s" % (DOCKER_HUB_TAGS, name))
    except Exception:
        return []
    count = first.get("count") or 0
    if count > DOCKER_HUB_MAX_TAGS and depth < 3:
        out = []
        for d in "0123456789":
            out += docker_hub_tags(name + d, depth + 1)
        return out
    names = [t.get("name", "") for t in first.get("results", [])]
    pages = range(2, min((count + 99) // 100, DOCKER_HUB_MAX_TAGS // 100) + 1)

    def page(n):
        try:
            return [t.get("name", "") for t in http_json("%s?page_size=100&page=%d&name=%s" % (DOCKER_HUB_TAGS, n, name)).get("results", [])]
        except Exception:
            return []
    with ThreadPoolExecutor(max_workers=8) as pool:
        for chunk in pool.map(page, pages):
            names += chunk
    return names


def cp_versions(root, fetch=True):
    """the Confluent Platform versions, newest first: the cache of 'playground generate-tag-list', else Docker Hub (one
    query per major version from 5, until a major without a version of its own)."""
    found = set()
    cache = os.path.join(root, "scripts", "cli", "tag-list.txt")
    if os.path.isfile(cache):
        for line in read(cache).splitlines():
            v = line.split(" ")[0]
            if re.match(r"^\d+\.\d+\.\d+$", v):
                found.add(v)
    if not found and fetch:
        major = 5
        while major < 20:
            # the filter is a substring: 7.5.0 matches "5." too, only X.Y.Z of this major count
            versions = set(n for n in docker_hub_tags("%d." % major) if re.match(r"^%d\.\d+\.\d+$" % major, n))
            if not versions:
                break
            found |= versions
            major += 1
    return sorted(found, key=lambda v: [int(x) for x in v.split(".")], reverse=True)


def plugin_versions(plugins):
    """{owner/name: [{"v", "date"}…] newest first} from Confluent Hub, for the website (its browser calls are refused)."""
    from concurrent.futures import ThreadPoolExecutor

    def one(plugin):
        try:
            data = http_json("https://api.hub.confluent.io/api/plugins/%s/versions" % plugin)
            return plugin, [{"v": x["version"], "date": x.get("release_date") or ""} for x in reversed(data) if x.get("version")]
        except Exception:
            return plugin, None
    out = {}
    with ThreadPoolExecutor(max_workers=12) as pool:
        for plugin, versions in pool.map(one, sorted(set(plugins))):
            if versions:
                out[plugin] = versions
    return out


def sql_datagen_load(directory):
    """the load script of the example inserts rows in one-row transactions (what --enable-sql-datagen runs)."""
    load = os.path.join(directory, "benchmark-load.bash")
    if not os.path.isfile(load):
        return False
    text = read(load)
    return "benchmark_sql_load" in text or "small-txn" in text


def category_of(rel, kind):
    top = rel.split("/")[0]
    d = rel.split("/")[1] if "/" in rel else ""
    if top == "connect":
        if kind in ("source", "sink"):
            return kind
        # neither a source nor a sink example: the SMT examples (connect-testing-smt), else another Connect example
        return "smt" if "smt" in d else "connect"
    if top == "ccloud":
        if d.startswith("fm-"):
            return "fully-managed"
        if d.startswith("custom-connector"):
            return "custom-connector"
        return "ccloud"
    return top


def explore(root):
    """every runnable example, for the examples explorer page."""
    entries = content_entries(root)
    icons = {d: (i, n) for d, (i, n, _) in entries.items()}
    areas = content_areas(root)
    class_icons = {}
    try:
        with open(os.path.join(root, "tools", "report-common", "connector_icons.json"), encoding="utf-8") as f:
            class_icons = json.load(f).get("classes", {})
    except (OSError, ValueError):
        pass
    out = []
    for top in EXPLORER_FOLDERS:
        base = os.path.join(root, top)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = sorted(d for d in dirnames if not d.startswith(".") and d not in ("deep-dive-labs", "node_modules", "target"))
            if dirpath[len(root):].count(os.sep) > 5:
                continue
            for f in sorted(filenames):
                if not f.endswith(".sh") or f == "stop.sh":
                    continue
                path = os.path.join(dirpath, f)
                try:
                    text = read(path)
                except OSError:
                    continue
                if "scripts/utils.sh" not in text:
                    continue
                try:
                    facts = describe(path, root)
                except Exception as e:  # one odd example must not break the page
                    print("⚠️ %s: %s" % (path, e), file=sys.stderr)
                    continue
                rel = facts["path"]
                readme = os.path.join(os.path.dirname(path), "README.md")
                docs_url = ""
                if os.path.isfile(readme):
                    m = DOCS_URL_RE.search(read(readme))
                    if m:
                        docs_url = m.group(1).split("#")[0]
                icon, display = icons.get(facts["dir"], ("", ""))
                cls = facts["connector"]["class"] if facts["connector"] else ""
                if not icon and cls:
                    icon = class_icons.get(cls.split(".")[-1], "")
                env = facts["environment"]
                category = category_of(rel, facts["kind"])
                topics = topics_of(rel, facts["title"], env, text)
                area = areas.get(facts["dir"]) or AREA_OF_CATEGORY.get(category) or \
                    ("platform" if "security" in topics or "cfk" in topics else "core" if "broker" in topics or "client" in topics else "")
                out.append({
                    "path": rel, "dir": facts["dir"], "name": facts["name"],
                    "display": display, "title": facts["title"], "icon": icon,
                    "note": entries.get(facts["dir"], ("", "", ""))[2],
                    "category": category, "area": area, "kind": facts["kind"], "managed": facts["managed"],
                    "plugins": compose_plugins(os.path.join(root, facts["compose_file"])) if facts["compose_file"] else [],
                    "connector": facts["connector"], "classes": sorted(set(c["class"] for c in facts["connectors"] if c["class"])),
                    "credentials": facts["credentials"], "required_env": facts["required_env"],
                    "honors_environment": bool(HONORS_ENV_RE.search(text)), "environment": env,
                    "connector_example": rel.startswith("connect/") and bool(facts["connectors"]),
                    "pipeline": facts["kind"] in ("source", "sink") and bool(facts["connector"]) and (rel.startswith("connect/") or rel.startswith("ccloud/fm-")),
                    "docs_url": docs_url,
                    # --enable-sql-datagen injects rows with the load script next to the example, in transactions of one
                    # row (--shape small-txn): the database sources (JDBC, Debezium, Oracle CDC, XStream)
                    "sql_datagen": sql_datagen_load(os.path.dirname(path)),
                    "topics": topics,
                })
    return out


def run_options(root):
    """the flags of 'playground run' the explorer offers, from the generated CLI description (scripts/cli/playground.json)."""
    opts = {"environments": [], "enable": [], "default_tag": ""}
    try:
        with open(os.path.join(root, "scripts", "cli", "playground.json"), encoding="utf-8") as f:
            cli = json.load(f)
        run = next(c for c in cli["subcommands"] if c.get("name") == "run")
    except (OSError, ValueError, StopIteration, KeyError):
        return opts
    for o in run.get("options", []):
        name = o["names"][0]
        desc = o.get("description", "")
        first = desc.split("\n")[0].strip()
        if name == "--environment":
            for line in desc.splitlines():
                m = re.match(r"^- ([a-z0-9_-]+)(?: \((.*)\))?\s*$", line.strip())
                if m:
                    opts["environments"].append({"name": m.group(1), "note": m.group(2) or ""})
        elif name.startswith("--enable-") and not o.get("argument") and name not in ("--enable-legacy-control-center", "--enable-kraft"):
            opts["enable"].append({"flag": name, "help": first, "ccloud": "not supported with ccloud" not in desc})
    m = re.search(r"TAG=([0-9.]+) # default tag", read(os.path.join(root, "scripts", "utils.sh")))
    if m:
        opts["default_tag"] = m.group(1)
    return opts


def report_banner(page):
    """the banner of the HTML reports of playground: their gradient (report_html.banner_css) and their 🐳 badge (kdp_brand),
    so that the two pages look like the reports; the fallback of ui.css without tools/report-common."""
    try:
        sys.dont_write_bytecode = True
        sys.path.insert(0, os.path.join(HERE, "..", "report-common"))
        import report_html
        css, badge = report_html.banner_css("header"), "<div>%s</div>" % report_html.kdp_brand()
    except Exception:
        css, badge = "", ""
    return page.replace("<!--__BANNER__-->", css, 1).replace("<!--__KDP_BRAND__-->", badge, 1)


def explorer_html(root, output, site=False):
    """the examples explorer page, with every example and the run options inside."""
    page = read(os.path.join(HERE, "explorer.html"))
    page = report_banner(page.replace("/*__UI_CSS__*/", read(os.path.join(HERE, "ui.css")), 1))
    examples = explore(root)
    # the versions offered in the dropdowns: the website collects those of the plugins (Confluent Hub refuses its browser
    # calls), a local page asks Confluent Hub when an example is picked (it allows pages opened from a file)
    versions = {"cp": cp_versions(root), "plugins": {}}
    if site:
        versions["plugins"] = plugin_versions([p for e in examples for p in e["plugins"][:1]])
    data = {"generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "examples": examples, "run": run_options(root), "versions": versions}
    page = page.replace("/*__EXPLORER_DATA__*/null", json.dumps(data, separators=(",", ":")).replace("</", "<\\/"), 1)
    page = page.replace('/*__PIPELINE_ROOT__*/""', json.dumps("" if site else root), 1)
    icons = "https://raw.githubusercontent.com/vdesabou/kafka-docker-playground/master/images/icons/"
    if not site and os.path.isdir(os.path.join(root, "images", "icons")):
        icons = "file://" + os.path.join(root, "images", "icons") + "/"
    page = re.sub(r'/\*__PIPELINE_ICONS__\*/"[^"]*"', lambda _: json.dumps(icons), page, count=1)
    with open(output, "w", encoding="utf-8") as f:
        f.write(page)


def pages(root, output_dir, site=False):
    """both pages side by side (they link to each other)."""
    os.makedirs(output_dir, exist_ok=True)
    html(root, os.path.join(output_dir, "pipeline-builder.html"), site)
    explorer_html(root, os.path.join(output_dir, "examples-explorer.html"), site)


def html(root, output, site=False):
    """the pipeline builder page, with the catalog inside (site: the root folder is left out, the command uses $PWD)."""
    with open(os.path.join(HERE, "builder.html"), encoding="utf-8") as f:
        page = f.read()
    page = report_banner(page.replace("/*__UI_CSS__*/", read(os.path.join(HERE, "ui.css")), 1))
    data = json.dumps(catalog(root), separators=(",", ":")).replace("</", "<\\/")
    page = page.replace("/*__PIPELINE_CATALOG__*/null", data, 1)
    page = page.replace('/*__PIPELINE_ROOT__*/""', json.dumps("" if site else root), 1)
    # the icons of the examples page: the files of the clone locally (works offline), GitHub on the website
    icons = "https://raw.githubusercontent.com/vdesabou/kafka-docker-playground/master/images/icons/"
    if not site and os.path.isdir(os.path.join(root, "images", "icons")):
        icons = "file://" + os.path.join(root, "images", "icons") + "/"
    page = re.sub(r'/\*__PIPELINE_ICONS__\*/"[^"]*"', lambda _: json.dumps(icons), page, count=1)
    with open(output, "w", encoding="utf-8") as f:
        f.write(page)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("describe")
    p.add_argument("file")
    p.add_argument("--root")
    p = sub.add_parser("check")
    p.add_argument("--source", required=True)
    p.add_argument("--sink", action="append", default=[])
    p.add_argument("--root")
    p = sub.add_parser("mermaid")
    p.add_argument("--model", help="read the chain from the '# 🔗 pipeline:' line of a reproduction model")
    p.add_argument("--source")
    p.add_argument("--sink", action="append", default=[])
    p.add_argument("--topic", default="topic")
    p.add_argument("--step")
    p.add_argument("--root")
    p = sub.add_parser("html")
    p.add_argument("--root", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--site", action="store_true", help="for the website: commands use $PWD instead of the root folder")
    p = sub.add_parser("pages")
    p.add_argument("--root", required=True)
    p.add_argument("--output-dir", required=True)
    p.add_argument("--site", action="store_true", help="for the website: commands use $PWD instead of the root folder")
    p = sub.add_parser("explore")
    p.add_argument("--root", required=True)
    p = sub.add_parser("catalog")
    p.add_argument("--root", required=True)
    p.add_argument("--output")
    args = parser.parse_args()

    root = os.path.abspath(args.root) if getattr(args, "root", None) else None
    if args.command == "describe":
        json.dump(describe(args.file, root), sys.stdout, indent=2)
    elif args.command == "check":
        source = describe(args.source, root)
        sinks = [describe(s, root) for s in args.sink]
        json.dump(check(source, sinks), sys.stdout, indent=2)
    elif args.command == "mermaid":
        if args.model:
            found = from_model(args.model, root or os.path.abspath(os.path.join(HERE, "..", "..")))
            if not found:
                sys.exit(1)
            source, sinks, topic, step = found
            print(mermaid(source, sinks, topic, step))
            return
        source = describe(args.source, root) if args.source else None
        sinks = [describe(s, root) for s in args.sink]
        print(mermaid(source, sinks, args.topic, args.step))
        return
    elif args.command == "html":
        html(root, os.path.abspath(args.output), args.site)
        print("🔗 pipeline builder: %s" % args.output, file=sys.stderr)
        return
    elif args.command == "pages":
        pages(root, os.path.abspath(args.output_dir), args.site)
        print("📄 %s/pipeline-builder.html, %s/examples-explorer.html" % (args.output_dir, args.output_dir), file=sys.stderr)
        return
    elif args.command == "explore":
        json.dump({"examples": explore(root), "run": run_options(root)}, sys.stdout, indent=2)
    elif args.command == "catalog":
        data = catalog(root)
        if args.output:
            with open(args.output, "w", encoding="utf-8") as f:
                json.dump(data, f, separators=(",", ":"))
            print("%d examples -> %s" % (len(data["examples"]), args.output), file=sys.stderr)
            return
        json.dump(data, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
