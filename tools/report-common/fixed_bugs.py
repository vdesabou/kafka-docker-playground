"""
Known bugs of connector plugins with the versions that fix them, for playground analyze logs (🩹): a record that matches
the pattern of a bug, logged by a connector whose plugin version the logs give (🏷️ "Instantiated connector … with
version …"), gets a verdict: affected (upgrade to …), fixed in its version (another cause, or a regression), or unknown
version.

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
]


def parse_version(v: str) -> Optional[Tuple[int, ...]]:
    m = re.match(r"^v?(\d+(?:\.\d+)*)", v or "")
    return tuple(int(x) for x in m.group(1).split(".")) if m else None


def verdict(version: str, fixed_in: List[str]) -> Tuple[str, Optional[str]]:
    """(affected | fixed | unknown, the version to upgrade to): the first fixed version of the minor line of `version`;
    a line older than every fixed line is affected (upgrade to the first fixed version above it), a line newer than all
    of them has the fix"""
    v = parse_version(version)
    fixed = sorted((p, f) for f in fixed_in for p in [parse_version(f)] if p)
    if not v or not fixed:
        return "unknown", None
    line = v[:2]
    for p, f in fixed:
        if p[:2] == line:
            return ("fixed", None) if v >= p else ("affected", f)
    above = [f for p, f in fixed if p[:2] > line]
    if above:
        return "affected", above[0]
    return "fixed", None
