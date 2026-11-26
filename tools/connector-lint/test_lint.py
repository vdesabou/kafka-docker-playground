#!/usr/bin/env python3
"""Tests of tools/connector-lint/lint.py: python3 -I tools/connector-lint/test_lint.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lint  # noqa: E402

SINK = {"connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector", "topics": "orders", "tasks.max": "1"}
SOURCE = {"connector.class": "io.debezium.connector.postgresql.PostgresConnector", "tasks.max": "1"}


def keys(result, severity=None):
    return [f["key"] for f in result["findings"] if severity is None or f["severity"] == severity]


class LintTest(unittest.TestCase):
    def test_clean_sink(self):
        r = lint.lint(dict(SINK), {})
        self.assertEqual(r["findings"], [])
        self.assertEqual(r["warning_count"], 0)

    def test_tolerance_all_without_dlq(self):
        r = lint.lint(dict(SINK, **{"errors.tolerance": "all"}), {})
        self.assertIn("errors.tolerance", keys(r, "MEDIUM"))
        self.assertIn("errors.log.enable", keys(r, "LOW"))

    def test_tolerance_all_with_dlq_and_log(self):
        r = lint.lint(dict(SINK, **{"errors.tolerance": "all", "errors.deadletterqueue.topic.name": "dlq",
                                    "errors.deadletterqueue.topic.replication.factor": "1"}), {"brokers": 1})
        self.assertEqual(keys(r, "MEDIUM"), [])
        self.assertEqual(keys(r, "HIGH"), [])
        self.assertIn("errors.deadletterqueue.topic.replication.factor", keys(r, "LOW"))

    def test_dlq_without_tolerance(self):
        r = lint.lint(dict(SINK, **{"errors.deadletterqueue.topic.name": "dlq"}), {})
        self.assertIn("errors.deadletterqueue.topic.name", keys(r, "MEDIUM"))

    def test_dlq_default_rf_above_brokers(self):
        r = lint.lint(dict(SINK, **{"errors.tolerance": "all", "errors.deadletterqueue.topic.name": "dlq"}), {"brokers": 1})
        self.assertIn("errors.deadletterqueue.topic.replication.factor", keys(r, "HIGH"))
        # offline: no broker count, no HIGH
        r = lint.lint(dict(SINK, **{"errors.tolerance": "all", "errors.deadletterqueue.topic.name": "dlq"}), {})
        self.assertEqual(keys(r, "HIGH"), [])

    def test_dlq_on_source(self):
        r = lint.lint(dict(SOURCE, **{"errors.deadletterqueue.topic.name": "dlq"}), {})
        self.assertIn("errors.deadletterqueue.topic.name", keys(r, "LOW"))

    def test_other_replication_factor(self):
        r = lint.lint(dict(SINK, **{"confluent.topic.replication.factor": "3"}), {"brokers": 1})
        self.assertIn("confluent.topic.replication.factor", keys(r, "HIGH"))

    def test_tasks_above_partitions(self):
        r = lint.lint(dict(SINK, **{"tasks.max": "4"}), {"partitions": {"orders": 1}})
        self.assertIn("tasks.max", keys(r, "LOW"))
        r = lint.lint(dict(SINK, **{"tasks.max": "4"}), {"partitions": {"orders": 0}})  # unknown topic
        self.assertNotIn("tasks.max", keys(r))

    def test_single_task_debezium(self):
        r = lint.lint(dict(SOURCE, **{"tasks.max": "3"}), {})
        self.assertIn("tasks.max", keys(r, "INFO"))
        self.assertEqual(r["warning_count"], 0)

    def test_overrides_policy(self):
        cfg = dict(SINK, **{"consumer.override.max.poll.records": "100"})
        self.assertIn("consumer.override.max.poll.records", keys(lint.lint(cfg, {"worker_override_policy": "None"}), "HIGH"))
        self.assertEqual(keys(lint.lint(cfg, {"worker_override_policy": "All"})), [])
        self.assertIn("consumer.override.max.poll.records", keys(lint.lint(cfg, {}), "INFO"))
        cfg = dict(SINK, **{"consumer.override.sasl.jaas.config": "${file:/a:b}"})
        self.assertEqual(keys(lint.lint(cfg, {"worker_override_policy": "Principal"}), "HIGH"), [])

    def test_consumer_override_on_source(self):
        r = lint.lint(dict(SOURCE, **{"consumer.override.fetch.min.bytes": "1"}), {"worker_override_policy": "All"})
        self.assertIn("consumer.override.fetch.min.bytes", keys(r, "LOW"))

    def test_poll_loop_and_offsets_and_acks(self):
        r = lint.lint(dict(SINK, **{"consumer.override.max.poll.records": "10000",
                                    "consumer.override.auto.offset.reset": "latest"}), {"worker_override_policy": "All"})
        self.assertIn("consumer.override.max.poll.records", keys(r, "MEDIUM"))
        self.assertIn("consumer.override.auto.offset.reset", keys(r, "LOW"))
        r = lint.lint(dict(SOURCE, **{"producer.override.acks": "1"}), {"worker_override_policy": "All"})
        self.assertIn("producer.override.acks", keys(r, "MEDIUM"))

    def test_converters(self):
        r = lint.lint(dict(SINK, **{"value.converter": "io.confluent.connect.avro.AvroConverter"}), {})
        self.assertIn("value.converter.schema.registry.url", keys(r, "MEDIUM"))
        r = lint.lint(dict(SINK, **{"value.converter": "io.confluent.connect.avro.AvroConverter",
                                    "value.converter.schema.registry.url": "http://schema-registry:8081"}), {})
        self.assertEqual(r["findings"], [])
        r = lint.lint(dict(SINK, **{"value.converter": "org.apache.kafka.connect.json.JsonConverter",
                                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                                    "value.converter.schemas.enable": "false"}), {})
        self.assertIn("value.converter", keys(r, "MEDIUM"))
        r = lint.lint(dict(SINK, **{"value.converter": "org.apache.kafka.connect.json.JsonConverter"}), {})
        self.assertIn("value.converter.schemas.enable", keys(r, "INFO"))
        r = lint.lint(dict(SINK, **{"value.converter": "org.apache.kafka.connect.json.JsonConverter",
                                    "value.converter.schemas.enable": "false"}), {})
        self.assertEqual(r["findings"], [])

    def test_secrets(self):
        r = lint.lint(dict(SINK, **{"connection.password": "s3cr3t", "connection.user": "u",
                                    "ssl.truststore.location": "/a", "aws.secret.access.key": "x",
                                    "key.converter": "org.apache.kafka.connect.storage.StringConverter"}), {})
        self.assertEqual(sorted(keys(r, "LOW")), ["aws.secret.access.key", "connection.password"])
        self.assertTrue(all(f["value"] == "****" for f in r["findings"]))
        r = lint.lint(dict(SINK, **{"connection.password": "${file:/secrets.properties:pw}"}), {})
        self.assertEqual(r["findings"], [])
        r = lint.lint(dict(SINK, **{"connection.password": "[hidden]"}), {})
        self.assertEqual(r["findings"], [])
        r = lint.lint(dict(SINK, **{"connection.uri": "mongodb://admin:pw@mongo:27017"}), {})
        self.assertIn("connection.uri", keys(r, "LOW"))
        r = lint.lint(dict(SINK, **{"sasl.jaas.config": 'org.apache.kafka.common.security.plain.PlainLoginModule required username="a" password="b";'}), {})
        self.assertIn("sasl.jaas.config", keys(r, "LOW"))
        r = lint.lint(dict(SINK, **{"sasl.jaas.config": 'PlainLoginModule required username="a" password="${file:/a:b}";'}), {})
        self.assertEqual(r["findings"], [])

    def test_fully_managed_skips_secrets_and_converters(self):
        r = lint.lint({"connector.class": "S3_SINK", "topics": "t", "kafka.api.secret": "x", "aws.secret.access.key": "y",
                       "input.data.format": "AVRO", "errors.tolerance": "all"}, {})
        self.assertEqual(r["findings"], [])
        r = lint.lint({"connector.class": "PostgresCdcSourceV2", "kafka.auth.mode": "KAFKA_API_KEY",
                       "database.password": "x"}, {})
        self.assertTrue(r["fully_managed"])
        self.assertEqual(r["findings"], [])
        # a short class name alias is self-managed
        r = lint.lint({"connector.class": "FileStreamSink", "topics": "t", "value.converter": "AvroConverter"}, {})
        self.assertFalse(r["fully_managed"])

    def test_cli_exit_codes_and_json(self):
        here = os.path.dirname(os.path.abspath(__file__))
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "c.json")
            with open(p, "w") as f:
                json.dump(dict(SINK, **{"errors.tolerance": "all", "tasks.max": 2}), f)
            out = subprocess.run([sys.executable, "-I", os.path.join(here, "lint.py"), "--config", p, "--json"],
                                 capture_output=True, text=True)
            self.assertEqual(out.returncode, 1)
            j = json.loads(out.stdout)
            self.assertFalse(j["ok"])
            self.assertEqual(j["warning_count"], 2)
            with open(p, "w") as f:
                json.dump(SINK, f)
            out = subprocess.run([sys.executable, "-I", os.path.join(here, "lint.py"), "--config", p],
                                 capture_output=True, text=True)
            self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
            self.assertIn("✅ no warning", out.stdout)


if __name__ == "__main__":
    unittest.main()
