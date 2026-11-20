#!/usr/bin/env python3
"""Append sink examples to a reproduction model: 'playground repro bootstrap --pipeline'.

  pipeline.py --model <generated model .sh> --base <base example .sh> --sink <sink example .sh>... \
              [--topic <topic>] [--step ksqldb] [--root <repo>]

The model is the base example as bootstrap generated it (header, compose override, --config...). The base is a
source example (source -> sinks), or a sink example (fan-out: its producer feeds the other sinks too). The model is
rewritten in place. Messages go to stdout, one per line, prefixed with 'I ' (info), 'W ' (warning) or 'E ' (error,
exit 1). The docker compose files are merged by the caller (yq).

What it does, for each sink:
  * its lines before the environment starts (credentials, downloads) go before the start of the model
  * every producer of the sink example is replaced with a no-op: the records come from the base
  * the sink reads the topic of the base ("topics", or "topics.regex" replaced), and the old topic name is replaced
    in the rest of its section (bucket paths, table names, index names)
  * converters (self-managed) or input.data.format (fully managed) are the ones the base writes
  * the 'fix' rules of rules.json are applied (ExtractNewRecordState for a Debezium envelope...)
  * duplicated connector names are renamed, connector_name of fully managed sinks becomes connector_name_<n>
  * after the sink connector: 'playground connector show-lag' waits until it has consumed every record; the checks
    of the sink example follow, under set +e, since they were written for the records of its producer
  * version guards are commented out: --connector-tag would apply to every connector of the model
"""

import argparse
import os
import re
import sys

# no __pycache__ in the checkout of the user
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import catalog  # noqa: E402

PRODUCE_LINE_RE = re.compile(r"^\s*(?!#).*?(" + catalog.PRODUCE_RE.pattern + r")")
HEREDOC_RE = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?")
GUARD_START_RE = re.compile(r"^\s*if\s+connect_cp_version_greater_than_8\b")
UTILS_RE = re.compile(r"^source .*scripts/utils\.sh")
SM_ANCHOR_RE = re.compile(r"^\s*playground\s+start-environment\b")
FM_ANCHOR_RE = re.compile(r"^\s*bootstrap_ccloud_environment\b")
PG_ENV_RE = re.compile(r"^\s*PLAYGROUND_ENVIRONMENT=")
TEARDOWN_RE = re.compile(r'^\s*log\s+"Do you want to delete')
# the Flink step: the versions of the flink/flink-sql-kafka example (the kafka sql connector is released for one Flink minor)
FLINK_TAG = "2.2"
FLINK_KAFKA_JAR = "https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka/5.0.0-2.2/flink-sql-connector-kafka-5.0.0-2.2.jar"
FLINK_AVRO_CONFLUENT_JAR = "https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-avro-confluent-registry/2.2.0/flink-sql-avro-confluent-registry-2.2.0.jar"
STORAGE_SINK_RE = re.compile(r"(S3SinkConnector|S3_SINK|GcsSink|AzureBlob|DataLakeGen[12]|HdfsSinkConnector|Hdfs3SinkConnector)")
KV_LINE_RE = re.compile(r'^(\s*)"([^"]+)"\s*:\s*"((?:[^"\\]|\\.)*)"(\s*,?)\s*$')

messages = []


def info(msg):
    messages.append("I " + msg)


def warn(msg):
    messages.append("W " + msg)


def fail(msg):
    for m in messages:
        print(m)
    print("E " + msg)
    sys.exit(1)


def find(lines, regex, start=0):
    for i in range(start, len(lines)):
        if regex.search(lines[i]):
            return i
    return -1


def comment_guards(lines, origin):
    """comment out the connect_cp_version_greater_than_8 blocks (if ... fi)."""
    out = []
    i = 0
    while i < len(lines):
        if GUARD_START_RE.search(lines[i]):
            j = i
            while j < len(lines) and not re.match(r"^\s*fi\b", lines[j]):
                j += 1
            out.append("# 🔗 pipeline: version guard of %s commented out (--connector-tag would apply to every connector)" % origin)
            out.extend("# " + l for l in lines[i:j + 1])
            i = j + 1
            continue
        out.append(lines[i])
        i += 1
    return out


def remove_producers(lines):
    """replace each producer (with its heredoc and continuation lines) with a no-op, keeping the bash syntax valid."""
    out = []
    removed = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        if PRODUCE_LINE_RE.search(line):
            end = i
            while lines[end].rstrip().endswith("\\") and end + 1 < len(lines):
                end += 1
            block = " ".join(lines[i:end + 1])
            m = HEREDOC_RE.search(block)
            if m:
                delim = m.group(1)
                k = end + 1
                while k < len(lines) and lines[k].strip() != delim:
                    k += 1
                end = min(k, len(lines) - 1)
            # the log line announcing it goes too
            if out and re.match(r'^\s*log\s+".*(send|sending|produc|messages|records|inject)', out[-1], re.I):
                out.pop()
            indent = re.match(r"^\s*", line).group(0)
            out.append(indent + ": # 🔗 pipeline: producer of the sink example removed, the records come from the base example")
            removed += 1
            i = end + 1
            continue
        out.append(line)
        i += 1
    return out, removed


def heredoc_span(lines, start=0):
    """(start, end) of the first 'connector create-or-update' heredoc at or after start."""
    for i in range(start, len(lines)):
        m = catalog.CREATE_RE.search(lines[i])
        if m:
            delim = m.group(2)
            for j in range(i + 1, len(lines)):
                if lines[j].strip() == delim:
                    return i, j
    return -1, -1


VALUE_LINE_RE = re.compile(r'^\s*"[^"]+"\s*:')


def fix_commas(body):
    """a comma after every "key": value line but the last one."""
    idx = [i for i, l in enumerate(body) if VALUE_LINE_RE.match(l)]
    for n, i in enumerate(idx):
        l = body[i].rstrip()
        if l.endswith(","):
            l = l[:-1].rstrip()
        body[i] = l + ("," if n < len(idx) - 1 else "")
    return body


def set_keys(lines, start, end, values, remove_regex=None, raw=None):
    """in the heredoc lines[start..end]: drop the keys matching remove_regex, set values (after connector.class);
    raw: "key": value lines inserted as written (values with bash escapes)."""
    raw = raw or []
    raw_keys = set(KV_LINE_RE.match(l).group(2) for l in raw if KV_LINE_RE.match(l))
    kept = []
    for l in lines[start + 1:end]:
        m = KV_LINE_RE.match(l)
        if m and (m.group(2) in values or m.group(2) in raw_keys or (remove_regex and re.search(remove_regex, m.group(2)))):
            continue
        kept.append(l)
    indent = "  "
    pos = None
    for idx, l in enumerate(kept):
        m = KV_LINE_RE.match(l)
        if m:
            indent = m.group(1)
            if m.group(2) == "connector.class":
                pos = idx + 1
                break
    if pos is None:
        pos = next((i + 1 for i, l in enumerate(kept) if l.strip() == "{"), 0)
    kept[pos:pos] = [indent + '"%s": "%s"' % (k, v.replace('"', '\\"')) for k, v in values.items()] + \
        [indent + l.strip() for l in raw]
    return lines[:start + 1] + fix_commas(kept) + lines[end:]


def raw_converter_lines(lines, start, end):
    return [l for l in lines[start + 1:end]
            if KV_LINE_RE.match(l) and re.match(r"^(key|value)\.converter", KV_LINE_RE.match(l).group(2))]


def replace_topic_token(text, old, new):
    # the topic as a whole token: not inside a longer name (letters, digits, _ . -)
    pattern = r"(?<![A-Za-z0-9_.\-])" + re.escape(old) + r"(?![A-Za-z0-9_\-]|\.[A-Za-z0-9_])"
    return re.sub(pattern, lambda m: new, text, flags=re.I)


def connector_names(lines):
    names = set()
    for l in lines:
        for m in catalog.CONNECTOR_FLAG_RE.finditer(l):
            if not m.group(2).startswith("$"):
                names.add(m.group(2))
    return names


DB_CMD_RE = re.compile(r"^(\s*playground\s+db\s+(?:sql|wait-for-rows|cdc-check)\b)(.*)$")


def pin_database(lines, container):
    """--container <db> on the 'playground db' calls that have none: several databases run in a pipeline."""
    out = []
    for l in lines:
        m = DB_CMD_RE.match(l)
        if m and not re.search(r"(\s--container|\s-c)[\s=]", m.group(2)):
            l = "%s --container %s%s" % (m.group(1), container, m.group(2))
        out.append(l)
    return out


FUNC_START_RE = re.compile(r"^(?:function\s+(\w+)\s*(?:\(\))?|(\w+)\s*\(\))\s*\{?\s*$")
EXIT_TRAP_RE = re.compile(r"^(\s*)trap\s+(?:'([^']*)'|\"([^\"]*)\"|(\S+))\s+EXIT\s*$")


HEREDOC_START_RE = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?")


def skip_heredoc(lines, i):
    """index of the last line of the heredoc started on line i (i when there is none): its body is not bash."""
    m = HEREDOC_START_RE.search(lines[i].replace("<<<", ""))
    if not m:
        return i
    j = i + 1
    while j < len(lines) and lines[j].strip() != m.group(1):
        j += 1
    return min(j, len(lines) - 1)


def functions(lines):
    """{name: (first line, last line)} of the functions defined at the top level (body closed by '}' at column 0)."""
    found = {}
    i = 0
    while i < len(lines):
        end = skip_heredoc(lines, i)
        if end != i:
            i = end + 1
            continue
        m = FUNC_START_RE.match(lines[i])
        # a definition opens its body on the same line or the next one ('print()' in a quoted python string does not)
        if m and "{" not in lines[i] and not (i + 1 < len(lines) and lines[i + 1].strip().startswith("{")):
            m = None
        if m:
            j = i + 1
            while j < len(lines) and not re.match(r"^\}\s*$", lines[j]):
                j = skip_heredoc(lines, j) + 1
            found[m.group(1) or m.group(2)] = (i, j)
            i = j + 1
            continue
        i += 1
    return found


def split_teardown(lines):
    """the 'Do you want to delete ... check_if_continue ... connector delete' end of a fully managed example: the last
    one at the top level (the same question inside a cleanup function stays where it is)."""
    inside = set()
    for start, end in functions(lines).values():
        inside.update(range(start, end + 1))
    candidates = [i for i, l in enumerate(lines) if TEARDOWN_RE.search(l) and i not in inside and not l.startswith((" ", "\t"))]
    if not candidates:
        return lines, []
    i = candidates[-1]
    return lines[:i], lines[i:]


def chain_exit_traps(lines):
    """each top-level 'trap X EXIT' replaces the previous one: in a model made of several examples, it runs X and
    then what was trapped before, so that every cleanup runs."""
    out = []
    handlers = []
    i = 0
    while i < len(lines):
        l = lines[i]
        end = skip_heredoc(lines, i)
        if end != i:
            out.extend(lines[i:end + 1])
            i = end + 1
            continue
        m = EXIT_TRAP_RE.match(l)
        if m and not l.startswith((" ", "\t")):
            cmd = [c.strip() for c in (m.group(2) or m.group(3) or m.group(4)).split(";") if c.strip()]
            previous = [h for h in handlers if h not in cmd]
            if previous:
                out.append("# 🔗 pipeline: the EXIT traps set before are kept, %s runs first" % " ".join(cmd))
                l = "trap '%s' EXIT" % "; ".join(cmd + previous)
            handlers = cmd + previous
        out.append(l)
        i += 1
    return out


def ksqldb_format(converter, data_format):
    if data_format:
        return {"AVRO": "AVRO", "PROTOBUF": "PROTOBUF", "JSON_SR": "JSON_SR"}.get(data_format.upper())
    if "avro" in converter.lower():
        return "AVRO"
    if "protobuf" in converter.lower():
        return "PROTOBUF"
    if "jsonschema" in converter.lower():
        return "JSON_SR"
    return None


def build(model_path, base_path, sink_paths, topic=None, step=None, root=None, validate_only=False):
    root = root or os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    base = catalog.describe(base_path, root)
    sinks = [catalog.describe(s, root) for s in sink_paths]

    if base["kind"] not in ("source", "sink"):
        fail("%s is neither a source nor a sink connector example" % base["path"])
    for s in sinks:
        if s["kind"] != "sink":
            fail("%s is not a sink connector example: --pipeline only takes sinks" % s["path"])
        if s["managed"] != base["managed"]:
            fail("%s and %s: a pipeline is all self-managed (connect/) or all fully managed (ccloud/fm-*)" % (base["path"], s["path"]))
        if not s["connector"]:
            fail("could not find the 'playground connector create-or-update' heredoc of %s" % s["path"])
    if not base["connector"]:
        fail("could not find the 'playground connector create-or-update' heredoc of %s" % base["path"])
    if step and base["managed"]:
        fail("--pipeline-step %s is only supported with self-managed (connect/) examples" % step)
    if step and base["kind"] != "source":
        fail("--pipeline-step %s needs a source example as base" % step)
    if step == "ksqldb" and not ksqldb_format(base["value_converter_effective"], base["data_format"]):
        fail("--pipeline-step ksqldb needs values with a schema (Avro, Protobuf or JSON Schema) to declare the stream "
             "without columns, and %s writes %s" % (base["path"], base["value_converter_effective"] or "?"))
    if step == "flink" and "avro" not in base["value_converter_effective"].lower():
        fail("--pipeline-step flink needs Avro values (open source Flink reads Schema Registry with avro-confluent only, "
             "the columns come from the Avro schema), and %s writes %s" % (base["path"], base["value_converter_effective"] or "?"))

    # the topic the sinks read
    if not topic:
        candidates = base["topics_out"] if base["kind"] == "source" else base["topics_in"]
        if not candidates:
            hints = ", ".join("%s=%s" % (h["key"], h["value"]) for h in base["topic_hints"])
            fail("could not find the topic written by %s%s: pass it with --pipeline-topic <topic>"
                 % (base["path"], " (config: " + hints + ")" if hints else ""))
        topic = candidates[0]
        if len(candidates) > 1:
            warn("%s uses several topics (%s): the sinks read %s, use --pipeline-topic to pick another one"
                 % (base["path"], ", ".join(candidates), topic))
    if validate_only:
        for m in messages:
            print(m)
        return

    info("🔗 the sinks read topic %s" % topic)

    findings = catalog.check(base, sinks)
    if base["kind"] == "sink":
        # fan-out: the base is a consumer like the others, the rules about the source do not apply
        findings = [f for f in findings if f["rule"].startswith("compose-")]

    with open(model_path, encoding="utf-8") as f:
        model = f.read().split("\n")

    anchor_re = FM_ANCHOR_RE if base["managed"] else SM_ANCHOR_RE
    model = comment_guards(model, base["path"])
    # several databases: 'playground db' needs to be told which one
    all_dbs = []
    for ex in [base] + sinks:
        all_dbs += [d for d in ex.get("databases", []) if d not in all_dbs]
    several_dbs = len(all_dbs) > 1
    if several_dbs:
        info("🗄️ several databases (%s): --container is added to the 'playground db' calls" % ", ".join(all_dbs))
        if len(base.get("databases", [])) == 1:
            model = pin_database(model, base["databases"][0])
    model, teardown = split_teardown(model)
    while model and not model[-1].strip():
        model.pop()

    # the base connector: its converters are the ones every sink uses
    b_start, b_end = heredoc_span(model, find(model, anchor_re) + 1)
    base_converter_lines = raw_converter_lines(model, b_start, b_end) if b_start >= 0 else []
    used_names = connector_names(model)
    defined_functions = set(functions(model))

    sink_topic = topic
    if step == "ksqldb":
        value_format = ksqldb_format(base["value_converter_effective"], base["data_format"])
        key_format = ksqldb_format(base["key_converter_effective"], "") or "KAFKA"
        sink_topic = topic + "_ksqldb"
        env_line = find(model, PG_ENV_RE)
        if env_line < 0:
            env_line = find(model, anchor_re)
        model[env_line:env_line] = ["# 🔗 pipeline: ksqlDB step between the source and the sinks", "export ENABLE_KSQLDB=true", ""]
        model += [
            "",
            "#################################################################################################",
            "# 🔗 pipeline: ksqlDB step, from topic %s to topic %s" % (topic, sink_topic),
            "#################################################################################################",
            'log "🔗 pipeline: ksqlDB step, from topic %s to topic %s"' % (topic, sink_topic),
            "playground ksqldb sql << EOF",
            "SET 'auto.offset.reset' = 'earliest';",
            "CREATE STREAM PIPELINE_SOURCE WITH (KAFKA_TOPIC='%s', KEY_FORMAT='%s', VALUE_FORMAT='%s');" % (topic, key_format, value_format),
            "CREATE STREAM PIPELINE_STEP WITH (KAFKA_TOPIC='%s', KEY_FORMAT='%s', VALUE_FORMAT='%s') AS" % (sink_topic, key_format, value_format),
            "  SELECT * FROM PIPELINE_SOURCE EMIT CHANGES;",
            "EOF",
            "",
            "playground topic consume --topic %s --min-expected-messages 1 --timeout 120" % sink_topic,
        ]
        info("🧪 ksqlDB step: %s -> PIPELINE_STEP -> %s (KEY_FORMAT %s, VALUE_FORMAT %s)" % (topic, sink_topic, key_format, value_format))
        if base["envelope"] == "debezium":
            warn("the ksqlDB step keeps the Debezium envelope, the sinks unwrap it: to flatten it in ksqlDB instead, use SELECT AFTER->* and remove ExtractNewRecordState from the sinks")

    if step == "flink":
        sink_topic = topic + "_flink"
        debezium = base["envelope"] == "debezium"
        env_line = find(model, PG_ENV_RE)
        if env_line < 0:
            env_line = find(model, anchor_re)
        model[env_line:env_line] = [
            "# 🔗 pipeline: Flink step between the source and the sinks (same versions as flink/flink-sql-kafka)",
            'if [ "${PLAYGROUND_ENVIRONMENT:-plaintext}" != "plaintext" ]',
            "then",
            '    logwarn "the Flink step of the pipeline is only available in the plaintext environment"',
            "    exit 111",
            "fi",
            "export ENABLE_FLINK=true",
            'if [ "$FLINK_TAG" == "latest" ]',
            "then",
            '    export FLINK_TAG="%s"' % FLINK_TAG,
            "fi",
            "# the kafka sql connector and the avro-confluent format, in /opt/flink/lib of the flink containers",
            'export FLINK_URL="%s %s"' % (FLINK_KAFKA_JAR, FLINK_AVRO_CONFLUENT_JAR),
            "",
        ]
        model += [
            "",
            "#################################################################################################",
            "# 🔗 pipeline: Flink step, from topic %s to topic %s" % (topic, sink_topic),
            "#################################################################################################",
            'log "🔗 pipeline: Flink step, from topic %s to topic %s"' % (topic, sink_topic),
            "# the columns of the tables come from the Avro value schema of %s (playground flink table-ddl)" % topic,
            "source_table=$(playground flink table-ddl --topic %s --table pipeline_source)" % topic,
        ] + ([
            "# the Debezium envelope is flattened by the job: the columns of 'after', the deletes (no 'after') are left out",
            "step_table=$(playground flink table-ddl --topic %s --schema-topic %s --field after --table pipeline_step --sink)" % (sink_topic, topic),
            "step_select=$(playground flink table-ddl --topic %s --field after --select-from pipeline_source)" % topic,
        ] if debezium else [
            "step_table=$(playground flink table-ddl --topic %s --schema-topic %s --table pipeline_step --sink)" % (sink_topic, topic),
            'step_select="SELECT * FROM pipeline_source"',
        ]) + [
            "playground flink sql << EOF",
            "$source_table",
            "",
            "$step_table",
            "",
            "INSERT INTO pipeline_step $step_select;",
            "EOF",
            "",
            "playground topic consume --topic %s --min-expected-messages 1 --timeout 120" % sink_topic,
        ]
        info("🐿️ Flink step: %s -> INSERT INTO pipeline_step -> %s (columns from the Avro schema, value only: the records of %s have no key)"
             % (topic, sink_topic, sink_topic))
        if debezium:
            info("🧩 the Flink job flattens the Debezium envelope (the columns of after, deletes left out): no ExtractNewRecordState in the sinks")
            findings = catalog.check(dict(base, envelope=None), sinks)

    for n, sink in enumerate(sinks, start=1):
        with open(os.path.join(root, sink["path"]), encoding="utf-8") as f:
            sl = f.read().split("\n")
        info("➕ sink %d: %s (connector %s)" % (n, sink["path"], sink["connector"]["name"] or "?"))
        # functions the model already defines (cleanup_cloud_resources...): renamed in the whole sink script
        for fname in sorted(set(functions(sl)) & defined_functions):
            new_name = "%s_%d" % (fname, n)
            sl = [re.sub(r"\b%s\b" % re.escape(fname), new_name, l) for l in sl]
            info("   🔤 function %s renamed %s (the model defines it too)" % (fname, new_name))
        defined_functions |= set(functions(sl))
        u = find(sl, UTILS_RE)
        a = find(sl, FM_ANCHOR_RE if sink["managed"] else SM_ANCHOR_RE)
        if u < 0 or a < 0:
            fail("could not find the start of the environment in %s" % sink["path"])

        # 1. what the sink needs before the environment starts
        pre = [l for l in sl[u + 1:a] if not PG_ENV_RE.search(l)]
        pre = comment_guards(pre, sink["path"])
        existing = set(l.strip() for l in model if l.strip())
        pre = [l for l in pre if not (l.strip() and re.match(r"^\s*handle_\w+_credentials\s*$", l) and l.strip() in existing)]
        while pre and not pre[-1].strip():
            pre.pop()
        while pre and not pre[0].strip():
            pre.pop(0)
        insert_at = find(model, PG_ENV_RE) if not base["managed"] else -1
        if insert_at < 0:
            insert_at = find(model, anchor_re)
        if pre:
            model[insert_at:insert_at] = ["# 🔗 pipeline: from %s" % sink["path"]] + pre + [""]

        # fully managed: one cluster, the most specific cloud/region wins
        if sink["managed"] and sink["cloud"] and sink["cloud"]["args"]:
            ai = find(model, FM_ANCHOR_RE)
            base_args = (base["cloud"] or {}).get("args", "")
            if not base_args:
                model[ai] = re.sub(r"bootstrap_ccloud_environment.*", "bootstrap_ccloud_environment " + sink["cloud"]["args"], model[ai])
                base["cloud"] = sink["cloud"]
                info("☁️ cluster: bootstrap_ccloud_environment %s, as %s needs" % (sink["cloud"]["args"], sink["path"]))
            elif base_args != sink["cloud"]["args"]:
                warn("%s runs on bootstrap_ccloud_environment %s, the model uses %s: check the bucket / region settings of the sink"
                     % (sink["path"], sink["cloud"]["args"], base_args))

        # 2. the rest of the sink example
        post = sl[a + 1:]
        post, sink_teardown = split_teardown(post)
        post = comment_guards(post, sink["path"])
        post, removed = remove_producers(post)
        if several_dbs and len(sink.get("databases", [])) == 1:
            post = pin_database(post, sink["databases"][0])
        if removed:
            info("   🗑️ %d producer(s) of the sink example removed" % removed)
        else:
            warn("   no producer found in %s, kept as is" % sink["path"])

        old_topics = list(sink["topics_in"])
        # its topic(s): never delete or re-create them, they hold the records of the base
        for t in old_topics:
            post = [": # 🔗 pipeline: topic %s of the sink example not deleted / created, the sink reads %s" % (t, sink_topic)
                    if re.search(r"playground\s+topic\s+(delete|create)\b.*(--topic|-t)[\s=]+['\"]?" + re.escape(t) + r"['\"]?(\s|$)", l)
                    else l for l in post]

        s_start, s_end = heredoc_span(post)
        if s_start < 0:
            fail("could not find the connector heredoc of %s" % sink["path"])

        # topics
        values = {"topics": sink_topic}
        post = set_keys(post, s_start, s_end, values, remove_regex=r"^topics(\.regex)?$")
        s_start, s_end = heredoc_span(post)

        # formats
        if sink["managed"]:
            fmt = {}
            if base["kind"] == "source":
                if base["config"].get("output.data.format"):
                    fmt["input.data.format"] = base["config"]["output.data.format"]
                if base["config"].get("output.key.format"):
                    fmt["input.key.format"] = base["config"]["output.key.format"]
            else:
                for k in ("input.data.format", "input.key.format"):
                    if base["config"].get(k):
                        fmt[k] = base["config"][k]
            if fmt:
                post = set_keys(post, s_start, s_end, fmt)
                s_start, s_end = heredoc_span(post)
                info("   💱 %s" % ", ".join("%s=%s" % kv for kv in fmt.items()))
        else:
            post = set_keys(post, s_start, s_end, {}, remove_regex=r"^(key|value)\.converter", raw=base_converter_lines)
            s_start, s_end = heredoc_span(post)
            if base_converter_lines:
                info("   💱 converters of the base: " + ", ".join(KV_LINE_RE.match(l).group(2) + "=" + KV_LINE_RE.match(l).group(3).split(".")[-1]
                                                             for l in base_converter_lines if not KV_LINE_RE.match(l).group(2).count(".") > 2))
            else:
                info("   💱 converters of the worker (the base sets none): key StringConverter, value AvroConverter")

        # rules that fix the config
        for f in findings:
            if f["sink"] == sink["path"] and f["severity"] == "fix" and f["add_to_sink"]:
                post = set_keys(post, s_start, s_end, f["add_to_sink"])
                s_start, s_end = heredoc_span(post)
                info("   🩹 %s" % f["message"])

        # connector names
        name = sink["connector"]["name"]
        if sink["managed"]:
            var = "connector_name_%d" % n
            post = [re.sub(r"\bconnector_name\b", var, l) for l in post]
            sink_teardown = [re.sub(r"\bconnector_name\b", var, l) for l in sink_teardown]
            name_ref = "$" + var
        else:
            name_ref = name
            if name and name in used_names:
                new = "%s-%d" % (name, n)
                post = [re.sub(r"((?:--connector|-c)[\s=]+\"?)" + re.escape(name) + r"\b", lambda m: m.group(1) + new, l) for l in post]
                info("   🏷️ connector %s renamed %s (the name is already used in the model)" % (name, new))
                name_ref = new
            used_names.add(name_ref)

        # the old topic name in the rest of the sink section: object paths, tables, indexes
        if old_topics:
            head = post[:s_start]
            tail = post[s_start:]
            for t in old_topics:
                if t != sink_topic:
                    tail = [replace_topic_token(l, t, sink_topic) for l in tail]
            post = head + tail
            s_start, s_end = heredoc_span(post)

        # wait for the sink, then its checks under set +e
        after = s_end + 1
        while after < len(post) and re.match(r"^\s*wait_for_ccloud_connector_up\b", post[after]):
            after += 1
        checks = post[after:]
        checks = ["set +e # 🔗 pipeline: was set -e" if re.match(r"^\s*set -e\s*$", l) else l for l in checks]
        while checks and not checks[-1].strip():
            checks.pop()
        if STORAGE_SINK_RE.search(sink["connector"]["class"]):
            # offsets are committed when a file is written (flush.size, rotate.interval.ms): the lag says nothing before
            wait = [
                "",
                "# 🔗 pipeline: %s commits its offsets when it writes a file (flush.size, rotate.interval.ms), so the" % name_ref,
                "#    consumer lag only drops then: check that it runs, the files are checked below",
                "sleep 30",
                "playground connector status --connector %s --fail-on-error" % name_ref,
            ]
        else:
            wait = [
                "",
                'log "🔗 pipeline: waiting until %s has consumed every record of %s"' % (name_ref, sink_topic),
                "playground connector show-lag --connector %s --max-wait 300 --fail-on-timeout" % name_ref,
            ]
        if any(l.strip() and not l.strip().startswith("#") for l in checks):
            wait += [
                "",
                "# 🔗 pipeline: the checks below come from %s, written for the records its producer sent:" % sink["path"],
                "#    adapt them to the records of the base example. set +e: they do not stop the model",
                "set +e",
            ] + checks + ["set -e"]
        section = [
            "",
            "#################################################################################################",
            "# 🔗 pipeline: sink %d, from %s" % (n, sink["path"]),
            "#################################################################################################",
        ] + post[:after] + wait
        model += section
        teardown += sink_teardown

    # one question for every fully managed connector to delete
    if teardown:
        deletes = [l for l in teardown if l.strip() and not TEARDOWN_RE.search(l) and not re.match(r"^\s*check_if_continue\b", l)]
        model += ["", 'log "Do you want to delete the fully managed connectors of the pipeline ?"', "check_if_continue"] + deletes

    model = chain_exit_traps(model)

    # header
    chain = base["path"] + (" -> " + step if step else "") + " -> " + ", ".join(s["path"] for s in sinks)
    header = ["# 🔗 pipeline: %s (topic %s)" % (chain, topic)]
    for f in findings:
        level = {"fix": "🩹", "warn": "⚠️", "info": "ℹ️"}[f["severity"]]
        header.append("# 🔗 pipeline note: %s %s%s" % (level, (os.path.basename(os.path.dirname(f["sink"])) + ": ") if f["sink"] else "", f["message"]))
        if f["severity"] != "fix":
            (warn if f["severity"] == "warn" else info)("%s %s%s" % (level, (f["sink"] + ": ") if f["sink"] else "", f["message"]))
    c = find(model, re.compile(r"^# 💬 comments:"))
    if c < 0:
        c = 1
    model[c:c] = header

    with open(model_path, "w", encoding="utf-8") as f:
        f.write("\n".join(model).rstrip("\n") + "\n")
    for m in messages:
        print(m)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--model")
    p.add_argument("--validate", action="store_true", help="only check the examples and find the topic, write nothing")
    p.add_argument("--base", required=True)
    p.add_argument("--sink", action="append", required=True)
    p.add_argument("--topic")
    p.add_argument("--step", choices=["ksqldb", "flink"])
    p.add_argument("--root")
    a = p.parse_args()
    if not a.model and not a.validate:
        p.error("--model is required")
    build(a.model, a.base, a.sink, a.topic, a.step, os.path.abspath(a.root) if a.root else None, a.validate)


if __name__ == "__main__":
    main()
