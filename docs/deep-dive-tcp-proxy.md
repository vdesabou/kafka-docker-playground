# 🍪 Deep dive: `playground tcp-proxy` (Zazkia)

The commands that slip a controllable TCP proxy, [emicklei/zazkia](https://github.com/emicklei/zazkia), between a
connector and the system it talks to (a database, an HTTP server, an MQ broker…), so you can slow down, break, cut or
close **one TCP connection at a time** and watch what the connector does: does it retry, does it lose records, does it
fail the task, does it reconnect on its own? Takes about 15 minutes to read and run.

> [!TIP]
> `tcp-proxy` complements [`debug block-traffic` and `debug degrade-traffic`](/deep-dive-network-traffic.md), which
> degrade the network of a whole container from the kernel. Section 2 compares them: in short, reach for `tcp-proxy`
> when you need to act on a **single connection**, in **one direction**, or to **close** it cleanly, and for the other
> two when the client config can't change or the target is a broker or a SaaS endpoint.

| You want | Command |
| --- | --- |
| put the proxy in front of `postgres:5432` and point the running connector to it | `playground tcp-proxy start --hostname postgres --port 5432` |
| the same, but you point the connector yourself (repro models) | `… start --hostname postgres --port 5432 --skip-automatic-connector-config`, then `zazkia:49998` in the config |
| every new connection slow, throttled, broken or corrupted from the start | `… start … --delay-service-response 5000` / `--throttle-service-response 1000` / `--break-service-response 10` / `--service-response-corrupt` |
| the live connections, their id, state and byte counters | `playground tcp-proxy get-connections` (`--connection-id N`) |
| add latency to the responses of the open connections | `playground tcp-proxy delay --delay-service-response 2000` (`0` to remove it) |
| break a percentage of the responses | `playground tcp-proxy break --break-service-response 100` (`0` to stop) |
| kill the connections, the way a firewall or a restarted database would | `playground tcp-proxy close-connection` (`--connection-id N`) |
| refuse new connections, keep the open ones | `playground tcp-proxy toggle-accept-connections` (run again to undo) |
| cut one direction of a connection | `playground tcp-proxy toggle-reads-client\|toggle-reads-service\|toggle-writes-client\|toggle-writes-service` |
| forget the connections that ended or failed | `playground tcp-proxy close-all-connection-with-error` |
| do all of the above with buttons | `playground tcp-proxy open-ui` (<http://localhost:9191>) |

---

## 1. Mental model (the 3 things to remember)

1. **It is a real proxy in the path, so the client must connect to `zazkia:49998`.** `start` adds a `zazkia`
   container (image `vdesabou/zazkia:latest`) to the running environment, with one route labelled `tcp-proxy`:
   it listens on port **49998** of the docker network and forwards every connection to `--hostname:--port`. Nothing
   changes until the client uses `zazkia:49998` instead of the real host: `start` rewrites the config of the running
   connectors for you (section 3), or you do it yourself. Port 49998 is not published on your machine: only containers
   can use the proxy. The admin REST API and the UI are on <http://localhost:9191>.
2. **Each TCP connection is a "link" with its own id and its own state.** A link copies the settings of the route
   when it opens (the `start` flags). `delay`, `break`, `close-connection` and the `toggle-*` commands change the
   **links open at that moment** (all of them without `--connection-id`), not the route. So a connection opened later,
   for instance when the connector reconnects after you closed its connection, comes back with the `start` settings:
   that is what lets the connector recover, and what you must take into account for clients that open a new
   connection per request (HTTP without keep-alive, connection pools that rotate).
3. **It acts on the byte stream, above TCP, and each direction separately.** Delay, break, throttle and corruption
   only apply to what goes **from the service back to the client** (the responses). The toggles stop the proxy from
   reading or writing one side, without closing anything, so the peer sees a connection that is open but silent.
   Corruption mangles bytes **inside** the stream, after TCP has checked them: the application gets garbage. That is
   the opposite of `degrade-traffic --corruption`, whose packets the TCP checksum drops.

What each command calls on the Zazkia admin API (from the scripts, with `curl` on `localhost:9191`):

| Command | Zazkia API | Prints |
| --- | --- | --- |
| `get-connections` | `GET /links/` | `{id, state, stats}` of each link, links ended by `EOF` hidden |
| `delay` | `POST /links/<id>/delay-response?ms=N` | the body, then `get-connections --connection-id <id>` |
| `break` | `POST /links/<id>/break-response?pct=N` | the body, then `get-connections --connection-id <id>` |
| `close-connection` | `POST /links/<id>/close` | the body (empty) |
| `toggle-reads-client` / `toggle-reads-service` / `toggle-writes-client` / `toggle-writes-service` | `POST /links/<id>/<toggle>` | the HTTP code (`200`, `404` for an unknown id) |
| `toggle-accept-connections` | `POST /routes/tcp-proxy/toggle-accept` | the new value, `true` or `false` |
| `close-all-connection-with-error` | `POST /links/closeAllWithError` | the HTTP code |

---

## 2. `tcp-proxy` vs `debug block-traffic` / `degrade-traffic`

| | `tcp-proxy` 🏚 | `block-traffic` 🚫 / `degrade-traffic` 🐌 |
| --- | --- | --- |
| Where it acts | a proxy container in the path, on the TCP byte stream | `iptables` / `tc netem` in the network namespace of the container (packets) |
| Client config | must point to `zazkia:49998` (rewritten by `start`, or by you) | unchanged |
| Targets | one `host:port`, one route at a time | any destination, IP, port, several containers at once |
| Granularity | each TCP connection (`--connection-id`), each direction | container → destination (`--port` optional), egress only |
| Outage | `close-connection` (the client gets the close right away), `toggle-accept-connections`, a silent direction with `toggle-*` | `block-traffic`: packets dropped, the client hangs until its own timeout |
| Slow | `delay` (ms per response), `--throttle-service-response` (bytes/s) | `--latency`, `--jitter`, `--rate` |
| Flaky | `break` (a % of responses) | `--loss` (TCP retransmits it) |
| Corruption | bytes mangled inside the stream, the application gets them | packets dropped by the TCP checksum, acts like loss |
| Kafka brokers, SaaS endpoints | ❌ (see gotchas) | ✅ |
| cfk | ❌ (needs the docker compose command of the environment) | ✅ |

Use them together: `degrade-traffic` to make the whole link slow, then `tcp-proxy close-connection` to kill the one
connection the connector uses, and see whether the reconnect works on the slow link.

Gotchas:

- **Kafka connections can't really go through it.** A Kafka client only uses its bootstrap address for the first
  metadata request, then connects to the advertised listeners of the brokers (`broker:9092`), which bypass the proxy.
  For connector ↔ broker problems, use `block-traffic` / `degrade-traffic` with `--destination broker`.
- **TLS works, hostname verification does not.** Zazkia forwards bytes, so a TLS session goes through it end to end,
  but the client now connects to `zazkia` while the certificate is for the real host: disable hostname verification in
  the client config, or use a certificate with `zazkia` as a SAN.
- **SaaS endpoints**: `--hostname` must be reachable from the `zazkia` container and the client must accept to talk to
  `zazkia:49998` (no SNI, no hostname check, no HTTP `Host` routing on the server side). Most SaaS APIs refuse that:
  use `block-traffic` / `degrade-traffic` instead.

---

## 3. `start`: putting the proxy in the path

```bash
# the connector is already running against postgres:5432
playground tcp-proxy start --hostname postgres --port 5432

# start "already broken": every connection gets 5 s of delay on each response
playground tcp-proxy start --hostname mysql --port 3306 --delay-service-response 5000

# repro model: start the proxy first, then create the connector with zazkia:49998
playground tcp-proxy start --hostname httpserver --port 9006 --skip-automatic-connector-config
```

What it does, in order:

1. Writes the route to `/tmp/zazkia/zazkia-routes.json` (label `tcp-proxy`, `listen-port` 49998, the transport
   settings from the flags, `verbose` on), and a compose override `/tmp/docker-compose.override.zazkia.yml` that adds
   the `zazkia` service (ports `9191:9191`, the folder mounted on `/data`).
2. Replays the docker compose command of the environment (`playground state get run.docker_command`) with that
   override added, keeping the `TAG`, connect tag and Oracle image of the running containers, then waits for connect:

   ```text
   💫 adding container zazkia listening on port 49998
   💗 you can now use zazkia tcp proxy using <zazkia:49998>
   🌐 zazkia UI is available on http://localhost:9191
   ```

   It opens the UI in your browser when an `open` command exists.
3. Unless `--skip-automatic-connector-config` is set, for **each running connector**, takes the output of
   `playground connector show-config`, and replaces textually: `<hostname>:<port>` by `zazkia:49998`, a value
   `"<hostname>"` by `"zazkia"`, and any other `<port>` by `49998`. If something changed, it prints the new
   `create-or-update` command, asks `Continue (y/n)?` and runs it:

   ```text
   🔮 checking existence of hostname postgres and port 5432 in connector postgres-source configuration to replace with zazkia and port 49998
   replacing postgres:5432 by zazkia:49998
   💫 updating connector postgres-source configuration with
   playground connector create-or-update --connector postgres-source << 'EOF'
   …
     "connection.url": "jdbc:postgresql://zazkia:49998/postgres?user=myuser&password=mypassword&ssl=false",
   …
   ```

   It handles both a URL (`jdbc:postgresql://postgres:5432/…`, `http://httpserver:9006/…`) and separate keys
   (`"database.hostname": "postgres"` + `"database.port": "5432"`, as Debezium has).

Gotchas:

- **The connector must be running before `start`** for the automatic rewrite. Otherwise:
  `💤 No connector is running, skipping automatic update of connector configuration with tcp proxy`. When nothing
  matches: `💅 could not replace automatically hostname <h> and port <p> in connector <c> configuration, please do it manually !`.
- **The rewrite is a plain `sed`.** The port is replaced **everywhere** it appears in the config, also inside other
  values: with `--port 80`, an `http://schema-registry:8081` would become `http://schema-registry:4999881`. Read the
  printed config before answering `y`, or use `--skip-automatic-connector-config` and write `zazkia:49998` yourself.
- **`Continue (y/n)?` needs an answer**, except in CI (`GITHUB_RUN_NUMBER` set). In a reproduction script, prefer
  `--skip-automatic-connector-config` and create the connector with `zazkia:49998` (what the repro models do), or
  feed it: `playground tcp-proxy start … <<< "y"`.
- **One route at a time.** Running `start` again rewrites the route and recreates the `zazkia` container: every
  link is dropped and the previous `--hostname` is no longer proxied. Only one service can go through the proxy at a
  time.
- **`--throttle-service-response` and `--service-response-corrupt` only exist on `start`**: there is no command to
  change them on open connections. Restart the proxy with other values (which drops the connections).
- **Not for cfk or Confluent Cloud**: `start` needs the docker compose command stored by `start-environment`
  (`docker_command retrieved from …/playground.ini is empty !` otherwise).

---

## 4. Acting on the open connections

```bash
playground tcp-proxy get-connections                       # ids, state, byte counters
playground tcp-proxy delay --delay-service-response 2000   # slow responses on every open connection
playground tcp-proxy delay --delay-service-response 0      # back to normal
playground tcp-proxy break --break-service-response 100 --connection-id 3   # break one connection only
playground tcp-proxy close-connection                      # kill them all
playground tcp-proxy toggle-accept-connections             # false: new connections refused; again: true
playground tcp-proxy toggle-reads-service                  # nothing comes back from the service; again to restore
playground tcp-proxy close-all-connection-with-error       # forget the links that ended or failed
```

`get-connections` prints one JSON object per link (fields from the Zazkia API, values vary):

```json
{
  "id": 3,
  "state": {
    "verbose": true,
    "throttle-service-response": 0,
    "delay-service-response": 0,
    "break-service-response": 0,
    "sending-to-client": true,
    "receiving-from-client": true,
    "sending-to-service": true,
    "receiving-from-service": true,
    "service-response-corrupt-method": "",
    "accept-connections": true
  },
  "stats": {
    "bytesSentToService": 1234,
    "bytesSentToClient": 5678,
    "bytesReceivedFromClient": 1234,
    "bytesReceivedFromService": 5678
  }
}
```

The four toggles, from the point of view of the connector (the client) and of the system it talks to (the service):

| Toggle (off) | The proxy stops… | What the connector sees |
| --- | --- | --- |
| `toggle-reads-client` | reading what the connector sends | its writes pile up in the socket buffer, then block: backpressure, produce / send timeouts |
| `toggle-writes-service` | forwarding the requests to the service | the request is "sent", nothing ever answers |
| `toggle-reads-service` | reading the responses of the service | requests hang until a client timeout, the connection stays open (the classic black hole) |
| `toggle-writes-client` | forwarding the responses to the connector | same as above for the connector, but the service considers its response delivered: both sides disagree |

Gotchas:

- **Without `--connection-id`, every command applies to all the active links** (and prints
  `🧲 --connection-id flag was not provided, applying command to all active Zazkia TCP connections` when there are
  several). The connector and its tasks often have one connection each: target one id to break only a task.
- **New connections don't inherit runtime changes** (mental model, point 2): after `close-connection`, the
  reconnection is healthy again unless the delay or break was set with `start`.
- **`delay` and `break` are toggles in Zazkia**: when the link already has a non-zero delay (or break), the call
  resets it to 0 whatever value you pass. So `delay … 0` removes it, but going from 500 to 2000 ms takes two calls
  (one resets, one sets). Both commands print the new state of the link afterwards: check
  `"delay-service-response"` / `"break-service-response"` there.
- **`break` does not close the connection**: the response that hits it is dropped and that direction of the link
  stops (the link gets a `serviceReceiveError`), while the client socket stays open. A client without a read timeout
  (a JDBC driver with no `socketTimeout`) hangs; follow with `close-connection` to see the reconnect.
- **`toggle-accept-connections` is for the route, not a link**, and the open connections keep working. The
  operating system still completes the TCP handshake of new clients while Zazkia stops accepting, so they don't get
  `Connection refused`: they connect, then wait for a reply that never comes (or get closed right away if they
  were accepted at the moment of the switch).
- **Links that ended stay in Zazkia**: `get-connections` and the "all links" commands skip the ones ended by `EOF`,
  but those failed in another way (a break, a reset) are still listed. `close-all-connection-with-error` removes
  every link with an error, `EOF` included.
- **`get-connections` before `start`** (or after `playground stop`) fails with
  `❌ curl request failed with error code 7!`: no proxy listens on `localhost:9191`. The other commands say
  `❌ No active Zazkia TCP connection found, make sure that Zazkia is being used!` when the proxy runs but nothing
  goes through it: the connector still uses the real host.
- **Zazkia logs every link** (verbose route): `playground container logs -c zazkia --no-follow --tail 100` shows when
  each connection was opened, ended, and with which error.

---

## 5. Hands-on lab (≈10 min)

A JDBC source connector keeps one connection open to PostgreSQL and queries it every 5 seconds, which makes the effect
of each command easy to see. No credentials needed:

```bash
cd connect/connect-jdbc-postgresql-source
playground run -f postgres.sh     # postgres + connector postgres-source, records in postgres-customers
```

**Step 1: before start, there is no proxy to talk to**

```bash
playground tcp-proxy get-connections
# ❌ curl request failed with error code 7!
```

**Step 2: put the proxy between the connector and postgres**

```bash
playground tcp-proxy start --hostname postgres --port 5432
# 💫 adding container zazkia listening on port 49998
# 💗 you can now use zazkia tcp proxy using <zazkia:49998>
# 🌐 zazkia UI is available on http://localhost:9191
# 🔮 checking existence of hostname postgres and port 5432 in connector postgres-source configuration to replace with zazkia and port 49998
# replacing postgres:5432 by zazkia:49998
# 💫 updating connector postgres-source configuration with
# …   "connection.url": "jdbc:postgresql://zazkia:49998/postgres?user=myuser&password=mypassword&ssl=false",
# Continue (y/n)?y
playground connector show-config --connector postgres-source --force-rest-endpoint
# … "connection.url": "jdbc:postgresql://zazkia:49998/postgres?…"    <- the running config uses the proxy
```

**Step 3: the connections going through the proxy**

```bash
playground tcp-proxy get-connections
# {
#   "id": <id>,
#   "state": {
#     …
#     "delay-service-response": 0,
#     …
#     "receiving-from-service": true,
#     …
#   },
#   "stats": {
#     "bytesSentToService": …,
#     …
#     "bytesReceivedFromService": …
#   }
# }
```

Run it twice: the byte counters grow every 5 seconds (`poll.interval.ms`). You may see more than one link: the
connector and its task each have their own connection.

**Step 4: a slow database**

```bash
playground tcp-proxy delay --delay-service-response 2000
# ⏲️ Add 2000 milliseconds delay to service response for connection id <id>
#     "delay-service-response": 2000,
#                                     <- each query of the connector now waits 2 s for its answer
playground tcp-proxy delay --delay-service-response 0
#     "delay-service-response": 0,
```

**Step 5: break the responses, then kill the connections**

```bash
playground tcp-proxy break --break-service-response 100
# 💔 Break sending the response to the client for 100 % for connection id <id>
#     "break-service-response": 100,
#                                     <- the next query never gets its answer: the task hangs, no error yet
playground tcp-proxy close-connection
# ❌ closing connection id <id>
playground container logs -c connect --errors --since 2m      # the I/O error of the PostgreSQL driver
playground tcp-proxy get-connections
#   "id": <new id>,                   <- the connector reconnected by itself
#     "break-service-response": 0,    <- with the settings of the route, not the break
playground connector wait --connector postgres-source         # still RUNNING
```

This is the question most support cases ask: **does the connector recover on its own once the connection is gone,
and how long does it take?**

**Step 6: refuse new connections, then accept them again**

```bash
playground tcp-proxy toggle-accept-connections
# 🙅‍♂️ Change whether new connections can be accepted
# false
playground tcp-proxy toggle-accept-connections
# true
```

In between, the open connections keep working: run `close-connection` while it is `false` to see how the connector
behaves when it can't reconnect.

**Step 7: a black hole in one direction**

```bash
playground tcp-proxy toggle-reads-service
# ✅ toggle-reads-service for connection id <id>
# 200
playground tcp-proxy get-connections
#     "receiving-from-service": false,
playground tcp-proxy toggle-reads-service                     # restore the flow
# 200
```

**Step 8: clean up and the UI**

```bash
playground tcp-proxy close-all-connection-with-error
# 🧹 Close all Zazkia TCP connections which are in error state
# 200
playground tcp-proxy open-ui
# 🧲 Open Zazkia UI
playground stop
```

---

## 6. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "the connector never recovers after a database failover / restart" | `tcp-proxy close-connection`, then `playground connector wait --connector <c> --max-wait 120` and `container logs -c connect --errors` |
| "the task hangs forever, no error" (no socket / read timeout) | `tcp-proxy toggle-reads-service` or `tcp-proxy break --break-service-response 100`, then `playground analyze thread-dump -c connect` |
| "the database is slow, the query times out" | `tcp-proxy delay --delay-service-response 30000` (or `start … --delay-service-response` to hit the reconnections too) |
| "a slow API: the HTTP sink retries, records arrive late" | `tcp-proxy start --hostname httpserver --port 9006 --throttle-service-response 1000` |
| "intermittent `Connection reset` / `Broken pipe`" | `tcp-proxy break --break-service-response 10`, then `close-all-connection-with-error` between runs |
| "the connector can't reconnect after a failure, pool exhausted" | `tcp-proxy toggle-accept-connections` (`false`), `tcp-proxy close-connection`, wait, `toggle-accept-connections` again |
| "garbage / protocol errors from the server" | `tcp-proxy start … --service-response-corrupt` |
| "only one task fails" | `tcp-proxy get-connections`, then any command with `--connection-id <id>` |

In a repro model, start the proxy before the connector and point it to `zazkia:49998` yourself, which needs no
prompt, then wait for the state instead of `sleep`:

```bash
playground tcp-proxy start --hostname postgres --port 5432 --skip-automatic-connector-config

playground connector create-or-update --connector postgres-source << EOF
{
     "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
     "connection.url": "jdbc:postgresql://zazkia:49998/postgres?user=myuser&password=mypassword&ssl=false",
     …
}
EOF

playground tcp-proxy close-connection
# 🎯 expected: the task reconnects by itself. 💥 actual: it fails
playground connector wait --connector postgres-source --state FAILED --max-wait 120 || true
playground repro assert --reproduced-if-connector-state FAILED
```

---

## 7. Cheat sheet

```bash
playground tcp-proxy start --hostname <h> --port <p> [--delay-service-response <ms>] [--break-service-response <%>] \
  [--throttle-service-response <bytes/s>] [--service-response-corrupt] [--skip-automatic-connector-config]
playground tcp-proxy get-connections [--connection-id N]
playground tcp-proxy delay --delay-service-response <ms> [--connection-id N]     # 0 removes it
playground tcp-proxy break --break-service-response <%> [--connection-id N]      # 0 stops it
playground tcp-proxy close-connection [--connection-id N]
playground tcp-proxy toggle-reads-client|toggle-reads-service|toggle-writes-client|toggle-writes-service [--connection-id N]
playground tcp-proxy toggle-accept-connections
playground tcp-proxy close-all-connection-with-error
playground tcp-proxy open-ui
```

- The client must use `zazkia:49998` (from containers only). `start` rewrites the running connectors, textually.
- One route (`tcp-proxy`) at a time, admin API and UI on `localhost:9191`.
- `start` flags = defaults of every new connection. Other commands = the connections open now, all of them without
  `--connection-id`.
- Delay, break, throttle, corruption: service → client direction only. Toggles: one direction, connection left open.
- Not for broker connections, SaaS endpoints with TLS hostname checks, or cfk: use `debug block-traffic` /
  `degrade-traffic`.
- Sources: [`commands/tcp-proxy/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/tcp-proxy)
  ([`start.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/tcp-proxy/start.sh),
  [`get-connections.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/tcp-proxy/get-connections.sh)),
  helper `get_zazkia_id_list` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh),
  Zazkia [README](https://github.com/emicklei/zazkia#how-does-it-work-) (diagram of the directions, also on
  <http://localhost:9191/help.html>).

---

**Links**

- 📖 [Simulate TCP connections problems](/toolkit-network?id=🏚-simulate-tcp-connections-problems) in the Reproduction
  toolkit
- 👉 Example: [`connect/connect-jdbc-postgresql-source`](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-jdbc-postgresql-source)
  (the lab), [`other/cli/debug-and-perf-http-sink.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cli/debug-and-perf-http-sink.sh)
  (an HTTP sink, `--throttle-service-response`)
- 🍪 Deep dives: [`debug block-traffic` and `debug degrade-traffic`](/deep-dive-network-traffic.md) for the network of a
  whole container, [`connector diagnose` and the dead letter queue](/deep-dive-connector-troubleshooting.md) for what
  the connector did with the failure, [JVM diagnostics](/deep-dive-jvm-diagnostics.md) for a task that hangs,
  [reproduction models](/deep-dive-reproduction-models.md) to turn the scenario into a repro with `repro assert`
- 🧠 CLI reference: [playground tcp-proxy start](/playground%20tcp-proxy%20start),
  [playground tcp-proxy get-connections](/playground%20tcp-proxy%20get-connections),
  [playground tcp-proxy delay](/playground%20tcp-proxy%20delay), [playground tcp-proxy break](/playground%20tcp-proxy%20break),
  [playground tcp-proxy close-connection](/playground%20tcp-proxy%20close-connection),
  [playground tcp-proxy toggle-accept-connections](/playground%20tcp-proxy%20toggle-accept-connections),
  [playground tcp-proxy toggle-reads-service](/playground%20tcp-proxy%20toggle-reads-service),
  [playground tcp-proxy close-all-connection-with-error](/playground%20tcp-proxy%20close-all-connection-with-error),
  [playground tcp-proxy open-ui](/playground%20tcp-proxy%20open-ui)
