# ServiceNow Sink connector

## Objective

Quickly test the [ServiceNow Sink](https://docs.confluent.io/kafka-connectors/servicenow/current/sink-connector/overview.html) connector.

## Prerequisites

* A ServiceNow test instance (see [Register a test account](#register-a-test-account)) with a `test_table` table (see [Create the test_table](#create-the-test_table-in-servicenow)).
* With CP 8.x, connector version 2.5.6 or later.

| Variable | Description |
| --- | --- |
| `SERVICENOW_URL` | ServiceNow instance URL, ending with `/` (e.g. `https://dev12345.service-now.com/`) |
| `SERVICENOW_PASSWORD` | Password of the ServiceNow `admin` user |

## How to run

```bash
export SERVICENOW_URL="https://dev12345.service-now.com/"
export SERVICENOW_PASSWORD="<admin password>"
playground run -f servicenow-sink.sh
```

| Script | Description |
| --- | --- |
| `servicenow-sink.sh` | Basic example |
| `servicenow-sink-proxy.sh` | Same, through an nginx forward proxy (`proxy.url=nginx-proxy:8888`) |

## What the script does

1. Produces 3 Avro records (`u_name`, `u_price`, `u_quantity`) to topic `test_table`.
2. Creates the ServiceNow Sink connector writing to table `u_test_table` as user `admin`, with reporter topics `test-result` and `test-error`.
3. Verifies 3 records in `test-result` with `playground topic consume`.
4. Queries `${SERVICENOW_URL}/api/now/table/u_test_table` with the ServiceNow REST API and checks the records are there.

## Register a test account

Go to [ServiceNow developer portal](https://developer.servicenow.com) and register an account.
Click on *Manage* -> *Instance* and register for an instance. After some time on the waiting list (about one hour), you should receive an email with the details of your test instance.

## Verify user-level requirements

The user account should have *Identity Type* set to `Machine`:

* Navigate to *User Administration* > *Users*.
* Search for and open the admin record.
* Make sure *Identity Type* is set to `Machine`.

## Create the test_table in ServiceNow

Search for *Tables* in the *All* menu and select the one from *System Definition*:

![create table](screenshot2.png)

Then click on the *New* button to create a new table:

![create table](Screenshot1.jpg)

**Do not set ACL.**
