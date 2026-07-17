# IBM Netezza sink connector

## Objective

Quickly test the [Netezza sink](https://github.com/confluentinc/kafka-connect-netezza) connector (`io.confluent.connect.netezza.NetezzaSinkConnector`) with an IBM Netezza (Netezza Performance Server / NPS) instance.

## Important: there is no Netezza docker image

This test runs against an **external, already-provisioned Netezza instance**.

You need one of:

- an **NPS-as-a-Service** instance (IBM Cloud / AWS / Azure), or
- the **IBM Netezza Software Emulator** VM (VMware, free, for local runs).

Make sure the instance is reachable and that port `5480` is open to the machine running this test.

## Prerequisites

1. A reachable Netezza instance (see above).

2. The **connector plugin** is [published on Confluent Hub](https://www.confluent.io/hub/confluentinc/kafka-connect-netezza) as `confluentinc/kafka-connect-netezza`, so it is installed automatically (like any other connector) from the `CONNECT_PLUGIN_PATH` in `docker-compose.plaintext.yml`. No build step is required.

3. The **NPS Linux client tools** (`nps-linuxclient-v11.3.1.2.tar.gz`). Neither the **Netezza JDBC driver** (`nzjdbc3.jar`) nor the native SQL client (`nzsql`) is bundled with the Confluent Hub package, and IBM does **not** publish them at a public URL (the driver is not on Maven Central under `org.netezza` or `com.netezza`).

   For convenience the full client tarball is hosted on the Confluent S3 bucket, so the test script downloads it automatically via `get_3rdparty_file "nps-linuxclient-v11.3.1.2.tar.gz"` (this only works for **Confluent employees** with valid AWS credentials set. If it cannot be downloaded, obtain it from your Netezza client tools distribution and copy it into the git-ignored `nzclient/` folder as:

   ```
   connect/connect-netezza-sink/nzclient/nps-linuxclient-v11.3.1.2.tar.gz
   ```

4. Export the connection details as environment variables:

   ```bash
   export NETEZZA_HOST=<host>       # required
   export NETEZZA_USER=<user>       # required
   export NETEZZA_PASSWORD=<password> # required
   export NETEZZA_PORT=5480         # optional, defaults to 5480
   export NETEZZA_DB=SYSTEMTEST      # optional, defaults to SYSTEMTEST
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

Verify data is in Netezza 

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