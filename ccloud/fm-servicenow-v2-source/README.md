# Fully Managed ServiceNow Source V2 connector

## Objective

Quickly test the [ServiceNow Source V2](https://docs.confluent.io/cloud/current/connectors/cc-servicenow-source-v2.html) fully managed connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* A ServiceNow instance (see [ServiceNow setup](#servicenow-setup))

| Variable | Description |
| --- | --- |
| `SERVICENOW_URL` | ServiceNow instance URL, ending with `/` (e.g. `https://dev12345.service-now.com/`) |
| `SERVICENOW_PASSWORD` | Password of the ServiceNow `admin` user |

## How to run

```bash
playground run -f fully-managed-servicenow-v2-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-servicenow-v2-source.sh` | Reads table `incident` (Avro output) with basic authentication, using `sys_updated_on` as timestamp field |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `topic-servicenow-incidents`.
2. Creates the fully managed `ServiceNowSourceV2` connector on table `incident`, starting from the current timestamp.
3. Creates an incident through the ServiceNow Table API.
4. Verifies the record with `playground topic consume --topic topic-servicenow-incidents`.
5. Asks whether to delete the connector.

## ServiceNow setup

### Register a test account

Go to the [ServiceNow developer portal](https://developer.servicenow.com) and register an account. Click on *Manage* -> *Instance* and request an instance. After some time on the waiting list (it can take about one hour), you receive an email with the details of your test instance.

### Verify user-level requirements

The `admin` user must have *Identity Type* set to *Machine*:

* Navigate to *User Administration* -> *Users*.
* Search for and open the `admin` record.
* Make sure *Identity Type* is set to *Machine*.
