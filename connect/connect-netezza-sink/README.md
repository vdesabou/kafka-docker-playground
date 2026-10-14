# IBM Netezza sink connector

## Objective

Quickly test the [Netezza sink](https://github.com/confluentinc/kafka-connect-netezza) connector (`io.confluent.connect.netezza.NetezzaSinkConnector`) with an IBM Netezza (Netezza Performance Server / NPS) instance.

The connector plugin is [published on Confluent Hub](https://www.confluent.io/hub/confluentinc/kafka-connect-netezza) as `confluentinc/kafka-connect-netezza` and is installed automatically, like any other connector.

## Prerequisites

### A reachable Netezza instance

There is no Netezza docker image: this test runs against an **external, already-provisioned Netezza instance**. You need one of:

- an **NPS-as-a-Service** instance (IBM Cloud / AWS / Azure), or
- the **IBM Netezza Software Emulator** VM (VMware, free, for local runs).

Make sure the instance is reachable and that port `5480` is open to the machine running this test.

| Variable | Description |
| --- | --- |
| `NETEZZA_HOST` | Netezza host (required) |
| `NETEZZA_USER` | Netezza user (required) |
| `NETEZZA_PASSWORD` | Netezza password (required) |
| `NETEZZA_PORT` | Netezza port (optional, default `5480`) |
| `NETEZZA_DB` | Netezza database (optional, default `SYSTEMTEST`) |

### NPS Linux client tools

The Netezza JDBC driver (`nzjdbc3.jar`) and the native SQL client (`nzsql`) are not bundled with the Confluent Hub package, and IBM does not publish them at a public URL (the driver is not on Maven Central). Both come from the NPS Linux client tools `nps-linuxclient-v11.3.1.2.tar.gz`.

The script downloads the tarball from the Confluent S3 bucket with `get_3rdparty_file` (only works for **Confluent employees** with valid AWS credentials set). Otherwise, obtain it from your Netezza client tools distribution and copy it into the git-ignored `nzclient/` folder:

```text
connect/connect-netezza-sink/nzclient/nps-linuxclient-v11.3.1.2.tar.gz
```

With CP 8.x, the minimum supported connector version is 1.0.7 (the script exits with code 111 otherwise).

## How to run

```bash
export NETEZZA_HOST="<host>"
export NETEZZA_USER="<user>"
export NETEZZA_PASSWORD="<password>"
playground run -f netezza-sink.sh
```

## What the script does

1. Extracts the NPS client tools into `nzclient/` and copies `nzjdbc3.jar` into the `confluentinc-kafka-connect-netezza` plugin `lib` folder.
2. Starts the environment, and drops table `orders_<suffix>` if it exists (`<suffix>` is derived from the CP tag, so concurrent runs don't collide).
3. Produces one Avro record with a unique `product` value to topic `orders_<suffix>` with `playground topic produce`.
4. Creates the Netezza sink connector `netezza-sink` (`auto.create=true`).
5. Verifies with `nzsql` that the unique value is in table `orders_<suffix>`, then drops the table (cleanup).

`nzsql` is run by a helper (`run_nzsql`) in a throwaway `--platform=linux/amd64` `debian:bullseye-slim` container with the client mounted at `/opt/nz`.
