"""
End of support of Confluent Platform and Confluent for Kubernetes versions, for playground analyze logs (🏷️ CP and 🛠️ CFK
tiles, the summary, the summary for a ticket): a version past its end of support is marked.

Copied from the tables of the docs (update them with each release):
  CP:  https://docs.confluent.io/platform/current/installation/versions-interoperability.html (Supported versions)
  CFK: https://docs.confluent.io/operator/current/co-supported-environments.html (Standard End of Support)
A version older than the oldest row of a table is out of support (the docs drop it).
"""

import re
from datetime import date, datetime
from typing import Dict, Optional, Tuple

FETCHED = "2026-11-07"
CP_DOC = "https://docs.confluent.io/platform/current/installation/versions-interoperability.html"
CFK_DOC = "https://docs.confluent.io/operator/current/co-supported-environments.html"

# minor: (release date, Confluent Community Software end of support, Enterprise Standard, Enterprise Platinum)
CP_SUPPORT = {
    "8.4": ("2026-10-27", "2027-10-27", "2028-10-27", "2029-10-27"),
    "8.3": ("2026-06-17", "2027-06-17", "2028-06-17", "2029-06-17"),
    "8.2": ("2026-03-04", "2027-03-04", "2028-03-04", "2029-03-04"),
    "8.1": ("2025-10-15", "2026-10-15", "2027-10-15", "2028-10-15"),
    "8.0": ("2025-06-11", "2026-06-11", "2027-06-11", "2028-06-11"),
    "7.9": ("2025-02-19", "2027-02-19", "2027-02-19", "2028-02-19"),
    "7.8": ("2024-12-02", "2026-12-02", "2026-12-02", "2027-12-02"),
    "7.7": ("2024-07-26", "2026-07-26", "2026-07-26", "2027-07-26"),
    "7.6": ("2024-02-09", "2026-02-09", "2026-02-09", "2027-02-09"),
}
# minor: (release date, Standard end of support)
CFK_SUPPORT = {
    "3.4": ("2026-10-28", "2028-10-28"),
    "3.3": ("2026-06-23", "2028-06-23"),
    "3.2": ("2026-03-11", "2028-03-11"),
    "3.1": ("2025-10-15", "2027-10-15"),
    "3.0": ("2025-06-13", "2027-06-13"),
    "2.11": ("2025-02-21", "2027-02-21"),
    "2.10": ("2024-12-04", "2026-12-04"),
}
# support ending within this many days: ⏳
SOON_DAYS = 180


def _minor(version: str) -> Optional[Tuple[int, int]]:
    parts = (version or "").lstrip("v").split(".")
    try:
        return int(parts[0]), int(parts[1])
    except (IndexError, ValueError):
        return None


def _d(text: str) -> date:
    return datetime.strptime(text, "%Y-%m-%d").date()


def _status(version: str, table: Dict[str, tuple], dates: Tuple[int, int], what: str, today: Optional[date]) -> dict:
    """state: supported | ending | standard_ended | ended | unknown; text: the short line for a tile"""
    today = today or date.today()
    m = _minor(version)
    if not m:
        return {"state": "unknown", "text": ""}
    key = f"{m[0]}.{m[1]}"
    known = sorted((_minor(k), k) for k in table)
    if key not in table:
        if m < known[0][0]:
            return {"state": "ended", "text": f"⛔ end of support: older than {known[0][1]}, the oldest {what} the docs still support"}
        return {"state": "unknown", "text": ""}
    row = table[key]
    standard, last = _d(row[dates[0]]), _d(row[dates[1]])
    if today > last:
        return {"state": "ended", "text": f"⛔ end of support since {last.isoformat()}", "until": last.isoformat()}
    if today > standard:
        return {"state": "standard_ended", "text": f"⚠️ Standard support ended {standard.isoformat()}, Platinum until {last.isoformat()}",
                "until": last.isoformat()}
    if (standard - today).days <= SOON_DAYS:
        days = (standard - today).days
        return {"state": "ending", "text": f"⏳ support ends {standard.isoformat()} (in {days} day{'s' if days != 1 else ''})",
                "until": standard.isoformat(), "days": days}
    return {"state": "supported", "text": f"✅ supported until {standard.isoformat()}", "until": standard.isoformat()}


def cp_status(version: str, today: Optional[date] = None) -> dict:
    """a Confluent Platform version (8.1.0, 7.6.3): Enterprise Standard end of support, then Platinum"""
    return _status(version, CP_SUPPORT, (2, 3), "Confluent Platform version", today)


def cfk_status(version: str, today: Optional[date] = None) -> dict:
    """a CFK operator version (3.1.0): Standard end of support (no extended support in the table)"""
    return _status(version, CFK_SUPPORT, (1, 1), "CFK version", today)


# the class of the 🏷️ CP / 🛠️ CFK tile: its color (ok green, warn amber, danger red) and a tinted background (support-*);
# an ended version also gets the ⛔ banner at the top of the log report
TILE_CLASS = {"ended": "danger support-ended", "standard_ended": "warn support-warn", "ending": "warn support-warn",
              "supported": "ok support-ok", "unknown": ""}


# ── Confluent Community (-ccs) ──────────────────────────────────────────────────────────────────────────────────────
def cp_community_status(version: str, today: Optional[date] = None) -> dict:
    """a Confluent Community Software version (x.y.z-ccs in the logs, no Enterprise license): its own end of support (about
    a year from 8.0, the "Confluent Community Software End of Support" column), no Standard / Platinum extension"""
    st = _status(version, CP_SUPPORT, (1, 1), "Confluent Platform version", today)
    if st["text"]:
        st["text"] = st["text"].replace("supported until", "Community supported until").replace("support ends", "Community support ends")
    return st


# ── clients ─────────────────────────────────────────────────────────────────────────────────────────────────────────
# https://docs.confluent.io/platform/current/clients/overview.html (Java client support, librdkafka and derived client
# support): minor: (release date, Standard end of support, Platinum / Cloud Premier end of support)
CLIENTS_DOC = "https://docs.confluent.io/platform/current/clients/overview.html"
JAVA_CLIENT_SUPPORT = {
    "4.3": ("2026-05-22", "2028-05-22", "2029-05-22"), "4.2": ("2026-02-17", "2028-02-17", "2029-02-17"),
    "4.1": ("2025-10-15", "2027-10-15", "2028-10-15"), "4.0": ("2025-03-18", "2027-03-18", "2028-03-18"),
    "3.9": ("2025-02-19", "2027-02-19", "2028-02-19"), "3.8": ("2024-07-26", "2026-07-26", "2027-07-26"),
    "3.7": ("2024-02-27", "2026-02-27", "2027-02-27"), "3.6": ("2023-10-11", "2025-10-11", "2026-10-11"),
    "3.5": ("2023-08-25", "2025-08-25", "2026-08-25"), "3.4": ("2023-05-04", "2025-05-04", "2026-05-04"),
    "3.3": ("2022-11-04", "2024-11-04", "2025-11-04"), "3.2": ("2022-07-06", "2024-07-06", "2025-07-06"),
    "3.1": ("2022-04-05", "2024-04-05", "2025-04-05"), "3.0": ("2021-10-27", "2023-10-27", "2024-10-27"),
    "2.8": ("2021-06-08", "2023-06-08", "2024-06-08"), "2.7": ("2021-02-09", "2023-02-09", "2024-02-09"),
    "2.6": ("2020-09-24", "2022-09-24", "2023-09-24"), "2.5": ("2020-04-24", "2022-04-24", "2023-04-24"),
    "2.4": ("2020-01-10", "2022-01-10", "2023-01-10"), "2.3": ("2019-07-19", "2021-07-19", "2022-07-19"),
    "2.2": ("2019-03-28", "2021-03-28", "2022-03-28"), "2.1": ("2018-12-14", "2020-12-14", "2021-12-14"),
    "2.0": ("2018-07-31", "2020-07-31", "2021-07-31"), "1.1": ("2018-04-16", "2020-04-16", "2021-04-16"),
}
LIBRDKAFKA_SUPPORT = {
    "2.16": ("2026-10-07", "2028-10-07", "2029-10-07"), "2.15": ("2026-06-30", "2028-06-30", "2029-06-30"),
    "2.14": ("2026-04-02", "2028-04-02", "2029-04-02"), "2.13": ("2026-01-05", "2028-01-05", "2029-01-05"),
    "2.12": ("2025-10-08", "2027-10-08", "2028-10-08"), "2.11": ("2025-07-03", "2027-07-03", "2028-07-03"),
    "2.10": ("2025-04-17", "2027-04-17", "2028-04-17"), "2.9": ("2025-04-01", "2027-04-01", "2028-04-01"),
    "2.8": ("2025-01-07", "2027-01-07", "2028-01-07"), "2.7": ("2024-12-21", "2026-12-21", "2027-12-21"),
    "2.6": ("2024-10-10", "2026-10-10", "2027-10-10"), "2.5": ("2024-07-10", "2026-07-10", "2027-07-10"),
    "2.4": ("2024-05-07", "2026-05-07", "2027-05-07"), "2.3": ("2023-10-25", "2025-10-25", "2026-10-25"),
}


def java_client_status(version: str, today: Optional[date] = None) -> dict:
    """an Apache Kafka Java client version ("Kafka version: 3.6.1" of AppInfoParser, without -ce / -ccs)"""
    return _status(version, JAVA_CLIENT_SUPPORT, (1, 2), "Java client version", today)


def librdkafka_status(version: str, today: Optional[date] = None) -> dict:
    """a librdkafka version (the C library under the Python, Go, .NET, JavaScript clients)"""
    return _status(version, LIBRDKAFKA_SUPPORT, (1, 2), "librdkafka version", today)


# ── connectors ──────────────────────────────────────────────────────────────────────────────────────────────────────
# the minimum connector version supported on each Confluent Platform release, as per the Connector lifecycle support
# policy: https://docs.confluent.io/platform/<x.y>/connect/supported-connector-version.html (fetched on FETCHED; copy
# the new release's table here). An older plugin version is not supported on that release.
CONNECTORS_DOC = "https://docs.confluent.io/platform/{minor}/connect/supported-connector-version.html"
_CONNECTOR_TABLES = {
    # 7.9: the page lists Netezza Sink 2.14.0 and Oracle CDC Source Connector 1.0.0 (looks swapped): both left out
    "7.9": """ActiveMQ Sink | 2.1.0
ActiveMQ Source | 12.2.0
Amazon CloudWatch Logs Source | 1.3.0
Amazon CloudWatch Metrics Sink | 2.0.0
Amazon Kinesis Source | 1.3.0
Amazon S3 Sink | 10.5.0
Amazon S3 Source | 2.6.0
Amazon SQS Source | 2.0.0
Apache HBase Sink | 2.0.0
Appdynamics Metrics Sink | 2.0.0
AWS DynamoDB Sink | 1.4.0
AWS Lambda Sink | 2.0.0
AWS Redshift Sink | 1.2.0
Azure Blob Storage Sink | 1.6.0
Azure Blob Storage Source | 2.6.0
Azure Cognitive Search Sink | 1.1.0
Azure Data Lake Storage Gen2 Sink | 1.6.0
Azure Event Hubs Source | 2.0.0
Azure Functions Sink | 2.0.0
Azure Service Bus Source | 1.2.0
Azure Synapse Analytics Sink | 1.0.0
Cassandra Sink | 2.0.0
Databricks Delta Lake Sink | 1.0.0
Data Diode (Source and Sink) | 1.2.0
Datadog Metrics Sink | 2.0.0
Elasticsearch Sink | 14.1.0
GitHub Source | 2.1.0
Google BigQuery Sink | 2.5.0
Google Cloud BigTable Sink | 2.0.0
Google Cloud Dataproc Sink Connector | 1.3.0
Google Cloud Functions Sink | 1.2.0
Google Cloud Pub/Sub Source Connector | 1.2.0
Google Cloud Spanner Sink | 1.0.0
Google Cloud Storage Sink | 10.2.0
Google Cloud Storage Source | 2.6.0
Google Firebase Connector | 1.2.0
HEAVY-AI (formerly OmniSci) Sink | 1.0.0
HDFS 2 Sink | 10.2.0
HDFS 2 Source | 2.6.0
HDFS 3 Sink | 1.1.0
HDFS 3 Source | 2.6.0
HTTP Sink | 1.7.0
HTTP Source | 0.2.0
IBM MQ Sink Connector | 2.1.0
IBM MQ Source | 12.1.0
InfluxDB Connector (Source and Sink) | 1.2.0
JDBC (Source and Sink) | 10.8.0
Jira Source | 1.2.0
JMS Sink | 2.1.0
JMS Source | 12.2.0
Kudu (Source and Sink) | 1.0.0
MapR-DB Sink | 1.1.0
MongoDB Source (Debezium) | 2.4.0
MQTT (Source and Sink) | 1.7.0
MySQL Source (Debezium) | 2.4.0
Oracle XStream CDC Source Connector | 1.0.0
PagerDuty Sink | 1.0.0
PostgresSQL Source (Debezium) | 2.5.0
Prometheus Metrics Sink | 2.0.0
RabbitMQ Sink | 1.8.0
RabbitMQ Source | 1.8.0
Redis Sink | 0.0.0
Salesforce Bulk API Source | 2.0.0
Salesforce Change Data Capture Source | 2.0.0
Salesforce (Source and Sink) | 2.0.0
ServiceNow (Source and Sink) | 2.5.0
SFTP (Source and Sink) | 3.2.0
SNMP Trap Source | 1.3.0
Solace Sink | 2.1.0
Solace Source | 1.2.0
Splunk Sink | 2.2.0
Splunk Source Connector | 2.0.0
Splunk S2S Source | 2.2.0
Spool Dir Connector | 2.0.0
SQL Server Source (Debezium) | 2.5.0
Syslog Source Connector | 1.5.0
Teradata (Source and Sink) | 1.1.0
TIBCO Sink | 2.1.0
TIBCO Source | 1.2.0
Vertica Sink | 1.3.0
VMware Tanzu Gemfire Sink | 1.0.0
Zendesk Source | 1.3.0""",
    "8.0": """ActiveMQ Sink | 2.1.16
ActiveMQ Source | 13.0.3
Amazon CloudWatch Logs Source | 1.3.3
Amazon CloudWatch Metrics Sink | 2.0.4
Amazon Kinesis Source | 1.3.28
Amazon S3 Sink | 10.6.0
Amazon S3 Source | 2.6.16
Amazon SQS Source | 2.0.6
Apache HBase Sink | 2.0.0
Appdynamics Metrics Sink | 2.0.4
AWS DynamoDB Sink | 1.5.0
AWS Lambda Sink | 2.0.13
AWS Redshift Sink | 1.2.5
Azure Blob Storage Sink | 1.6.25
Azure Blob Storage Source | 2.6.16
Azure Cognitive Search Sink | 1.1.8
Azure Data Lake Storage Gen2 Sink | 1.6.0
Azure Event Hubs Source | 2.0.11
Azure Functions Sink | 2.0.7
Azure Service Bus Source | 1.2.16
Azure Synapse Analytics Sink | 1.0.10
Cassandra Sink | 2.0.11
Databricks Delta Lake Sink | 1.0.20
Data Diode (Source and Sink) | 1.2.8
Datadog Metrics Sink | 2.0.4
Elasticsearch Sink | 14.1.0
GitHub Source | 2.1.10
Google BigQuery Sink | 2.5.0
Google Cloud BigTable Sink | 2.0.28
Google Cloud Dataproc Sink Connector | 1.3.2
Google Cloud Functions Sink | 1.2.5
Google Cloud Pub/Sub Source Connector | 1.2.10
Google Cloud Spanner Sink | 1.1.2
Google Cloud Storage Sink | 10.3.3
Google Cloud Storage Source | 2.6.16
Google Firebase Connector | 1.2.7
HEAVY-AI (formerly OmniSci) Sink | 1.0.10
HDFS 2 Sink | 10.2.0
HDFS 2 Source | 2.6.16
HDFS 3 Sink | 1.2.0
HDFS 3 Source | 2.6.16
HTTP Sink | 1.7.10
HTTP Source | 0.2.0
IBM MQ Sink Connector | 2.1.16
IBM MQ Source | 13.0.3
InfluxDB Connector (Source and Sink) | 1.2.11
JDBC (Source and Sink) | 10.8.0
Jira Source | 1.2.14
JMS Sink | 2.1.16
JMS Source | 13.0.3
Kudu (Source and Sink) | 1.0.6
MongoDB Source (Debezium) | 2.5.0
MQTT (Source and Sink) | 1.7.5
MySQL Source (Debezium) | 3.0.0
Netezza Sink | 1.0.7
Oracle CDC Source Connector | 2.14.9
Oracle XStream CDC Source Connector | 1.1.0
PagerDuty Sink | 1.0.12
PostgresSQL Source (Debezium) | 2.5.0
Prometheus Metrics Sink | 2.0.4
RabbitMQ Sink | 1.8.1
RabbitMQ Source | 1.8.1
Redis Sink | 0.0.7
Salesforce Bulk API Source | 2.0.29
Salesforce Change Data Capture Source | 2.0.29
Salesforce (Source and Sink) | 2.0.29
ServiceNow (Source and Sink) | 2.5.6
SFTP (Source and Sink) | 3.2.0
SNMP Trap Source | 1.3.3
Solace Sink | 2.1.16
Solace Source | 1.2.12
Splunk Sink | 2.2.0
Splunk Source Connector | 1.1.6
Splunk S2S Source | 2.2.3
Spool Dir Connector | 2.0.0
SQL Server Source (Debezium) | 2.5.0
Syslog Source Connector | 1.5.12
Teradata (Source and Sink) | 1.1.3
TIBCO Sink | 2.1.16
TIBCO Source | 1.2.12
Vertica Sink | 1.3.0
VMware Tanzu Gemfire Sink | 1.0.20
Zendesk Source | 1.3.4""",
    "8.1": """ActiveMQ Sink | 2.1.19
ActiveMQ Source | 13.0.3
Amazon CloudWatch Logs Source | 1.4.1
Amazon CloudWatch Metrics Sink | 2.0.5
Amazon Kinesis Source | 1.3.30
Amazon S3 Sink | 11.0.2
Amazon S3 Source | 2.6.18
Amazon SQS Source | 2.0.7
Apache HBase Sink | 2.0.31
Appdynamics Metrics Sink | 2.0.5
AWS DynamoDB Sink | 1.5.1
AWS Lambda Sink | 2.0.13
AWS Redshift Sink | 1.2.8
Azure Blob Storage Sink | 1.7.1
Azure Blob Storage Source | 2.6.18
Azure Cognitive Search Sink | 1.1.10
Azure Data Lake Storage Gen2 Sink | 1.7.1
Azure Event Hubs Source | 2.0.12
Azure Functions Sink | 2.0.7
Azure Service Bus Source | 1.2.16
Azure Synapse Analytics Sink | 1.0.10
Cassandra Sink | 2.0.11
Databricks Delta Lake Sink | 1.0.24
Data Diode (Source and Sink) | 1.2.8
Datadog Metrics Sink | 2.0.5
Elasticsearch Sink | 15.0.1
GitHub Source | 2.1.10
Google BigQuery Sink | 2.5.7
Google Cloud BigTable Sink | 2.0.31
Google Cloud Dataproc Sink Connector | 1.3.5
Google Cloud Functions Sink | 1.2.5
Google Cloud Pub/Sub Source Connector | 1.2.12
Google Cloud Spanner Sink | 1.1.3
Google Cloud Storage Sink | 10.3.4
Google Cloud Storage Source | 2.6.18
Google Firebase Connector | 1.2.9
HEAVY-AI (formerly OmniSci) Sink | 1.0.10
HDFS 2 Sink | 10.2.17
HDFS 2 Source | 3.0.0
HDFS 3 Sink | 2.0.3
HDFS 3 Source | 3.0.0
HTTP Sink | 1.7.10
HTTP Source | 1.0.1
IBM MQ Sink Connector | 2.1.19
IBM MQ Source | 13.0.3
InfluxDB Connector (Source and Sink) | 1.2.11
JDBC (Source and Sink) | 10.8.4
Jira Source | 1.2.14
JMS Sink | 2.1.19
JMS Source | 13.0.2
Kudu (Source and Sink) | 1.0.6
MapR-DB Sink | 1.1.3
MongoDB Source (Debezium) | 3.1.2
MQTT (Source and Sink) | 1.7.6
MySQL Source (Debezium) | 3.1.2
Netezza Sink | 1.0.7
Oracle CDC Source Connector | 2.14.10
Oracle XStream CDC Source Connector | 1.2.1
PagerDuty Sink | 1.0.13
PostgresSQL Source (Debezium) | 3.1.2
Prometheus Metrics Sink | 2.0.5
RabbitMQ Sink | 1.8.1
RabbitMQ Source | 1.8.1
Redis Sink | 0.0.8
Salesforce Bulk API Source | 3.0.5
Salesforce Change Data Capture Source | 3.0.5
Salesforce (Source and Sink) | 3.0.5
ServiceNow (Source and Sink) | 2.5.8
SFTP (Source and Sink) | 3.2.16
SNMP Trap Source | 1.3.3
Solace Sink | 2.1.19
Solace Source | 1.2.12
Splunk Sink | 2.2.2
Splunk Source Connector | 1.2.9
Splunk S2S Source | 2.3.2
Spool Dir Connector | 2.0.70
SQL Server Source (Debezium) | 3.1.2
Syslog Source Connector | 1.5.13
Teradata (Source and Sink) | 1.1.3
TIBCO Sink | 2.1.19
TIBCO Source | 1.2.12
Vertica Sink | 1.3.2
VMware Tanzu Gemfire Sink | 1.0.20
Zendesk Source | 1.3.6""",
    "8.2": """ActiveMQ Sink | 2.2.0
ActiveMQ Source | 13.0.5
Amazon CloudWatch Logs Source | 2.0.2
Amazon CloudWatch Metrics Sink | 2.0.9
Amazon Kinesis Source | 2.0.2
Amazon S3 Sink | 12.0.1
Amazon S3 Source | 3.0.4
Amazon SQS Source | 2.0.8
Apache HBase Sink | 2.0.34
Appdynamics Metrics Sink | 2.0.9
AWS DynamoDB Sink | 1.5.2
AWS Lambda Sink | 3.0.1
AWS Redshift Sink | 1.2.8
Azure Blob Storage Sink | 2.0.3
Azure Blob Storage Source | 3.0.4
Azure Cognitive Search Sink | 1.1.13
Azure Data Lake Storage Gen2 Sink | 2.0.3
Azure Event Hubs Source | 2.0.17
Azure Functions Sink | 2.0.10
Azure Service Bus Source | 1.2.16
Azure Synapse Analytics Sink | 1.0.12
Cassandra Sink | 2.0.14
Databricks Delta Lake Sink | 1.0.26
Data Diode (Source and Sink) | 1.2.8
Datadog Metrics Sink | 2.0.9
Elasticsearch Sink | 15.1.1
GitHub Source | 2.1.10
Google BigQuery Sink | 2.5.7
Google Cloud BigTable Sink | 2.0.34
Google Cloud Dataproc Sink Connector | 1.3.5
Google Cloud Functions Sink | 1.2.5
Google Cloud Pub/Sub Source Connector | 1.2.13
Google Cloud Spanner Sink | 1.1.4
Google Cloud Storage Sink | 11.0.2
Google Cloud Storage Source | 3.0.4
Google Firebase Connector | 1.2.10
HEAVY-AI (formerly OmniSci) Sink | 1.0.11
HDFS 2 Sink | 10.2.17
HDFS 2 Source | 3.0.4
HDFS 3 Sink | 3.0.5
HDFS 3 Source | 3.0.4
HTTP Sink | 1.7.12
HTTP Source | 1.0.1
IBM MQ Sink Connector | 2.2.0
IBM MQ Source | 13.0.5
InfluxDB Connector (Source and Sink) | 1.2.11
JDBC (Source and Sink) | 10.9.2
Jira Source | 1.3.1
JMS Sink | 2.2.0
JMS Source | 13.0.5
Kudu (Source and Sink) | 1.0.6
MapR-DB Sink | 1.1.3
MongoDB Source (Debezium) | 3.1.2
MQTT (Source and Sink) | 1.7.6
MySQL Source (Debezium) | 3.1.2
Netezza Sink | 1.0.7
Oracle CDC Source Connector | 2.15.0
Oracle XStream CDC Source Connector | 1.3.2
PagerDuty Sink | 1.0.13
PostgresSQL Source (Debezium) | 3.1.2
Prometheus Metrics Sink | 2.0.9
RabbitMQ Sink | 1.8.1
RabbitMQ Source | 1.8.1
Redis Sink | 0.0.8
Salesforce Bulk API Source | 3.1.1
Salesforce Change Data Capture Source | 3.0.5
Salesforce (Source and Sink) | 3.1.1
ServiceNow (Source and Sink) | 2.6.1
SFTP (Source and Sink) | 3.2.18
SNMP Trap Source | 1.3.3
Solace Sink | 2.2.0
Solace Source | 1.2.12
Splunk Sink | 2.2.4
Splunk Source Connector | 1.1.7
Splunk S2S Source | 2.3.4
Spool Dir Connector | 2.0.71
SQL Server Source (Debezium) | 3.1.2
Syslog Source Connector | 1.5.13
Teradata (Source and Sink) | 2.0.2
TIBCO Sink | 2.2.0
TIBCO Source | 1.2.12
Vertica Sink | 1.3.3
VMware Tanzu Gemfire Sink | 1.0.21
Zendesk Source | 1.3.7""",
    "8.3": """ActiveMQ Sink | 2.2.2
ActiveMQ Source | 13.0.10
Amazon CloudWatch Logs Source | 2.0.6
Amazon CloudWatch Metrics Sink | 2.0.13
Amazon Kinesis Source | 2.0.6
Amazon S3 Sink | 12.1.5
Amazon S3 Source | 3.0.11
Amazon SQS Source | 2.0.11
Apache HBase Sink | 2.0.39
Appdynamics Metrics Sink | 2.0.13
AWS DynamoDB Sink | 1.5.6
AWS Lambda Sink | 3.0.4
AWS Redshift Sink | 1.2.10
Azure Blob Storage Sink | 2.2.3
Azure Blob Storage Source | 3.0.11
Azure Cognitive Search Sink | 1.1.19
Azure Data Lake Storage Gen2 Sink | 2.2.3
Azure Event Hubs Source | 2.0.20
Azure Functions Sink | 2.0.13
Azure Service Bus Source | 1.3.3
Azure Synapse Analytics Sink | 1.0.13
Cassandra Sink | 2.0.17
Databricks Delta Lake Sink | 1.0.30
Data Diode (Source and Sink) | 1.2.9
Datadog Metrics Sink | 2.0.13
Elasticsearch Sink | 15.1.2
GitHub Source | 2.1.11
Google BigQuery Sink | 2.5.10
Google Cloud BigTable Sink | 2.0.39
Google Cloud Dataproc Sink Connector | 1.3.5
Google Cloud Functions Sink | 1.2.8
Google Cloud Pub/Sub Source Connector | 1.2.19
Google Cloud Spanner Sink | 1.2.3
Google Cloud Storage Sink | 11.0.11
Google Cloud Storage Source | 3.0.11
Google Firebase Connector | 1.2.16
HEAVY-AI (formerly OmniSci) Sink | 1.0.11
HDFS 2 Sink | 10.2.17
HDFS 2 Source | 3.0.11
HDFS 3 Sink | 3.0.12
HDFS 3 Source | 3.0.11
HTTP Sink | 1.7.13
HTTP Source | 1.0.3
IBM MQ Sink Connector | 2.2.2
IBM MQ Source | 13.0.10
InfluxDB Connector (Source and Sink) | 1.2.12
JDBC (Source and Sink) | 10.9.3
Jira Source | 1.3.3
JMS Sink | 2.2.2
JMS Source | 13.0.10
Kudu (Source and Sink) | 1.0.7
MapR-DB Sink | 1.1.3
MongoDB Source (Debezium) | 3.1.2
MQTT (Source and Sink) | 1.7.8
MySQL Source (Debezium) | 3.2.6-1
Netezza Sink | 1.0.8
Oracle CDC Source Connector | 2.15.1
Oracle XStream CDC Source Connector | 1.4.1
PagerDuty Sink | 1.0.13
PostgresSQL Source (Debezium) | 3.2.6-1
Prometheus Metrics Sink | 2.0.13
RabbitMQ Sink | 1.8.3
RabbitMQ Source | 1.8.3
Redis Sink | 0.0.9
Salesforce Bulk API Source | 3.1.6
Salesforce Change Data Capture Source | 3.1.6
Salesforce (Source and Sink) | 3.1.6
ServiceNow (Source and Sink) | 2.6.5
SFTP (Source and Sink) | 3.2.21
SNMP Trap Source | 1.3.6
Solace Sink | 2.2.2
Solace Source | 1.2.13
Splunk Sink | 2.2.6
Splunk Source Connector | 1.1.7
Splunk S2S Source | 2.3.8
Spool Dir Connector | 2.0.71
SQL Server Source (Debezium) | 3.2.6-1
Syslog Source Connector | 1.5.16
Teradata (Source and Sink) | 2.0.4
TIBCO Sink | 2.2.2
TIBCO Source | 1.2.13
Vertica Sink | 1.3.3
VMware Tanzu Gemfire Sink | 1.0.23
Zendesk Source | 1.3.8""",
    "8.4": """ActiveMQ Sink | 2.2.3
ActiveMQ Source | 13.0.11
Amazon CloudWatch Logs Source | 2.0.11
Amazon CloudWatch Metrics Sink | 2.0.18
Amazon Kinesis Source | 2.0.12
Amazon S3 Sink | 12.1.11
Amazon S3 Source | 3.1.8
Amazon SQS Source | 2.1.2
Apache HBase Sink | 2.0.45
Appdynamics Metrics Sink | 2.0.18
AWS DynamoDB Sink | 1.5.9
AWS Lambda Sink | 3.0.9
AWS Redshift Sink | 1.2.10
Azure Blob Storage Sink | 2.2.9
Azure Blob Storage Source | 3.1.8
Azure Cognitive Search Sink | 1.1.21
Azure Data Lake Storage Gen2 Sink | 2.2.9
Azure Event Hubs Source | 2.1.6
Azure Functions Sink | 2.0.16
Azure Service Bus Source | 1.3.9
Azure Synapse Analytics Sink | 1.0.13
Cassandra Sink | 2.0.20
Databricks Delta Lake Sink | 1.0.32
Data Diode (Source and Sink) | 1.2.9
Datadog Metrics Sink | 2.0.18
Elasticsearch Sink | 15.1.3
GitHub Source | 2.1.14
Google BigQuery Sink | 2.5.11
Google Cloud BigTable Sink | 2.0.45
Google Cloud Dataproc Sink Connector | 1.3.5
Google Cloud Functions Sink | 1.2.12
Google Cloud Pub/Sub Source Connector | 1.2.25
Google Cloud Spanner Sink | 1.2.10
Google Cloud Storage Sink | 11.0.19
Google Cloud Storage Source | 3.1.8
Google Firebase Connector | 1.2.21
HEAVY-AI (formerly OmniSci) Sink | 1.0.14
HDFS 2 Sink | 10.2.17
HDFS 2 Source | 3.1.8
HDFS 3 Sink | 3.0.21
HDFS 3 Source | 3.1.8
HTTP Sink | 1.7.13
HTTP Source | 1.0.5
IBM MQ Sink Connector | 2.2.3
IBM MQ Source | 13.0.11
InfluxDB Connector (Source and Sink) | 1.2.12
JDBC (Source and Sink) | 10.9.9
Jira Source | 1.3.5
JMS Sink | 2.2.3
JMS Source | 13.0.11
Kudu (Source and Sink) | 1.0.7
MapR-DB Sink | 1.1.3
MongoDB Source (Debezium) | 3.2.6-3
MQTT (Source and Sink) | 1.7.9
MySQL Source (Debezium) | 3.2.6-3
Netezza Sink | 1.0.9
Oracle CDC Source Connector | 2.15.2
Oracle XStream CDC Source Connector | 1.6.1
PagerDuty Sink | 1.0.13
PostgresSQL Source (Debezium) | 3.2.6-3
Prometheus Metrics Sink | 2.0.18
RabbitMQ Sink | 1.8.10
RabbitMQ Source | 1.8.10
Redis Sink | 0.0.12
Salesforce Bulk API Source | 3.1.10
Salesforce Change Data Capture Source | 3.1.10
Salesforce (Source and Sink) | 3.1.10
ServiceNow (Source and Sink) | 2.6.6
SFTP (Source and Sink) | 3.2.24
SNMP Trap Source | 1.3.6
Solace Sink | 2.2.3
Solace Source | 1.2.15
Splunk Sink | 2.2.7
Splunk Source Connector | 2.0.2
Splunk S2S Source | 2.3.11
Spool Dir Connector | 2.0.71
SQL Server Source (Debezium) | 3.2.6-3
Syslog Source Connector | 1.5.17
Teradata (Source and Sink) | 2.0.4
TIBCO Sink | 2.2.3
TIBCO Source | 1.2.15
Vertica Sink | 1.3.3
VMware Tanzu Gemfire Sink | 1.0.27
Zendesk Source | 1.3.11""",
}
CONNECTOR_MIN = {cp: dict(tuple(x.strip() for x in line.split("|")) for line in text.strip().splitlines())
                 for cp, text in _CONNECTOR_TABLES.items()}

# the class of a connector (short name) -> its row in the tables above
CONNECTOR_ROWS = {
    "ActiveMQSourceConnector": "ActiveMQ Source", "ActiveMqSinkConnector": "ActiveMQ Sink",
    "AwsCloudWatchSourceConnector": "Amazon CloudWatch Logs Source", "AwsCloudWatchMetricsSinkConnector": "Amazon CloudWatch Metrics Sink",
    "KinesisSourceConnector": "Amazon Kinesis Source", "S3SinkConnector": "Amazon S3 Sink", "S3SourceConnector": "Amazon S3 Source",
    "SqsSourceConnector": "Amazon SQS Source", "HBaseSinkConnector": "Apache HBase Sink",
    "AppDynamicsMetricsSinkConnector": "Appdynamics Metrics Sink", "DynamoDbSinkConnector": "AWS DynamoDB Sink",
    "AwsLambdaSinkConnector": "AWS Lambda Sink", "RedshiftSinkConnector": "AWS Redshift Sink",
    "AzureBlobStorageSinkConnector": "Azure Blob Storage Sink", "AzureBlobStorageSourceConnector": "Azure Blob Storage Source",
    "AzureSearchSinkConnector": "Azure Cognitive Search Sink", "AzureDataLakeGen2SinkConnector": "Azure Data Lake Storage Gen2 Sink",
    "EventHubsSourceConnector": "Azure Event Hubs Source", "AzureFunctionsSinkConnector": "Azure Functions Sink",
    "ServiceBusSourceConnector": "Azure Service Bus Source", "AzureSqlDwSinkConnector": "Azure Synapse Analytics Sink",
    "CassandraSinkConnector": "Cassandra Sink", "DatabricksDeltaLakeSinkConnector": "Databricks Delta Lake Sink",
    "DataDiodeSinkConnector": "Data Diode (Source and Sink)", "DataDiodeSourceConnector": "Data Diode (Source and Sink)",
    "DatadogMetricsSinkConnector": "Datadog Metrics Sink", "ElasticsearchSinkConnector": "Elasticsearch Sink",
    "GithubSourceConnector": "GitHub Source", "BigQuerySinkConnector": "Google BigQuery Sink",
    "BigtableSinkConnector": "Google Cloud BigTable Sink", "DataprocSinkConnector": "Google Cloud Dataproc Sink Connector",
    "GoogleCloudFunctionsSinkConnector": "Google Cloud Functions Sink", "PubSubSourceConnector": "Google Cloud Pub/Sub Source Connector",
    "SpannerSinkConnector": "Google Cloud Spanner Sink", "GcsSinkConnector": "Google Cloud Storage Sink",
    "GcsSourceConnector": "Google Cloud Storage Source", "FirebaseSinkConnector": "Google Firebase Connector",
    "FirebaseSourceConnector": "Google Firebase Connector", "OmnisciSinkConnector": "HEAVY-AI (formerly OmniSci) Sink",
    "HdfsSinkConnector": "HDFS 2 Sink", "Hdfs2SourceConnector": "HDFS 2 Source", "Hdfs3SinkConnector": "HDFS 3 Sink",
    "Hdfs3SourceConnector": "HDFS 3 Source", "HttpSinkConnector": "HTTP Sink", "HttpSourceConnector": "HTTP Source",
    "IbmMqSinkConnector": "IBM MQ Sink Connector", "IbmMQSourceConnector": "IBM MQ Source",
    "InfluxDBSinkConnector": "InfluxDB Connector (Source and Sink)", "InfluxdbSourceConnector": "InfluxDB Connector (Source and Sink)",
    "JdbcSinkConnector": "JDBC (Source and Sink)", "JdbcSourceConnector": "JDBC (Source and Sink)", "JiraSourceConnector": "Jira Source",
    "JmsSinkConnector": "JMS Sink", "JmsSourceConnector": "JMS Source", "KuduSinkConnector": "Kudu (Source and Sink)",
    "KuduSourceConnector": "Kudu (Source and Sink)", "MapRDbSinkConnector": "MapR-DB Sink", "MongoDbConnector": "MongoDB Source (Debezium)",
    "MqttSinkConnector": "MQTT (Source and Sink)", "MqttSourceConnector": "MQTT (Source and Sink)", "MySqlConnector": "MySQL Source (Debezium)",
    "NetezzaSinkConnector": "Netezza Sink", "OracleCdcSourceConnector": "Oracle CDC Source Connector",
    "OracleXStreamSourceConnector": "Oracle XStream CDC Source Connector", "PagerDutySinkConnector": "PagerDuty Sink",
    "PostgresConnector": "PostgresSQL Source (Debezium)", "PrometheusMetricsSinkConnector": "Prometheus Metrics Sink",
    "RabbitMQSinkConnector": "RabbitMQ Sink", "RabbitMQSourceConnector": "RabbitMQ Source", "RedisSinkConnector": "Redis Sink",
    "SalesforceBulkApiSourceConnector": "Salesforce Bulk API Source", "SalesforceCdcSourceConnector": "Salesforce Change Data Capture Source",
    "SalesforceBulkApiSinkConnector": "Salesforce (Source and Sink)", "SalesforcePushTopicSourceConnector": "Salesforce (Source and Sink)",
    "SalesforcePlatformEventSourceConnector": "Salesforce (Source and Sink)", "SalesforcePlatformEventSinkConnector": "Salesforce (Source and Sink)",
    "SalesforceSObjectSinkConnector": "Salesforce (Source and Sink)", "ServiceNowSinkConnector": "ServiceNow (Source and Sink)",
    "ServiceNowSourceConnector": "ServiceNow (Source and Sink)", "SftpSinkConnector": "SFTP (Source and Sink)",
    "SftpCsvSourceConnector": "SFTP (Source and Sink)", "SftpJsonSourceConnector": "SFTP (Source and Sink)",
    "SftpSchemaLessJsonSourceConnector": "SFTP (Source and Sink)", "SftpBinaryFileSourceConnector": "SFTP (Source and Sink)",
    "SnmpTrapSourceConnector": "SNMP Trap Source", "SolaceSinkConnector": "Solace Sink", "SolaceSourceConnector": "Solace Source",
    "SplunkSinkConnector": "Splunk Sink", "SplunkHttpSourceConnector": "Splunk Source Connector", "SplunkS2SSourceConnector": "Splunk S2S Source",
    "SpoolDirCsvSourceConnector": "Spool Dir Connector", "SpoolDirJsonSourceConnector": "Spool Dir Connector",
    "SpoolDirLineDelimitedSourceConnector": "Spool Dir Connector", "SpoolDirSchemaLessJsonSourceConnector": "Spool Dir Connector",
    "SpoolDirAvroSourceConnector": "Spool Dir Connector", "SpoolDirBinaryFileSourceConnector": "Spool Dir Connector",
    "SqlServerConnector": "SQL Server Source (Debezium)", "SyslogSourceConnector": "Syslog Source Connector",
    "TeradataSinkConnector": "Teradata (Source and Sink)", "TeradataSourceConnector": "Teradata (Source and Sink)",
    "TibcoSinkConnector": "TIBCO Sink", "TibcoSourceConnector": "TIBCO Source", "VerticaSinkConnector": "Vertica Sink",
    "PivotalGemfireSinkConnector": "VMware Tanzu Gemfire Sink", "ZendeskSourceConnector": "Zendesk Source",
}


def _numbers(version: str) -> Tuple[int, ...]:
    """the first three numbers of a version: 10.7.4, 3.2.6.Final, 3.2.6-3 (a packaging revision, ignored)"""
    out = []
    for part in re.split(r"[.\-]", version or "")[:3]:
        m = re.match(r"\d+", part)
        if not m:
            break
        out.append(int(m.group(0)))
    return tuple(out)


def connector_status(cls: str, version: str, cp_version: str) -> dict:
    """a connector plugin version against the minimum version supported on the Confluent Platform release of the worker.
    state: supported | unsupported | unknown (class not in the tables, no table for that release, no version)"""
    row = CONNECTOR_ROWS.get((cls or "").split(".")[-1])
    m = _minor(cp_version)
    cp = f"{m[0]}.{m[1]}" if m else None
    if not row or not cp or not _numbers(version):
        return {"state": "unknown", "text": ""}
    table = CONNECTOR_MIN.get(cp)
    if table is None or row not in table:
        return {"state": "unknown", "text": "", "row": row, "cp": cp}
    minimum = table[row]
    doc = CONNECTORS_DOC.format(minor=cp)
    if _numbers(version) < _numbers(minimum):
        return {"state": "unsupported", "row": row, "cp": cp, "minimum": minimum, "doc": doc,
                "text": f"⛔ {version} is older than {minimum}, the minimum {row} version supported on CP {cp}"}
    return {"state": "supported", "row": row, "cp": cp, "minimum": minimum, "doc": doc,
            "text": f"✅ supported on CP {cp} (minimum {minimum})"}
