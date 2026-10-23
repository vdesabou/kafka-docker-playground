# ServiceNow Source connector

## Objective

Quickly test the [ServiceNow Source](https://docs.confluent.io/kafka-connectors/servicenow/current/source-connector/overview.html) connector.

## Prerequisites

* A ServiceNow test instance (see [Register a test account](#register-a-test-account)).
* With CP 8.x, connector version 2.5.6 or later.

| Variable | Description |
| --- | --- |
| `SERVICENOW_URL` | ServiceNow instance URL, ending with `/` (e.g. `https://dev12345.service-now.com/`) |
| `SERVICENOW_PASSWORD` | Password of the ServiceNow `admin` user |

## How to run

```bash
export SERVICENOW_URL="https://dev12345.service-now.com/"
export SERVICENOW_PASSWORD="<admin password>"
playground run -f servicenow-source.sh
```

| Script | Description |
| --- | --- |
| `servicenow-source.sh` | Basic example |
| `servicenow-source-proxy.sh` | Same, through an nginx forward proxy (`proxy.url=nginx-proxy:8888`, `retry.max.times=3`); the proxy is checked with curl first, and the incident is created through the proxy |

## What the script does

1. Creates the ServiceNow Source connector on table `incident` as user `admin` (`servicenow.since` set to today), writing to topic `topic-servicenow` (JSON converter).
2. Creates one incident (`"short_description": "This is test"`) with the ServiceNow REST API (`/api/now/table/incident`).
3. Verifies the record is received with `playground topic consume --topic topic-servicenow`.

## Register a test account

Go to [ServiceNow developer portal](https://developer.servicenow.com) and register an account.
Click on *Manage* -> *Instance* and register for an instance. After some time on the waiting list (about one hour), you should receive an email with the details of your test instance.

## Verify user-level requirements

The user account should have *Identity Type* set to `Machine`. The scripts do it themselves: when ServiceNow answers 401 to basic authentication as `admin`, they log in through the UI login page (`login.do`) and set `identity_type` to `machine` on `admin` with the REST Table API. To do it by hand instead:

* Navigate to *User Administration* > *Users*.
* Search for and open the admin record.
* Make sure *Identity Type* is set to `Machine`.
