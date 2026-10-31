# 🍪 Deep dive: debugging the JVM (remote debugger, SSL / Kerberos / class loading traces, testssl, diagnostics bundle)

The commands for "I need a breakpoint", "the TLS handshake fails", "the Kerberos login is refused", "which jar did this
class come from?" and "support wants a diagnostics bundle": `playground debug enable-remote-debugging` attaches your IDE
(or `jdb`) to a container, `playground debug java-debug` turns on the JVM's own traces, `playground debug testssl` probes
a TLS endpoint from the outside, and `playground debug generate-diagnostics` runs the Confluent Diagnostics Bundle Tool.
Thread dumps, heap dumps, GC logs, flight recordings, jscissors and tcp dumps are in the
[JVM diagnostics](/deep-dive-jvm-diagnostics.md) deep dive: this page is about the four others, what they do to the
container (most of them recreate it) and how to read what they print. Takes about 10 minutes to read and run.

> [!TIP]
> 🎬 Short on time? The video session
> [🐞 A breakpoint in a running connector: remote debugging](/sessions?id=🐞-a-breakpoint-in-a-running-connector-remote-debugging)
> shows `jdb` and Visual Studio Code attached to `localhost:5005`, with a breakpoint in a JDBC sink task. This page goes
> further: the containers other than `connect`, what the commands change under the hood, the JVM traces, a hands-on
> lab and recipes for support repros.

| You want | Command |
| --- | --- |
| a breakpoint in a connector | nothing to enable: attach to `localhost:5005` (`connect2`: `5205`, `connect3`: `5305`) |
| the connector code at the version that runs, compiled, open in the editor | `playground connector enable-remote-debugging` (interactive) or `playground connector-plugin sourcecode -c <owner/name> --connector-tag <v> --checkout-only` |
| a debugger on the broker, Schema Registry, ksqlDB… | `playground debug enable-remote-debugging -c broker` (repeat `-c`) |
| back to the original definition | `playground debug disable-remote-debugging -c broker` |
| why the TLS handshake fails | `playground debug java-debug -c <c> --type ssl_handshake` (`ssl_all` for everything) |
| why the Kerberos login is refused | `playground debug java-debug -c <c> --type kerberos` |
| which jar a class is loaded from (`ClassNotFoundException`, `NoSuchMethodError`) | `playground debug java-debug -c connect --type class_loading` |
| the traces off again | `playground debug java-debug -c <c> --type <type> --action disable` |
| the protocols, ciphers and certificate of a TLS endpoint | `playground debug testssl --uri <host:port>` |
| a Diagnostics Bundle Tool zip for support | `playground debug generate-diagnostics -c connect` (or `-c broker`) |

---

## 1. Mental model (the 3 things to remember)

1. **`connect` always listens for a debugger; the other containers need `enable-remote-debugging`.** The `connect`
   service of every environment (they all start from `environment/plaintext/docker-compose.yml`) sets
   `KAFKA_DEBUG: 'true'` and `JAVA_DEBUG_OPTS: '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=0.0.0.0:5005'`,
   and publishes port `5005` (`connect2` on `5205`, `connect3` on `5305`). `kafka-run-class`, the launcher of every CP
   JVM, sees a non-empty `KAFKA_DEBUG` and puts `JAVA_DEBUG_OPTS` in front of `KAFKA_OPTS`. `enable-remote-debugging`
   sets the same two variables on another container; on a `connect*` container that already has `KAFKA_DEBUG` it does
   nothing: `💫 remote debugging is already enabled for connect container connect (KAFKA_DEBUG in the base compose)`.
   `disable-remote-debugging -c connect` sets `KAFKA_DEBUG` to an empty value, which switches JDWP off.

2. **Everything except `testssl` recreates the container.** `enable-remote-debugging`, `disable-remote-debugging` and
   `java-debug` are `playground container set-environment-variables`: a temporary compose override with the variables
   and a random `DUMMY` value, then `run.docker_command` replayed with it, so the container is **recreated** (not
   restarted), and the command waits until Connect is ready again. Consequences:

   | | Effect |
   | --- | --- |
   | one override at a time | each call writes a new override with **only its own variables**: `java-debug` after `enable-remote-debugging -c broker` loses the debugger on `broker` |
   | `disable` = restore everything | `disable-remote-debugging` and `java-debug --action disable` both replay the original command: every variable set by any of these commands goes, not only the one you name |
   | recreate = a new container | files copied in, `degrade-traffic` rules, a JDK installed by `change-jdk` are gone; connectors survive (they live in Kafka topics) |

   `generate-diagnostics` doesn't recreate anything, but it downloads and runs a jar **inside** the container.

3. **`java-debug` adds its option to the `KAFKA_OPTS` of the container.** The four types are one JVM option each,
   appended to what the environment already has (`☕ KAFKA_OPTS of connect: -Ddynamic.worker.config.file=/dev/null -verbose:class`):

   | `--type` | `KAFKA_OPTS` | What you read in the container logs |
   | --- | --- | --- |
   | `ssl_handshake` | `-Djavax.net.debug=ssl:handshake` | each handshake message, the certificates, the alert |
   | `ssl_all` | `-Djavax.net.debug=all` | the same plus every record, the key material and the trust manager: huge |
   | `kerberos` | `-Dsun.security.krb5.debug=true` | `krb5.conf` read, KDC requests and errors, the keytab entries |
   | `class_loading` | `-verbose:class` | one line per class loaded, with the jar it came from |

   So `-Ddynamic.worker.config.file=/dev/null` on `connect`, and **the JAAS file of the brokers**
   (`-Djava.security.auth.login.config=…`) in the `sasl-plain`, `sasl-scram`, `sasl-ssl`, `kerberos` and
   `ssl_kerberos` environments, stay. An option already there isn't added twice. The JDWP agent is not affected: it
   comes from `JAVA_DEBUG_OPTS`.

---

## 2. Remote debugging: `enable-remote-debugging`, `disable-remote-debugging`

```bash
# connect: already on, port 5005 on your machine
jdb -attach localhost:5005

# another container (several -c at once): recreated with KAFKA_DEBUG + JAVA_DEBUG_OPTS, prints the VS Code entry
playground debug enable-remote-debugging -c broker
playground debug enable-remote-debugging -c schema-registry -c ksqldb-server --skip-vs-code-config-display

# back to the original definition
playground debug disable-remote-debugging -c broker
```

What `enable-remote-debugging -c broker` prints:

```text
✨ enable remote debugging for broker
📦 enabling containers broker with environment variables KAFKA_DEBUG: 'true' JAVA_DEBUG_OPTS: '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=0.0.0.0:5005'
⌛ Waiting up to 300 seconds for connect to start
🚦 containers have started! (took … seconds)
If you use Visual Studio Code:
Edit .vscode/launch.json with
        {
            "version": "0.2.0",
            "configurations": [
                {
                    "type": "java",
                    …
                    "hostName": "127.0.0.1",
                    "port": 5005,
                    "timeout": 30000
                }
            ]
        }
see https://kafka-docker-playground.io/#/toolkit-debugging?id=✨-remote-debugging
```

And in the logs of the container, the lines of `kafka-run-class` and of the JDWP agent:

```text
Enabling Java debug options: -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=0.0.0.0:5005
Listening for transport dt_socket at address: 5005
```

For the connector code itself, `playground connector enable-remote-debugging` (no flag) clones the source of the
running connector at its version into `/tmp/connector-plugin-sourcecode/<repo>-<version>`, adds a `.vscode/launch.json`
that attaches to `127.0.0.1:5005`, compiles it with Maven in Docker, opens the folder in your editor
(`playground config get editor`), and ends with
`✨ now you can set breakpoints and use Hot Code Replace feature …`. It's interactive and needs `git`; Confluent
connectors with private dependencies need the Confluent VPN and AWS credentials; it doesn't work for fully managed or
custom connectors. `playground connector disable-remote-debugging` is `debug disable-remote-debugging -c connect`.
From a script or an agent, use `playground connector-plugin sourcecode … --checkout-only` and attach by hand (the
🐞 session).

Gotchas:

- **Only the `connect` ports are published.** `enable-remote-debugging -c broker` opens JDWP on `broker:5005` inside the
  Docker network, but `localhost:5005` on your machine is still `connect`. To attach from your IDE, publish another
  host port in the compose override of the example (`ports: ["5006:5005"]` on the service), as the
  [toolkit](/toolkit-debugging?id=✨-remote-debugging) shows for `control-center`.
- **The variables only work for JVMs started by `kafka-run-class`** (broker, controller, Connect, and the CP
  components whose launcher reads `KAFKA_DEBUG` / `JAVA_DEBUG_OPTS`). If `Listening for transport dt_socket` doesn't
  show up in `playground container logs -c <c> --grep dt_socket --no-follow`, the launcher of that image ignores them:
  put `-agentlib:jdwp=…` in the image's own options variable (for example `CONTROL_CENTER_OPTS`) with
  `playground container set-environment-variables`.
- **`suspend=n` is hard-coded**: the JVM starts without waiting. To debug the startup of a worker (plugin loading, a
  connector that fails in `start()`), set `suspend=y` yourself; the command then waits (up to 300 s) for the worker to
  be ready, which happens only once your debugger is attached:

  ```bash
  playground container set-environment-variables -c connect --env "JAVA_DEBUG_OPTS: -agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=0.0.0.0:5005"
  ```

- **`disable-remote-debugging -c connect` switches the debugger off with `KAFKA_DEBUG: ''`** (the base compose has
  JDWP on, so restoring the original definition wouldn't); `enable-remote-debugging -c connect` turns it back on. On
  the other containers, `disable` restores the original definition.
- **A breakpoint suspends every thread** of the worker by default (`jdb`, VS Code): heartbeats stop, the consumer group
  of a sink rebalances after `session.timeout.ms`, the worker can leave the Connect group. Keep the pause short, or
  suspend only the thread (IntelliJ: "Suspend: Thread").
- The VS Code entry printed by the command is named after the container (`"Debug broker container"`).
- On `cfk`, Connect pods don't listen by default: `enable-remote-debugging -c <connect pod>` sets the variables (it only
  skips a `connect*` container that already has `KAFKA_DEBUG`); port-forward `5005` to attach.

---

## 3. JVM traces: `java-debug`

```bash
playground debug java-debug --type ssl_handshake                       # connect by default
playground debug java-debug -c broker --type kerberos
playground debug java-debug -c connect -c broker --type ssl_all
playground debug java-debug -c connect --type class_loading
playground debug java-debug -c connect --type class_loading --action disable   # --type is required, even to disable
```

It prints the new `KAFKA_OPTS` (the environment's value plus the option), the line of `set-environment-variables`,
then waits for Connect:

```text
☕ KAFKA_OPTS of connect: -Ddynamic.worker.config.file=/dev/null -verbose:class
📦 enabling containers connect with environment variables KAFKA_OPTS: -Ddynamic.worker.config.file=/dev/null -verbose:class
⌛ Waiting up to 300 seconds for connect to start
🚦 containers have started! (took … seconds)
```

Then read the traces with `playground container logs -c <c> --grep "<text>" --no-follow` (the JVM writes them to its
stdout, so they are in the container logs). What to look for:

```text
# --type class_loading (JDK 11+; JDK 8 prints [Loaded <class> from <jar>])
[…s][info][class,load] org.apache.kafka.connect.cli.ConnectDistributed source: file:/usr/share/java/kafka/connect-runtime-…jar
[…s][info][class,load] org.apache.kafka.connect.file.FileStreamSinkTask source: file:/usr/share/filestream-connectors/connect-file-…jar

# --type ssl_handshake: the alert says who refused what
javax.net.ssl|ERROR|…|TransportContext.java:…|Fatal (CERTIFICATE_UNKNOWN): PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
javax.net.ssl|DEBUG|…|Alert.java:…|Received alert message (
  "level"      : "fatal",
  "description": "handshake_failure"
)

# --type kerberos
Java config name: /etc/krb5.conf
>>> KdcAccessibility: reset
>>>KRBError:
	 error code is 6
	 error Message is Client not found in Kerberos database
```

Gotchas:

- **The broker of a SASL or Kerberos environment keeps its JAAS file** (mental model, point 3): `java-debug -c broker
  --type kerberos` gives `KAFKA_OPTS: -Djava.security.auth.login.config=… -Dsun.security.krb5.debug=true`.
- **Turn on the trace on the side that fails.** A sink connector that can't reach a TLS database: `-c connect`. A
  client refused by the broker: the broker sees the alert too, but the reason (an untrusted certificate, no common
  cipher) is on the side that sends the alert.
- **The trace covers the whole JVM**: on `connect`, every TLS connection (brokers, Schema Registry, the connector's
  external system) and every class of every plugin. `ssl_all` and `class_loading` write tens of thousands of lines at
  startup: always grep, never scroll, and `--action disable` when done.
- `ssl_all` prints key material and the content of the records: don't share those logs outside.
- Two traces at once: one call with both options, `set-environment-variables -c connect --env "KAFKA_OPTS: -Djavax.net.debug=ssl:handshake -verbose:class"`.
  Two `java-debug` calls keep only the last one (each call starts from the original `KAFKA_OPTS`).
- `--type` is required, also with `--action disable`.
- The traces are lost on the next `recreate`, `re-run` or `disable`, and kept by `playground container restart`.

---

## 4. TLS endpoints from the outside: `testssl`

```bash
playground debug testssl --uri "https://google.com" --fast
playground debug testssl --uri "pkc-xxxx.us-west-2.aws.confluent.cloud:9092"
playground debug testssl --uri "my-database.example.com:5432" --starttls=postgres
```

It runs [testssl.sh](https://testssl.sh/) in the `drwetter/testssl.sh` image
(`🔐 Testing TLS/SSL encryption with uri <uri> and arguments <args>`): protocols, ciphers, the certificate chain, its
validity and its names, known vulnerabilities. No Java involved: it answers "what does this endpoint offer?", which you
then compare with what the client JVM accepts (`ssl_handshake` trace above).

Gotchas:

- It works without a terminal too (an agent, a CI job, a repro model): `-ti` is only passed when there is one.
- **It runs outside the playground network**: `broker:9092` doesn't resolve. For a listener of the playground, use the
  port published on your machine through `host.docker.internal` (Docker Desktop), for example
  `--uri host.docker.internal:9092` on the `2way-ssl` or `sasl-ssl` environment. Cloud endpoints and the customer's
  hosts reachable from your machine work as they are.
- Every extra option is passed as is, one argument each: `--uri <host:port> --fast --quiet --protocols`.
- A Kafka listener is plain TLS (no STARTTLS): `host:port` is enough. For protocols that start in clear text (PostgreSQL,
  SMTP, LDAP…), add `--starttls=<protocol>`: the `=` form keeps it one argument.

---

## 5. Diagnostics bundle: `generate-diagnostics`

```bash
playground debug generate-diagnostics              # connect
playground debug generate-diagnostics -c broker
```

It runs the [Diagnostics Bundle Tool](https://docs.confluent.io/platform/current/tools/diagnostics-tool.html#collect-diagnostics)
in the container, the way support asks customers to:

1. `curl` of `diagnostics-bundle-1.0.4.jar` from `packages.confluent.io` into `/tmp` of the container,
2. `java -jar /tmp/diagnostics-bundle-1.0.4.jar collect`, its output printed as it comes,
3. the zip it writes copied to the **current directory**:

```text
⛑️ Creating diagnostics bundle for container connect
⏳ please wait...
…
Diagnostics output has been zipped and written to: /…/….zip
⛑️ diagnostics bundle is available at ….zip
```

Then read it like a customer's: `playground analyze logs -f <zip>`.

Gotchas:

- **`connect` and `broker` only**, by exact name: `connect2`, `broker2` or a CFK pod name stop with
  `❌ only connect and broker containers are supported`.
- **The container needs internet access** to download the jar (version 1.0.4, fixed in the script). Behind a proxy or
  offline: `❌ Failed to generate bundle`, followed by the output of the tool.
- The zip lands where you run the command: run it from `/tmp` (or `cd` back) to keep it out of the repository.
- A bundle holds configurations and logs: same care as a customer bundle before sharing it.

---

## 6. Hands-on lab (≈10 min)

```bash
playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/other/deep-dive-labs/docker-compose.plaintext.yml"
```

The plaintext environment with the FileStream connectors on the plugin path (what the lab script starts).

**Step 1: `connect` already listens for a debugger**

```bash
playground container logs -c connect --grep "dt_socket" --no-follow
# Listening for transport dt_socket at address: 5005
playground debug enable-remote-debugging
# 💫 enable-remote-debugging is already enabled for connect container connect
```

**Step 2: a debugger on the broker**

```bash
playground debug enable-remote-debugging -c broker
# ✨ enable remote debugging for broker
# 📦 enabling containers broker with environment variables KAFKA_DEBUG: 'true' JAVA_DEBUG_OPTS: '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=0.0.0.0:5005'
# …
#                     "port": 5005,
# …
# see https://kafka-docker-playground.io/#/toolkit-debugging?id=✨-remote-debugging
playground container logs -c broker --grep "dt_socket" --no-follow
# Listening for transport dt_socket at address: 5005   <- inside the Docker network: localhost:5005 is still connect
```

**Step 3: back to the original broker**

```bash
playground debug disable-remote-debugging -c broker
# 🛑 disable remote debugging for broker
# 🧽 restore back original values before any changes was made for containers broker
playground container logs -c broker --grep "dt_socket" --no-follow
#   <- nothing: a new container, without the variables
```

**Step 4: which jar a class comes from**

```bash
playground debug java-debug -c connect --type class_loading
# ☕ KAFKA_OPTS of connect: -Ddynamic.worker.config.file=/dev/null -verbose:class
playground connector create-or-update --connector filestream-sink << 'EOF'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false"
}
EOF
playground container logs -c connect --grep "FileStreamSinkTask source:" --no-follow
# [….…s][info][class,load] org.apache.kafka.connect.file.FileStreamSinkTask source: file:/usr/share/filestream-connectors/connect-file-…jar
playground container logs -c connect --grep "dt_socket" --no-follow
# Listening for transport dt_socket at address: 5005   <- KAFKA_OPTS changed, the debugger is still there
```

**Step 5: the traces off**

```bash
playground debug java-debug -c connect --type class_loading --action disable
# 🧽 restore back original values before any changes was made for containers connect
playground container logs -c connect --grep "class,load" --no-follow
#   <- nothing
playground connector wait --connector filestream-sink
#   <- RUNNING again: a recreated worker, the same connector (its config is in Kafka)
```

**Step 6: the debugger of connect off, then on again**

```bash
playground debug disable-remote-debugging -c connect
playground container logs -c connect --grep "dt_socket" --no-follow
#   <- nothing: KAFKA_DEBUG is empty
playground debug enable-remote-debugging -c connect --skip-vs-code-config-display
# ✨ enable remote debugging for connect
playground container logs -c connect --grep "dt_socket" --no-follow
# Listening for transport dt_socket at address: 5005
```

**Step 7 (not replayed by the lab): testssl and the diagnostics bundle**

```bash
# needs internet access
playground debug testssl --uri "https://google.com" --fast
# 🔐 Testing TLS/SSL encryption with uri https://google.com and arguments --fast
cd /tmp && playground debug generate-diagnostics -c connect
# ⛑️ Creating diagnostics bundle for container connect
# …
# ⛑️ diagnostics bundle is available at ….zip
```

```bash
playground stop
```

---

## 7. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "I need a breakpoint in the connector" | nothing to enable on `connect`: `playground connector-plugin sourcecode -c <owner/name> --connector-tag <v> --checkout-only`, then `jdb -attach localhost:5005 -sourcepath <folder>/src/main/java` or your IDE (the 🐞 session) |
| "the connector fails in `start()`, I need the very first lines" | `set-environment-variables -c connect --env "JAVA_DEBUG_OPTS: …suspend=y…"`, attach while the command waits, then create the connector |
| "a breakpoint in the broker / Schema Registry" | `debug enable-remote-debugging -c <c>` + a published port in the compose override |
| `PKIX path building failed` / `unable to find valid certification path` | `java-debug -c connect --type ssl_handshake`: the chain the server sent and the truststore that was used; the CA is missing from the truststore of the client |
| `Received fatal alert: handshake_failure` / `No appropriate protocol` | `testssl --uri <host:port>` for what the server offers, `java-debug --type ssl_handshake` on the client for what it proposes (protocols, cipher suites) |
| `SSLHandshakeException: No subject alternative names matching …` | `ssl_handshake`: the names of the certificate in the trace vs the host the client connects to (`ssl.endpoint.identification.algorithm`) |
| `GSS initiate failed` / `Cannot locate KDC` / `Client not found in Kerberos database` | `java-debug -c connect --type kerberos` (on a `kerberos` / `ssl_kerberos` environment): the `krb5.conf` read, the principal, the KDC error code |
| `ClassNotFoundException` / `NoClassDefFoundError` | `java-debug -c connect --type class_loading`, grep the class: no line = not on the plugin path or the classpath; `connector-plugin search-jar --class <class>` for the jar that should have it |
| `NoSuchMethodError` / `ClassCastException` between two versions of a library | `class_loading`, grep the class: the `source:` names the jar that won (the plugin's or the worker's); `connector-plugin search-jar --with-worker` for the duplicates |
| "support asked for a diagnostics bundle" (to see what it collects) | `cd /tmp && debug generate-diagnostics -c connect`, then `analyze logs -f <zip>` |
| "is the certificate of our endpoint valid? which TLS versions?" | `debug testssl --uri <host:port>` from your terminal |

In a repro model, turn the trace on before the connector is created, and grep the line that proves the cause:

```bash
playground debug java-debug -c connect --type ssl_handshake
playground connector create-or-update --connector my-sink << EOF … EOF
playground container logs -c connect --grep "PKIX path building failed" --no-follow
playground debug java-debug -c connect --type ssl_handshake --action disable
```

---

## 8. Cheat sheet

```bash
jdb -attach localhost:5005                                     # connect (connect2: 5205, connect3: 5305)
playground debug enable-remote-debugging  [-c <c>]… [--skip-vs-code-config-display]
playground debug disable-remote-debugging [-c <c>]…
playground connector enable-remote-debugging                   # clone + compile + editor, interactive
playground connector disable-remote-debugging
playground debug java-debug [-c <c>]… --type ssl_all|ssl_handshake|class_loading|kerberos [--action enable|disable]
playground debug testssl --uri <host|host:port|https URL> [<one testssl option>]
playground debug generate-diagnostics [-c connect|broker]
playground container set-environment-variables -c <c> --env "KAFKA_OPTS: …" | --restore-original-values
```

- `connect` listens on 5005 out of the box; other containers: `enable-remote-debugging` (`KAFKA_DEBUG` +
  `JAVA_DEBUG_OPTS`, read by `kafka-run-class`), reachable inside the Docker network unless you publish a port.
- `enable` / `disable` / `java-debug` = `set-environment-variables` = the container is recreated; one override at a
  time; `disable` restores everything.
- `java-debug` replaces `KAFKA_OPTS`: careful with the brokers of SASL / Kerberos environments (JAAS file).
- Traces are in the container logs: `container logs -c <c> --grep … --no-follow`, then `--action disable`.
- `testssl`: TTY needed, outside the playground network, one extra option. `generate-diagnostics`: connect or broker,
  internet access, zip in the current directory.
- Sources: [`debug/enable-remote-debugging.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/debug/enable-remote-debugging.sh),
  [`debug/disable-remote-debugging.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/debug/disable-remote-debugging.sh),
  [`debug/java-debug.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/debug/java-debug.sh),
  [`debug/testssl.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/debug/testssl.sh),
  [`debug/generate-diagnostics.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/debug/generate-diagnostics.sh),
  [`connector/enable-remote-debugging.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/connector/enable-remote-debugging.sh),
  [`container/set-environment-variables.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/container/set-environment-variables.sh),
  the `connect` service of [`environment/plaintext/docker-compose.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/plaintext/docker-compose.yml).

---

**Links**

- 🎬 Video session: [🐞 A breakpoint in a running connector: remote debugging](/sessions?id=🐞-a-breakpoint-in-a-running-connector-remote-debugging)
- 🍪 Deep dives: [JVM diagnostics](/deep-dive-jvm-diagnostics.md) (thread dumps, heap, GC, flight recorder, jscissors,
  tcp dumps: the TLS alert on the wire), [secured environments](/deep-dive-secured-environments.md) (where SSL and
  Kerberos errors come from), [log levels](/deep-dive-log-levels.md) (the connector's own logs at TRACE),
  [connector plugins: `search-jar`](/deep-dive-connector-plugin?id=_5-jars-search-jar) (which jar has a class),
  [containers](/deep-dive-container-lifecycle.md) (`set-environment-variables`, restart vs recreate)
- 📖 In the Reproduction toolkit: [✨ Remote debugging](/toolkit-debugging?id=✨-remote-debugging),
  [🔑 SSL debug](/toolkit-debugging?id=🔑-ssl-debug), [🔒 Kerberos debug](/toolkit-debugging?id=🔒-kerberos-debug),
  [🔬 Class loading](/toolkit-debugging?id=🔬-class-loading),
  [🧰 More debug commands](/toolkit-debugging?id=🧰-more-debug-commands)
- 🧠 CLI reference: [playground debug enable-remote-debugging](/playground%20debug%20enable-remote-debugging),
  [playground debug disable-remote-debugging](/playground%20debug%20disable-remote-debugging),
  [playground debug java-debug](/playground%20debug%20java-debug),
  [playground debug testssl](/playground%20debug%20testssl),
  [playground debug generate-diagnostics](/playground%20debug%20generate-diagnostics),
  [playground connector enable-remote-debugging](/playground%20connector%20enable-remote-debugging)
