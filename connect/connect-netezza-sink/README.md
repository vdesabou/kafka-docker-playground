# IBM Netezza sink connector

## Objective

Quickly test the [Netezza sink](https://github.com/confluentinc/kafka-connect-netezza) connector (`io.confluent.connect.netezza.NetezzaSinkConnector`) with an IBM Netezza (Netezza Performance Server / NPS) instance.

## Important: there is no Netezza docker image

Unlike most examples in this repo, Netezza **cannot** be run in a container — IBM does not publish a Netezza server image. This test therefore runs against an **external, already-provisioned Netezza instance**.

You need one of:

- an **NPS-as-a-Service** instance (IBM Cloud / AWS / Azure), or
- the **IBM Netezza Software Emulator** VM (VMware, free, for local runs).

Make sure the instance is reachable and that port `5480` is open to the machine running this test.

## Prerequisites

1. A reachable Netezza instance (see above).

2. The **connector plugin** is [published on Confluent Hub](https://www.confluent.io/hub/confluentinc/kafka-connect-netezza) as `confluentinc/kafka-connect-netezza`, so it is installed automatically (like any other connector) from the `CONNECT_PLUGIN_PATH` in `docker-compose.plaintext.yml`. No build step is required.

3. The **NPS Linux client tools** (`nps-linuxclient-v11.3.1.2.tar.gz`). Neither the **Netezza JDBC driver** (`nzjdbc3.jar`) nor the native SQL client (`nzsql`) is bundled with the Confluent Hub package, and IBM does **not** publish them at a public URL (the driver is not on Maven Central under `org.netezza` or `com.netezza`). Per [IBM's docs](https://www.ibm.com/docs/en/netezza?topic=jdbc-installing-driver-unix-linux), both ship with the **NPS Linux client tools**.

   For convenience the full client tarball is hosted on the Confluent S3 bucket, so the test script downloads it automatically via `get_3rdparty_file "nps-linuxclient-v11.3.1.2.tar.gz"` (this only works for **Confluent employees** with valid AWS credentials set — the same mechanism used for the other proprietary drivers in this repo, e.g. the Oracle instant client). If it cannot be downloaded, obtain it from your Netezza client tools distribution and copy it into this folder as `nps-linuxclient-v11.3.1.2.tar.gz` (it is git-ignored):

   ```
   connect/connect-netezza-sink/nps-linuxclient-v11.3.1.2.tar.gz
   ```

   The tarball is an installer bundle, so the script unpacks it twice inside the git-ignored `nzclient/` folder — first the bundle, then the nested client tarball (`linux64/npsclient.11.3.1.2.tar.gz`) into `nzclient/npsclient/` — and uses two things from the result:
   - **`nzjdbc3.jar`** — copied into the connector's plugin `lib` directory (`../../confluent-hub/confluentinc-kafka-connect-netezza/lib`, mounted into the connect container at `/usr/share/confluent-hub-components`) **before** starting the connect worker, so it is on the classpath when the connector is created.
   - **`nzsql`** — the native SQL client used to reset and read the target table. `nzsql` is a Linux **x86_64** binary, so (since the connect container is arm64 on Apple Silicon and can't execute it) the script runs the downloaded `nzsql` in a separate throwaway `--platform=linux/amd64` container, with the `nzclient/` tree mounted at `/opt/nz`. The base image is `debian:bullseye-slim` because `nzsql` needs `libnsl.so.2` (provided by debian but not by the connect image). This is the same pattern `connect-azure-functions-sink` uses to run a tool in an amd64 base-image container.

   The test script exits with a clear message if the tarball cannot be found, or if `nzjdbc3.jar` / `nzsql` are not present in the extracted tree.

4. Export the connection details as environment variables:

   ```bash
   export NETEZZA_HOST=<host>       # required
   export NETEZZA_USER=<user>       # required
   export NETEZZA_PASSWORD=<password> # required
   export NETEZZA_PORT=5480         # optional, defaults to 5480
   export NETEZZA_DB=SYSTEMTEST      # optional, defaults to SYSTEMTEST (cannot be the SYSTEM database, which does not allow user tables)
   ```

## How to run

Simply run:

```
$ just use <playground run> command and search for netezza-sink.sh in this folder
```

## Details of what the script is doing

The `NetezzaSinkConnector` connects to Netezza over the `nzjdbc3.jar` driver copied into its plugin `lib` directory. The native `nzsql` client (from the same NPS client tools) is used to reset and read the target table, run via a helper (`run_nzsql`) that executes it in a throwaway `--platform=linux/amd64` `debian:bullseye-slim` container with the client mounted at `/opt/nz`.

Sending messages to topic `orders`:

```bash
$ playground topic produce -t orders --nb-messages 1 --forced-value '{"id":2,"product":"foo","quantity":2,"price":0.86583304}'
```

Creating the Netezza sink connector:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.netezza.NetezzaSinkConnector",
               "tasks.max": "1",
               "connection.host": "<host>",
               "connection.port": "5480",
               "connection.database": "SYSTEMTEST",
               "connection.user": "<user>",
               "connection.password": "<password>",
               "topics": "orders",
               "auto.create": "true"
          }' \
     http://localhost:8083/connectors/netezza-sink/config | jq .
```

> The connector does not set `confluent.topic.bootstrap.servers` / `confluent.topic.replication.factor` — the connect worker provides these at the worker level (`CONNECT_CONFLUENT_TOPIC_BOOTSTRAP_SERVERS`), so the connector inherits them.

Verify data is in Netezza (the `grep "foo"` is the test assertion — it fails the run if the row did not land), then drop the table again as cleanup. `nzsql` is run through the `run_nzsql` helper (a `--platform=linux/amd64` `debian:bullseye-slim` container with the client mounted at `/opt/nz`):

```bash
run_nzsql > /tmp/result.log 2>&1 << EOF
SELECT * FROM orders;
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log

run_nzsql << EOF
DROP TABLE orders;
EOF
```

## Notes

- Both the connect container (the connector) and the `nzsql` helper container need network reachability to `NETEZZA_HOST:NETEZZA_PORT`. If your Netezza instance is only reachable from the Docker host (e.g. an emulator on `localhost`), use `host.docker.internal` (or the host IP) as `NETEZZA_HOST`.
- `NETEZZA_DB` must be an existing database that allows user tables — it cannot be `SYSTEM`. If the connector reports `FATAL 1: database connection refused`, the target database likely does not exist or the user lacks CONNECT rights; create it first (e.g. `run_nzsql -c "CREATE DATABASE SYSTEMTEST"` against an existing DB).
- Because this test depends on an external, manually-provisioned instance, it is intended to be run on demand and is not part of the automated CI matrix.
- N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021)
