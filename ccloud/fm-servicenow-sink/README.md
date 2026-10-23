# Fully Managed ServiceNow Sink connector

## Objective

Quickly test the [ServiceNow Sink](https://docs.confluent.io/cloud/current/connectors/cc-servicenow-sink.html) fully managed connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* A ServiceNow instance (see [ServiceNow setup](#servicenow-setup))
* The script creates the table `u_test_table` with fields `u_name` (string), `u_price` (floating point number) and `u_quantity` (integer) itself (see [The test table](#the-test-table))

| Variable | Description |
| --- | --- |
| `SERVICENOW_URL` | ServiceNow instance URL, ending with `/` (e.g. `https://dev12345.service-now.com/`) |
| `SERVICENOW_PASSWORD` | Password of the ServiceNow `admin` user |

## How to run

```bash
playground run -f fully-managed-servicenow-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-servicenow-sink.sh` | Writes Avro records to table `u_test_table` with basic authentication |

## What the script does

1. Creates the ServiceNow table `u_test_table` and its columns, if they do not exist yet.
2. Bootstraps the Confluent Cloud environment and recreates topic `test_table`.
3. Creates the fully managed `ServiceNowSink` connector writing to table `u_test_table` as user `admin`.
4. Produces 3 Avro records (`u_name`, `u_price`, `u_quantity`) to topic `test_table`.
5. Verifies 3 records in the `success-<connector id>` topic and checks the `error-<connector id>` topic.
6. Asks whether to delete the connector.

## ServiceNow setup

### Register a test account

Go to the [ServiceNow developer portal](https://developer.servicenow.com) and register an account. Click on *Manage* -> *Instance* and request an instance. After some time on the waiting list (it can take about one hour), you receive an email with the details of your test instance.

### Verify user-level requirements

The `admin` user must have *Identity Type* set to *Machine*. The script does it itself: when ServiceNow answers 401 to basic authentication as `admin`, it logs in through the UI login page (`login.do`) and sets `identity_type` to `machine` on `admin` with the REST Table API. To do it by hand instead:

* Navigate to *User Administration* -> *Users*.
* Search for and open the `admin` record.
* Make sure *Identity Type* is set to *Machine*.

### The test table

The script creates the table `u_test_table` and its columns with the ServiceNow REST Table API (records in `sys_db_object` and `sys_dictionary`), as user `admin`, without access controls. A table or column that already exists is left as is.

To create it by hand instead, search for *Tables* in the *All* menu and select the one from *System Definition*:

![create table](screenshot2.png)

Then click on *New* to create a new table `test_table` (ServiceNow names it `u_test_table`):

![create table](Screenshot1.jpg)

**Do not set ACL.**
