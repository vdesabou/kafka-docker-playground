#!/usr/bin/env python3
"""Tests of the pipeline builder (repro bootstrap --pipeline, repro pipeline-builder, connector flow):
python3 -I tools/pipeline-builder/test_pipeline.py"""

import io
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

import catalog  # noqa: E402
import flink_ddl  # noqa: E402
import flow  # noqa: E402
import pipeline  # noqa: E402

HEAD = '''#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
'''

SM_ENV = '''
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"
'''

GUARD = '''
if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.9.99"
then
     logwarn "minimal supported connector version is 3.0.0 for CP 8.0"
     exit 111
fi
'''

DBZ_SOURCE = HEAD + GUARD + SM_ENV + '''
playground db sql --database mydb << EOF
INSERT INTO CUSTOMERS VALUES (1);
EOF

playground connector create-or-update --connector dbz-source << EOF
{
  "connector.class": "io.debezium.connector.mysql.MySqlConnector",
  "tasks.max": "1",
  "topic.prefix": "server1",
  "_transforms": "unwrap"
}
EOF

log "Verifying topic server1.mydb.CUSTOMERS"
playground topic consume --topic server1.mydb.CUSTOMERS --min-expected-messages 1 --timeout 60
'''

JSON_SOURCE = HEAD + SM_ENV + '''
playground connector create-or-update --connector file-source << EOF
{
  "connector.class": "FileStreamSource",
  "topic": "file-topic",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false"
}
EOF
'''

DATAGEN_SOURCE = HEAD + SM_ENV + '''
playground connector create-or-update --connector datagen-source << EOF
{
  "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
  "kafka.topic": "pageviews",
  "quickstart": "pageviews"
}
EOF
'''

JDBC_SINK = HEAD + GUARD + '''
handle_aws_credentials
''' + SM_ENV + '''
playground connector create-or-update --connector pg-sink << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "connection.url": "jdbc:postgresql://postgres/postgres",
  "topics": "orders",
  "value.converter": "io.confluent.connect.protobuf.ProtobufConverter",
  "auto.create": "true"
}
EOF

log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 1 << 'EOF'
{"type": "record", "name": "r", "fields": [{"name": "id", "type": "int"}]}
EOF

for i in 1 2
do
  playground topic produce -t orders --nb-messages 1 --forced-value '{"id":2}' << 'EOF'
{"type": "record", "name": "r", "fields": [{"name": "id", "type": "int"}]}
EOF
done

set +e
cleanup
set -e

playground db wait-for-rows --table ORDERS --min-expected-rows 2
playground db sql > /tmp/result.log 2>&1 << 'EOF'
SELECT * FROM ORDERS;
SELECT * FROM "orders";
EOF
grep "orders-backup" /tmp/x
'''

REGEX_SINK = HEAD + SM_ENV + '''
playground connector create-or-update --connector pg-sink << EOF
{
  "connector.class": "io.confluent.connect.s3.S3SinkConnector",
  "topics.regex": "s3-.*"
}
EOF
seq 10 | docker exec -i broker kafka-console-producer --bootstrap-server broker:9092 --topic s3-topic
'''

FM_SOURCE = HEAD + '''
bootstrap_ccloud_environment

connector_name="DatagenSource_$USER"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "DatagenSource",
     "kafka.topic" : "datagen_pageviews",
     "output.data.format" : "AVRO"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

playground topic consume --topic datagen_pageviews --min-expected-messages 5 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
'''

FM_SINK = HEAD + '''
handle_aws_credentials

bootstrap_ccloud_environment "aws" "$AWS_REGION"

set +e
playground topic delete --topic s3-topic
sleep 3
playground topic create --topic s3-topic --nb-partitions 1
set -e

playground topic produce -t s3-topic --nb-messages 1000 --forced-value '{"f1":"value%g"}' << 'EOF'
{"type": "record", "name": "myrecord", "fields": [{"name": "f1", "type": "string"}]}
EOF

connector_name="S3_SINK_$USER"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "S3_SINK",
    "name": "$connector_name",
    "topics": "s3-topic",
    "input.data.format": "JSON",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

aws s3 cp --recursive s3://bucket/$TAG/s3-topic /tmp/s3-topic

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
'''

FM_TRAP_SOURCE = HEAD + '''
bootstrap_ccloud_environment

TOPIC="logs.stream"
connector_name="CloudWatchLogsSource_$USER"

function cleanup_cloud_resources {
    set +e
    log "Do you want to delete the log group (connector will be deleted first)?"
    check_if_continue
    playground connector delete --connector $connector_name
}
trap cleanup_cloud_resources EXIT

playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "CloudWatchLogsSource",
    "output.data.format": "AVRO"
}
EOF

playground topic consume --topic $TOPIC --min-expected-messages 10 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
'''

FM_TRAP_SINK = HEAD + '''
bootstrap_ccloud_environment "aws" "$AWS_REGION"

CLUSTER_NAME=pgredshift

function cleanup_cloud_resources {
  set +e
  log "Delete AWS Redshift cluster $CLUSTER_NAME"
  check_if_continue
  aws redshift delete-cluster --cluster-identifier $CLUSTER_NAME
}
trap cleanup_cloud_resources EXIT

playground topic produce -t redshiftorders --nb-messages 3 << 'EOF'
{"type": "record", "name": "r", "fields": [{"name": "id", "type": "int"}]}
EOF

connector_name="RedshiftSink_$USER"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "RedshiftSink",
  "topics": "redshiftorders"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
'''

COMPOSE_MYSQL = '''---
services:
  mysql:
    image: mysql:8.1
    container_name: mysql
    ports:
      - "3306:3306"

  connect:
    volumes:
      - ../../a:/a
    environment:
      CONNECT_PLUGIN_PATH: /usr/share/confluent-hub-components/debezium-debezium-connector-mysql
'''

COMPOSE_POSTGRES = '''---
services:
  postgres:
    image: postgres:15
    container_name: postgres
    ports:
      - "3306:5432"

  connect:
    environment:
      CONNECT_PLUGIN_PATH: /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc
'''


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class Repo:
    """a tiny kafka-docker-playground tree in a temporary folder."""

    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="pipeline-test-")
        self.add("connect/connect-debezium-mysql-source/dbz.sh", DBZ_SOURCE, COMPOSE_MYSQL)
        self.add("connect/connect-datagen-source/datagen.sh", DATAGEN_SOURCE, "---\nservices:\n  connect:\n    environment:\n      CONNECT_PLUGIN_PATH: /z\n")
        self.add("connect/connect-filestream-source/file.sh", JSON_SOURCE, "---\nservices:\n  connect:\n    environment:\n      CONNECT_PLUGIN_PATH: /x\n")
        self.add("connect/connect-jdbc-postgresql-sink/pg.sh", JDBC_SINK, COMPOSE_POSTGRES)
        self.add("connect/connect-aws-s3-sink/s3.sh", REGEX_SINK, "---\nservices:\n  connect:\n    environment:\n      CONNECT_PLUGIN_PATH: /y\n")
        self.add("ccloud/fm-datagen-source/fm.sh", FM_SOURCE)
        self.add("ccloud/fm-aws-s3-sink/fm.sh", FM_SINK)
        self.add("ccloud/fm-aws-cloudwatch-logs-source/fm.sh", FM_TRAP_SOURCE)
        self.add("ccloud/fm-aws-redshift-sink/fm.sh", FM_TRAP_SINK)

    def add(self, rel, text, compose=None):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)
        if compose:
            with open(os.path.join(os.path.dirname(path), "docker-compose.plaintext.yml"), "w") as f:
                f.write(compose)

    def path(self, rel):
        return os.path.join(self.root, rel)

    def model(self, base_rel):
        """the base example with the header bootstrap writes."""
        text = read(self.path(base_rel)).split("\n")
        path = os.path.join(self.root, "model.sh")
        with open(path, "w") as f:
            f.write("\n".join([text[0], "###", "# 💬 comments:", "# 🩹 status: open", "###"] + text[1:]))
        return path

    def build(self, base, sinks, **kw):
        model = self.model(base)
        out = io.StringIO()
        pipeline.messages.clear()
        with redirect_stdout(out):
            pipeline.build(model, self.path(base), [self.path(s) for s in sinks], root=self.root, **kw)
        return read(model), out.getvalue()

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)


def heredoc_json(text, connector_line_re):
    """the JSON of the connector heredoc after the line matching connector_line_re, with the bash variables replaced."""
    lines = text.split("\n")
    i = next(n for n, l in enumerate(lines) if re.search(connector_line_re, l))
    j = next(n for n in range(i + 1, len(lines)) if lines[n].strip() == "EOF")
    return json.loads(re.sub(r"\$\{?\w+\}?", "X", "\n".join(lines[i + 1:j])))


def bash_ok(text):
    r = subprocess.run(["bash", "-n"], input=text, capture_output=True, text=True)
    return r.returncode == 0, r.stderr


class DescribeTest(unittest.TestCase):
    def setUp(self):
        self.repo = Repo()

    def tearDown(self):
        self.repo.close()

    def test_source_topic_converter_envelope(self):
        f = catalog.describe(self.repo.path("connect/connect-debezium-mysql-source/dbz.sh"), self.repo.root)
        self.assertEqual(f["kind"], "source")
        self.assertEqual(f["topics_out"], ["server1.mydb.CUSTOMERS"])
        self.assertEqual(f["envelope"], "debezium")
        self.assertEqual(f["value_converter_effective"], catalog.DEFAULT_VALUE_CONVERTER)
        self.assertEqual(f["databases"], ["mysql"])
        self.assertEqual(f["cp8_connector_tag_above"], "2.9.99")
        self.assertNotIn("_transforms", f["config"])

    def test_sink_topics_producer_fm_name(self):
        f = catalog.describe(self.repo.path("connect/connect-jdbc-postgresql-sink/pg.sh"), self.repo.root)
        self.assertEqual((f["kind"], f["topics_in"], f["producer"], f["credentials"]), ("sink", ["orders"], True, ["aws"]))
        fm = catalog.describe(self.repo.path("ccloud/fm-aws-s3-sink/fm.sh"), self.repo.root)
        self.assertTrue(fm["managed"])
        self.assertEqual(fm["connector"]["name"], "S3_SINK_$USER")
        self.assertEqual(fm["cloud"]["cloud"], "aws")
        self.assertEqual(fm["data_format"], "JSON")

    def test_rules(self):
        dbz = catalog.describe(self.repo.path("connect/connect-debezium-mysql-source/dbz.sh"), self.repo.root)
        js = catalog.describe(self.repo.path("connect/connect-filestream-source/file.sh"), self.repo.root)
        pg = catalog.describe(self.repo.path("connect/connect-jdbc-postgresql-sink/pg.sh"), self.repo.root)
        rules = [f["rule"] for f in catalog.check(dbz, [pg])]
        self.assertIn("debezium-envelope-into-flat-sink", rules)
        self.assertIn("compose-port-conflict", rules)
        self.assertNotIn("schemaless-into-schema-sink", rules)
        self.assertIn("schemaless-into-schema-sink", [f["rule"] for f in catalog.check(js, [pg])])

    def test_mermaid_from_model(self):
        model, _ = self.repo.build("connect/connect-debezium-mysql-source/dbz.sh", ["connect/connect-jdbc-postgresql-sink/pg.sh"])
        path = self.repo.path("model.sh")
        src, sinks, topic, step = catalog.from_model(path, self.repo.root)
        self.assertEqual((src["path"], [s["path"] for s in sinks], topic, step),
                         ("connect/connect-debezium-mysql-source/dbz.sh", ["connect/connect-jdbc-postgresql-sink/pg.sh"], "server1.mydb.CUSTOMERS", None))
        self.assertIn('topic[("server1.mydb.CUSTOMERS")]', catalog.mermaid(src, sinks, topic))


class BuildTest(unittest.TestCase):
    def setUp(self):
        self.repo = Repo()

    def tearDown(self):
        self.repo.close()

    def test_self_managed_pipeline(self):
        model, out = self.repo.build("connect/connect-debezium-mysql-source/dbz.sh", ["connect/connect-jdbc-postgresql-sink/pg.sh"])
        ok, err = bash_ok(model)
        self.assertTrue(ok, err)
        self.assertIn("# 🔗 pipeline: connect/connect-debezium-mysql-source/dbz.sh -> connect/connect-jdbc-postgresql-sink/pg.sh (topic server1.mydb.CUSTOMERS)", model)
        self.assertLess(model.index("# 🔗 pipeline:"), model.index("# 💬 comments:"))
        # every producer replaced, the bash still valid (the one in the for loop too)
        self.assertNotIn("playground topic produce", model)
        self.assertEqual(model.count(": # 🔗 pipeline: producer of the sink example removed"), 2)
        self.assertNotIn("Sending messages", model)
        # the sink config: topic, converter of the source (none: the worker one), unwrap
        cfg = heredoc_json(model, r"--connector pg-sink")
        self.assertEqual(cfg["topics"], "server1.mydb.CUSTOMERS")
        self.assertNotIn("value.converter", cfg)
        self.assertEqual(cfg["transforms.unwrap.type"], "io.debezium.transforms.ExtractNewRecordState")
        # the old topic in the checks, as a whole token only, any case
        self.assertIn("--table server1.mydb.CUSTOMERS", model)
        # in the SQL of 'playground db sql', quoted: PostgreSQL would fold the name to lower case
        self.assertIn('SELECT * FROM "server1.mydb.CUSTOMERS";', model)
        self.assertNotIn('""', model[model.index("SELECT * FROM"):model.index("SELECT * FROM") + 200])
        self.assertIn('grep "orders-backup"', model)
        # guards commented out, credentials of the sink before the start, one show-lag, checks under set +e
        self.assertNotRegex(model, r"(?m)^if connect_cp_version_greater_than_8")
        self.assertLess(model.index("handle_aws_credentials"), model.index("playground start-environment"))
        self.assertIn("playground connector show-lag --connector pg-sink --max-wait 300 --fail-on-timeout", model)
        checks = model[model.index("# 🔗 pipeline: the checks below"):]
        self.assertIn("set +e # 🔗 pipeline: was set -e", checks)
        self.assertTrue(checks.rstrip().endswith("set -e"))
        # two databases: --container on each 'playground db'
        self.assertIn("playground db sql --container mysql --database mydb", model)
        self.assertIn("playground db wait-for-rows --container postgres --table", model)
        self.assertIn("I 🗄️ several databases", out)

    def test_converters_and_regex_and_storage_sink(self):
        model, _ = self.repo.build("connect/connect-filestream-source/file.sh",
                                   ["connect/connect-jdbc-postgresql-sink/pg.sh", "connect/connect-aws-s3-sink/s3.sh"])
        self.assertTrue(bash_ok(model)[0])
        pg = heredoc_json(model, r"--connector pg-sink << EOF")
        self.assertEqual(pg["value.converter"], "org.apache.kafka.connect.json.JsonConverter")
        self.assertEqual(pg["value.converter.schemas.enable"], "false")
        # the source and both sinks
        self.assertEqual(model.count('"value.converter":'), 3)
        # same connector name twice: renamed; topics.regex replaced; storage sink: flush.size=1, then a lag wait that
        # fails when nothing is written (the base may send fewer records than the flush.size of the example)
        s3 = heredoc_json(model, r"--connector pg-sink-2 << EOF")
        self.assertEqual(s3, {"connector.class": "io.confluent.connect.s3.S3SinkConnector", "topics": "file-topic", "flush.size": "1",
                              "value.converter": "org.apache.kafka.connect.json.JsonConverter", "value.converter.schemas.enable": "false"})
        self.assertIn("playground connector show-lag --connector pg-sink-2 --max-wait 300 --fail-on-timeout", model)
        self.assertNotIn("playground connector status --connector pg-sink-2", model)
        self.assertIn("flush.size=1 is set", "\n".join(pipeline.messages))
        self.assertNotIn("kafka-console-producer", model)
        self.assertIn("the source writes values without a schema", "\n".join(pipeline.messages))

    def test_storage_sink_flush_size(self):
        # an example that already writes one file per record: no fix, and the same lag wait (the final flush.size decides)
        self.repo.add("connect/connect-gcp-gcs-sink/gcs.sh", REGEX_SINK.replace(
            "io.confluent.connect.s3.S3SinkConnector", "io.confluent.connect.gcs.GcsSinkConnector").replace(
            '"topics.regex": "s3-.*"', '"topics.regex": "s3-.*",\n  "flush.size": "1"'))
        model, _ = self.repo.build("connect/connect-filestream-source/file.sh", ["connect/connect-gcp-gcs-sink/gcs.sh"])
        self.assertTrue(bash_ok(model)[0])
        self.assertEqual(heredoc_json(model, r"--connector pg-sink << EOF")["flush.size"], "1")
        self.assertNotIn("flush.size=1 is set", "\n".join(pipeline.messages))
        self.assertIn("playground connector show-lag --connector pg-sink --max-wait 300 --fail-on-timeout", model)
        self.assertNotIn("playground connector status --connector pg-sink", model)
        # HDFS: flush.size=1, but its offsets live in the file names, so no lag wait
        self.repo.add("connect/connect-hdfs3-sink/hdfs3.sh", REGEX_SINK.replace(
            "io.confluent.connect.s3.S3SinkConnector", "io.confluent.connect.hdfs3.Hdfs3SinkConnector"))
        model, _ = self.repo.build("connect/connect-filestream-source/file.sh", ["connect/connect-hdfs3-sink/hdfs3.sh"])
        self.assertTrue(bash_ok(model)[0])
        self.assertEqual(heredoc_json(model, r"--connector pg-sink << EOF")["flush.size"], "1")
        self.assertIn("playground connector status --connector pg-sink --fail-on-error", model)
        self.assertNotIn("show-lag --connector pg-sink", model)

    def test_fan_out_and_ksqldb_step(self):
        model, _ = self.repo.build("connect/connect-jdbc-postgresql-sink/pg.sh", ["connect/connect-aws-s3-sink/s3.sh"])
        self.assertTrue(bash_ok(model)[0])
        self.assertIn("(topic orders)", model)
        # the base keeps its producers
        self.assertIn("playground topic produce -t orders", model)
        s3 = heredoc_json(model, r"--connector pg-sink-1 << EOF")
        self.assertEqual(s3["value.converter"], "io.confluent.connect.protobuf.ProtobufConverter")
        model, _ = self.repo.build("connect/connect-debezium-mysql-source/dbz.sh", ["connect/connect-aws-s3-sink/s3.sh"], step="ksqldb")
        self.assertTrue(bash_ok(model)[0])
        self.assertIn("export ENABLE_KSQLDB=true", model)
        self.assertLess(model.index("export ENABLE_KSQLDB=true"), model.index("playground start-environment"))
        self.assertIn("CREATE STREAM PIPELINE_SOURCE WITH (KAFKA_TOPIC='server1.mydb.CUSTOMERS', KEY_FORMAT='KAFKA', VALUE_FORMAT='AVRO');", model)
        self.assertEqual(heredoc_json(model, r"--connector pg-sink << EOF")["topics"], "server1.mydb.CUSTOMERS_ksqldb")

    def test_flink_step(self):
        model, out = self.repo.build("connect/connect-debezium-mysql-source/dbz.sh", ["connect/connect-aws-s3-sink/s3.sh"], step="flink")
        self.assertTrue(bash_ok(model)[0])
        self.assertIn("-> flink -> connect/connect-aws-s3-sink/s3.sh (topic server1.mydb.CUSTOMERS)", model)
        env = model.index("playground start-environment")
        for line in ("export ENABLE_FLINK=true", 'export FLINK_TAG="2.2"', "flink-sql-avro-confluent-registry-2.2.0.jar", "exit 111"):
            self.assertLess(model.index(line), env, line)
        self.assertIn("source_table=$(playground flink table-ddl --topic server1.mydb.CUSTOMERS --table pipeline_source)", model)
        # a Debezium source: the job flattens the envelope, the sinks get no ExtractNewRecordState
        self.assertIn("step_table=$(playground flink table-ddl --topic server1.mydb.CUSTOMERS_flink --schema-topic server1.mydb.CUSTOMERS --field after --table pipeline_step --sink)", model)
        self.assertIn("step_select=$(playground flink table-ddl --topic server1.mydb.CUSTOMERS --field after --select-from pipeline_source)", model)
        self.assertIn("INSERT INTO pipeline_step $step_select;", model)
        cfg = heredoc_json(model, r"--connector pg-sink << EOF")
        self.assertEqual(cfg["topics"], "server1.mydb.CUSTOMERS_flink")
        self.assertNotIn("transforms", cfg)
        self.assertIn("🐿️ Flink step", out)
        # any other Avro source: SELECT * of the whole value
        model, _ = self.repo.build("connect/connect-datagen-source/datagen.sh", ["connect/connect-aws-s3-sink/s3.sh"], step="flink")
        self.assertTrue(bash_ok(model)[0])
        self.assertIn('step_select="SELECT * FROM pipeline_source"', model)
        self.assertIn("--topic pageviews_flink --schema-topic pageviews --table pipeline_step --sink)", model)

        src, _, topic, step = catalog.from_model(self.repo.path("model.sh"), self.repo.root)
        self.assertEqual((topic, step), ("pageviews", "flink"))

    def test_fully_managed(self):
        model, out = self.repo.build("ccloud/fm-datagen-source/fm.sh", ["ccloud/fm-aws-s3-sink/fm.sh"])
        self.assertTrue(bash_ok(model)[0])
        self.assertIn('bootstrap_ccloud_environment "aws" "$AWS_REGION"', model)
        self.assertEqual(model.count("bootstrap_ccloud_environment"), 1)
        # its topic is neither deleted nor re-created, the producer is gone
        self.assertNotIn("playground topic delete --topic s3-topic", model)
        self.assertNotIn("--topic datagen_pageviews --nb-partitions", model)
        self.assertNotIn("playground topic produce", model)
        cfg = heredoc_json(model, r"--connector \$connector_name_1 << EOF")
        self.assertEqual((cfg["topics"], cfg["input.data.format"]), ("datagen_pageviews", "AVRO"))
        self.assertIn('connector_name_1="S3_SINK_$USER"', model)
        self.assertIn("s3://bucket/$TAG/datagen_pageviews", model)
        # one question at the end, both connectors deleted
        tail = model[model.index('log "Do you want to delete the fully managed connectors of the pipeline ?"'):]
        self.assertEqual(model.count("check_if_continue"), 1)
        self.assertIn("playground connector delete --connector $connector_name\n", tail)
        self.assertIn("playground connector delete --connector $connector_name_1", tail)
        self.assertIn("playground connector status --connector $connector_name_1 --fail-on-error", model)
        # fully managed storage sink: flush.size has a 1000 minimum, so a warning instead of a fix
        self.assertNotIn("flush.size", cfg)
        self.assertIn("1000 minimum", "\n".join(pipeline.messages))
        self.assertIn("1000 minimum", model)

    def test_cleanup_functions_and_exit_traps(self):
        model, out = self.repo.build("ccloud/fm-aws-cloudwatch-logs-source/fm.sh", ["ccloud/fm-aws-redshift-sink/fm.sh"])
        self.assertTrue(bash_ok(model)[0])
        # the question inside the cleanup function is not the end of the script: the source connector stays in place
        self.assertLess(model.index("--connector $connector_name << EOF"), model.index("# 🔗 pipeline: sink 1"))
        self.assertLess(model.index("trap cleanup_cloud_resources EXIT"), model.index("--connector $connector_name << EOF"))
        # the cleanup of the sink is renamed, and both run on exit
        self.assertIn("function cleanup_cloud_resources_1 {", model)
        self.assertEqual(model.count("function cleanup_cloud_resources {"), 1)
        self.assertIn("trap 'cleanup_cloud_resources_1; cleanup_cloud_resources' EXIT", model)
        self.assertIn("function cleanup_cloud_resources renamed cleanup_cloud_resources_1", out)
        # one question at the end (the ones in the cleanup functions stay), both connectors deleted
        tail = model[model.index('log "Do you want to delete the fully managed connectors of the pipeline ?"'):]
        self.assertIn("playground connector delete --connector $connector_name\n", tail)
        self.assertIn("playground connector delete --connector $connector_name_1", tail)
        self.assertEqual(model.count("check_if_continue"), 3)

    def test_errors(self):
        for base, sinks, kw, message in [
            ("connect/connect-debezium-mysql-source/dbz.sh", ["ccloud/fm-aws-s3-sink/fm.sh"], {}, "all self-managed"),
            ("connect/connect-debezium-mysql-source/dbz.sh", ["connect/connect-filestream-source/file.sh"], {}, "not a sink"),
            ("ccloud/fm-datagen-source/fm.sh", ["ccloud/fm-aws-s3-sink/fm.sh"], {"step": "ksqldb"}, "only supported with self-managed"),
            ("connect/connect-filestream-source/file.sh", ["connect/connect-aws-s3-sink/s3.sh"], {"step": "ksqldb"}, "needs values with a schema"),
            ("connect/connect-filestream-source/file.sh", ["connect/connect-aws-s3-sink/s3.sh"], {"step": "flink"}, "needs Avro values"),
            ("connect/connect-jdbc-postgresql-sink/pg.sh", ["connect/connect-aws-s3-sink/s3.sh"], {"step": "flink"}, "needs a source example"),
        ]:
            out = io.StringIO()
            pipeline.messages.clear()
            with redirect_stdout(out), self.assertRaises(SystemExit):
                pipeline.build(self.repo.model(base), self.repo.path(base), [self.repo.path(s) for s in sinks], root=self.repo.root, **kw)
            self.assertIn(message, out.getvalue())

    def test_topic_override(self):
        model, _ = self.repo.build("connect/connect-filestream-source/file.sh", ["connect/connect-aws-s3-sink/s3.sh"], topic="other")
        self.assertIn('"topics": "other"', model)


class FlinkDdlTest(unittest.TestCase):
    SCHEMA = {
        "type": "record", "name": "Envelope", "namespace": "server1.mydb.CUSTOMERS",
        "fields": [
            {"name": "before", "type": ["null", {"type": "record", "name": "Value", "fields": [
                {"name": "id", "type": "int"},
                {"name": "email", "type": ["null", "string"], "default": None},
                {"name": "update_ts", "type": {"type": "string", "connect.name": "io.debezium.time.ZonedTimestamp"}},
                {"name": "price", "type": {"type": "bytes", "logicalType": "decimal", "precision": 10, "scale": 2}},
                {"name": "day", "type": {"type": "int", "logicalType": "date"}},
                {"name": "ts", "type": {"type": "long", "logicalType": "timestamp-millis"}},
            ]}], "default": None},
            {"name": "after", "type": ["null", "Value"], "default": None},
            {"name": "op", "type": "string"},
            {"name": "tags", "type": {"type": "array", "items": "string"}},
            {"name": "attrs", "type": {"type": "map", "values": "long"}},
            {"name": "level", "type": {"type": "enum", "name": "Level", "symbols": ["A", "B"]}},
        ]}

    def test_columns_from_the_registry_answer(self):
        answer = json.dumps({"subject": "t-value", "version": 1, "id": 3, "schema": json.dumps(self.SCHEMA)})
        cols = dict(flink_ddl.columns(answer))
        row = "ROW<`id` INT, `email` STRING, `update_ts` STRING, `price` DECIMAL(10, 2), `day` DATE, `ts` TIMESTAMP(3)>"
        self.assertEqual(cols["before"], row)
        self.assertEqual(cols["after"], row, "a named type used again")
        self.assertEqual((cols["op"], cols["tags"], cols["attrs"], cols["level"]), ("STRING", "ARRAY<STRING>", "MAP<STRING, BIGINT>", "STRING"))

    def test_ddl_source_and_sink(self):
        cols = [("id", "INT"), ("my`col", "STRING")]
        src = flink_ddl.ddl("pipeline_source", "a'topic", cols)
        self.assertIn("`my``col` STRING", src)
        self.assertIn("'topic' = 'a''topic'", src)
        self.assertIn("'scan.startup.mode' = 'earliest-offset'", src)
        self.assertIn("'value.format' = 'avro-confluent'", src)
        sink = flink_ddl.ddl("pipeline_step", "t_flink", cols, sink=True)
        self.assertNotIn("scan.startup.mode", sink)
        self.assertNotIn("properties.group.id", sink)

    def test_debezium_after_columns_and_select(self):
        answer = json.dumps({"schema": json.dumps(self.SCHEMA)})
        cols = flink_ddl.columns(answer, "after")
        self.assertEqual([n for n, _ in cols], ["id", "email", "update_ts", "price", "day", "ts"])
        self.assertEqual(flink_ddl.select("after", cols[:2], "pipeline_source"),
                         "SELECT `after`.`id` AS `id`, `after`.`email` AS `email` FROM `pipeline_source` WHERE `after` IS NOT NULL")
        with self.assertRaises(flink_ddl.Unsupported):
            flink_ddl.columns(answer, "op")

    def test_unsupported(self):
        for schema in ({"schemaType": "PROTOBUF", "schema": "syntax = 'proto3';"},
                       {"type": "record", "name": "r", "fields": [{"name": "u", "type": ["int", "string"]}]},
                       {"type": "record", "name": "n", "fields": [{"name": "next", "type": ["null", "n"]}]}):
            with self.assertRaises(flink_ddl.Unsupported):
                flink_ddl.columns(json.dumps(schema))


class FlowTest(unittest.TestCase):
    def test_tree_lag_dlq_and_orphan_topic(self):
        data = {"connectors": [
            {"name": "src", "config": {"connector.class": "a.MySqlConnector"}, "status": {"state": "RUNNING", "tasks": [{"state": "RUNNING"}]},
             "active_topics": ["t1"]},
            {"name": "snk", "config": {"connector.class": "a.JdbcSinkConnector", "topics": "t1", "errors.deadletterqueue.topic.name": "dlq"},
             "status": {"state": "RUNNING", "tasks": [{"state": "FAILED"}]}, "lag": {"total_lag": 3}},
            {"name": "s3", "config": {"connector.class": "io.confluent.connect.s3.S3SinkConnector", "topics.regex": "t.*"},
             "status": {"state": "RUNNING", "tasks": [{"state": "RUNNING"}]}, "lag": {"total_lag": 0}},
            {"name": "http", "config": {"connector.class": "HttpSink", "topics": "orders"}, "status": {"state": "RUNNING", "tasks": []}, "lag": {}},
        ], "counts": {"t1": 5, "dlq": 1, "orders": 2}}
        out = io.StringIO()
        with redirect_stdout(out):
            rc = flow.render(data)
        text = out.getvalue()
        self.assertEqual(rc, 1)
        self.assertIn("└─▶ 🗳 t1 · 5 records", text)
        self.assertIn("🔌 snk · JdbcSinkConnector · 🛑 RUNNING 0/1 tasks · lag 3 ⏳ · ☠️ dlq dlq: 1", text)
        self.assertIn("🔌 s3 · S3SinkConnector · ✅ RUNNING 1/1 tasks · lag 0 ✔️", text)
        self.assertIn("🗳 orders · 2 records · no source connector", text)
        out = io.StringIO()
        with redirect_stdout(out):
            flow.topics(data)
        self.assertEqual(out.getvalue().split(), ["t1", "orders", "dlq"])


class RepoTest(unittest.TestCase):
    """the real examples of the repository: every one is read, and random pipelines give valid bash."""

    def test_catalog_and_random_pipelines(self):
        data = catalog.catalog(ROOT)
        ex = [e for e in data["examples"] if e["connector"]]
        self.assertGreater(len(ex), 300)
        self.assertGreater(len([e for e in ex if e["kind"] == "source" and e["topics_out"]]), 150)
        rng = random.Random(42)
        tmp = tempfile.mkdtemp(prefix="pipeline-repo-")
        try:
            built = 0
            for i in range(60):
                managed = i % 3 == 0
                base = rng.choice([e for e in ex if e["kind"] == "source" and e["managed"] == managed and e["topics_out"]])
                sinks = rng.sample([e for e in ex if e["kind"] == "sink" and e["managed"] == managed], 2)
                model = os.path.join(tmp, "m%d.sh" % i)
                shutil.copy(os.path.join(ROOT, base["path"]), model)
                pipeline.messages.clear()
                with redirect_stdout(io.StringIO()):
                    pipeline.build(model, os.path.join(ROOT, base["path"]), [os.path.join(ROOT, s["path"]) for s in sinks], root=ROOT)
                text = read(model)
                where = "%s -> %s" % (base["path"], ", ".join(s["path"] for s in sinks))
                ok, err = bash_ok(text)
                self.assertTrue(ok, "%s: %s" % (where, err))
                # valid bash is not enough: the base connector before the sinks, no sink inside a function (a cleanup
                # function of the base asks 'Do you want to delete'), no function defined twice
                lines = text.split("\n")
                first_sink = next(k for k, l in enumerate(lines) if l.startswith("# 🔗 pipeline: sink 1"))
                creates = [k for k, l in enumerate(lines) if catalog.CREATE_RE.search(l)]
                self.assertLess(creates[0], first_sink, where)
                for name, (a, b) in pipeline.functions(lines).items():
                    self.assertFalse(any("🔗 pipeline: sink" in l for l in lines[a:b + 1]), "%s: sink inside function %s" % (where, name))
                names = [m.group(1) or m.group(2) for m in (pipeline.FUNC_START_RE.match(l) for l in lines) if m]
                defined = [n for n in names if n in pipeline.functions(lines)]
                self.assertEqual(len(defined), len(set(defined)), "%s: function defined twice" % where)
                built += 1
            self.assertEqual(built, 60)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_page(self):
        tmp = tempfile.mkdtemp(prefix="pipeline-page-")
        try:
            out = os.path.join(tmp, "p.html")
            catalog.html(ROOT, out, site=True)
            page = read(out)
            self.assertNotIn("/*__PIPELINE_CATALOG__*/", page)
            self.assertIn('const ROOT = "";', page)
            # the script that holds the catalog (the theme script comes first, in the head)
            start = page.index("<script>", page.index("</style>"))
            script = page[start + 8:page.rindex("</script>")]
            self.assertIn("const CATALOG = {", script)
            self.assertNotIn("</script", script)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=1)
