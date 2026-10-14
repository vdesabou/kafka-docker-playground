# Fully Managed ServiceNow Source connector

## Objective

Quickly test the [ServiceNow Source](https://docs.confluent.io/cloud/current/connectors/cc-servicenow-source.html) fully managed connector.

This legacy connector is deprecated in Confluent Cloud: see [ServiceNow Source V2](../fm-servicenow-v2-source/README.md) for its replacement.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* A ServiceNow instance (see [ServiceNow setup](#servicenow-setup))

| Variable | Description |
| --- | --- |
| `SERVICENOW_URL` | ServiceNow instance URL, ending with `/` (e.g. `https://dev12345.service-now.com/`) |
| `SERVICENOW_PASSWORD` | Password of the ServiceNow `admin` user |

## How to run

```bash
playground run -f fully-managed-servicenow-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-servicenow-source.sh` | Reads table `incident` (JSON output) with basic authentication |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `topic-servicenow`.
2. Creates the fully managed `ServiceNowSource` connector on table `incident` with `servicenow.since` set to today.
3. Creates an incident through the ServiceNow Table API.
4. Verifies the record with `playground topic consume --topic topic-servicenow`.
5. Asks whether to delete the connector.

## ServiceNow setup

### Register a test account

Go to the [ServiceNow developer portal](https://developer.servicenow.com) and register an account. Click on *Manage* -> *Instance* and request an instance. After some time on the waiting list (it can take about one hour), you receive an email with the details of your test instance.

### Verify user-level requirements

The `admin` user must have *Identity Type* set to *Machine*:

* Navigate to *User Administration* -> *Users*.
* Search for and open the `admin` record.
* Make sure *Identity Type* is set to *Machine*.
