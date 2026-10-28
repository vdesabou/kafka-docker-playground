# 🍪 Deep dive: secured environments (`--environment`)

The same example runs on a plaintext cluster, behind SASL/PLAIN, SCRAM, SASL_SSL, mutual TLS, Kerberos, LDAP or RBAC,
by changing one flag. The CLI then talks to the secured cluster for you: `topic produce` / `topic consume` pick the
right client config, `connector create-or-update` adds the security keys the connector needs, and the Connect and
Schema Registry REST calls carry the right certificate or user. This is how you reproduce "it works in dev, not in our
SSL cluster" or "the connector gets `TopicAuthorizationException`". Takes about 15 minutes to read and run.

> [!TIP]
> 🎬 Short on time? The video session [🔐 The same example under SASL_SSL and RBAC](/sessions?id=🔐-the-same-example-under-sasl_ssl-and-rbac) shows it in 5 minutes: the same commands under `sasl-ssl`, the security keys `create-or-update` adds, then a role binding removed under RBAC and the `TopicAuthorizationException` it causes.
>
> The video session [🕹️ Run an example: with the menu or with flags](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags)
> runs an example under `--environment sasl-ssl`. This page goes further: what each environment sets up, how the CLI
> adapts, where the credentials are, a hands-on lab and recipes for support repros.

| You want | Command |
| --- | --- |
| the customer's security setup for an example | `playground run -f <example> --environment sasl-ssl` (or any type below) |
| an environment without an example | `playground start-environment --environment rbac-sasl-plain` |
| the client config a component really loaded | `playground container get-properties -c connect` |
| the security keys added to a connector config | `playground connector create-or-update … --dry-run` |
| the config exactly as written, without them | `create-or-update … --skip-automatic-connector-config` |
| new certificates (expired, or another container) | `playground tools certs-create --output-folder <dir> [-c <container>]` |
| an authorization error (RBAC) | `playground rbac role-binding delete --principal User:connectorSA …` |
| an authorization error (Confluent Cloud ACLs) | `playground rbac acl delete --connector <c> …` (see [🚦 Reproduce an authorization error](/reusables?id=🚦-reproduce-an-authorization-error)) |

---

## 1. Mental model (the 3 things to remember)

1. **Every environment is plaintext plus one compose file.** `environment/<type>/start.sh` runs
   `docker compose -f environment/plaintext/docker-compose.yml [-f environment/sasl-plain/docker-compose.yml] -f environment/<type>/docker-compose.yml -f <example override> … up -d`.
   The secured file only changes listeners, JAAS, keystores and authorizers; container names, ports and the example's
   override (plugin path, external systems) stay the same. That's why `docker-compose.plaintext.yml` of an example
   works under every type, and why an example only needs
   `PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}` to run anywhere (CI re-runs `connect/` examples
   under other environments that way). The full command is recorded in `playground.ini` (`run.docker_command`) and
   `run.environment`, so `recreate`, `re-run` and `stop` replay it.

2. **The CLI reads `run.environment` and adapts each call.** Nothing to pass on the command line:
   - `topic produce` / `topic consume` run the console clients in the `connect` container (or `client` for Kerberos)
     with the environment's client config (`--command-config` / `--producer.config`) and, on SSL types, the Schema
     Registry keystore / truststore;
   - `connector create-or-update` adds the security keys of the environment to the config
     (`add_connector_config_based_on_environment`) when the config has keys that open their own Kafka or Schema
     Registry connection: `confluent.topic.bootstrap.servers`, `redo.log.consumer.bootstrap.servers`,
     `*.converter.schema.registry.url`, `schema.history.internal.kafka.bootstrap.servers` /
     `database.history.kafka.bootstrap.servers`, `reporter.bootstrap.servers`, and on RBAC `principal.service.name`.
     It prints them: `✨ Following config was added to handle environment sasl-ssl:` and a diff;
   - the Connect and Schema Registry REST calls switch to `https://localhost:8083` / `:8081` with the client
     certificate on `sasl-ssl` and `2way-ssl`, and to basic auth on RBAC (`connectorSubmitter` for Connect,
     `superUser` for Schema Registry).

3. **Credentials are fixed, public, and on disk.** Users and passwords are the same in every run (`client` /
   `client-secret`, `admin` / `admin-secret`, keystore password `confluent`, RBAC users named after their role…).
   They live in the environment folder (`client.properties`, `*.jaas.conf`, `security/` for certificates, keytabs
   generated in `kdc`), mounted in the containers. Fine for a reproduction, never for anything else: don't copy them
   into a customer answer as "the" config, copy the keys.

---

## 2. The environments

| `--environment` | Broker listener | Inter-broker / client auth | Schema Registry | Connect REST | Client config used by the CLI |
| --- | --- | --- | --- | --- | --- |
| `plaintext` | `PLAINTEXT` | none | `http`, no auth | `http`, no auth | none |
| `sasl-plain` | `SASL_PLAINTEXT` | `PLAIN` | `http` | `http` | `/tmp/client.properties` (`environment/sasl-plain/client.properties`) |
| `sasl-scram` | `SASL_PLAINTEXT` | `SCRAM-SHA-256` | `http` | `http` | `/tmp/client.properties` (`environment/sasl-scram/client.properties`) |
| `sasl-ssl` | `SASL_SSL` (`ssl.client.auth=required`) | `PLAIN` over TLS, client certificate | `https`, client certificate | `https`, client certificate | `/etc/kafka/secrets/client_without_interceptors.config` |
| `2way-ssl` | `SSL` (`ssl.client.auth=required`) | mutual TLS | `https`, client certificate | `https`, client certificate | `/etc/kafka/secrets/client_without_interceptors.config` |
| `kerberos` | `SASL_PLAINTEXT` | `GSSAPI`, `kdc` container, keytabs | `http` | `http` | `/etc/kafka/producer.properties` in the `client` container, after `kinit` |
| `ssl_kerberos` | `SASL_SSL` | `GSSAPI` over TLS | `http` | `http` | same as `kerberos` |
| `ldap-sasl-plain` | `SASL_PLAINTEXT` | `PLAIN`, users checked in OpenLDAP | `http` | `http` | `/tmp/client.properties` |
| `ldap-authorizer-sasl-plain` | `SASL_PLAINTEXT` | `PLAIN`, `LdapAuthorizer` (groups from LDAP → ACLs) | `http` | `http` | `/service/kafka/users/client.properties` |
| `rbac-sasl-plain` | `SASL_PLAINTEXT` (+ `TOKEN` listener) | `PLAIN`, clients `OAUTHBEARER` with MDS tokens, `ConfluentServerAuthorizer` | `http`, basic auth, `RbacAuthorizer` | `http`, basic auth (`connectorSubmitter`) | `/etc/kafka/secrets/client_without_interceptors.config` |

Other types, with their own pages: `cfk` / `cfk-rbac` (Confluent for Kubernetes, see the
[`analyze cfk-bundle` session](/sessions?id=☸️-what-is-wrong-in-this-cfk-cluster)), `mdc-plaintext` /
`mdc-sasl-plain` / `mdc-kerberos` (two clusters, see [replication between clusters](/deep-dive-replication.md)), and
`ccloud` (Confluent Cloud, `bootstrap_ccloud_environment` in `ccloud/` examples).

Gotchas:

- **Kerberos needs FQDNs**: the broker is `broker.kerberos-demo.local:9092`, the console clients run in the `client`
  container after `kinit -k -t /var/lib/secret/kafka-connect.key connect` (the CLI does it). A short name fails the
  GSSAPI handshake.
- **SSL certificates expire**: `start.sh` of the SSL types runs `playground tools certs-create` in
  `environment/<type>/security` on every start. If you copied a `security/` folder somewhere, regenerate it with the
  same command.
- **RBAC starts more**: OpenLDAP, MDS on the brokers (`http://broker:8091`), and the default role bindings of
  `environment/rbac-sasl-plain/role-bindings.txt`. Connectors are created by `connectorSubmitter` and run as
  `connectorSA` (`principal.service.name` / `principal.service.password`, added for you). It's the slowest type to
  start (in the lab: the run creates about 35 role bindings before the example starts).
- `--rbac-role-bindings-file <file>` (with `rbac-sasl-plain` only) replaces the default role bindings: start from a
  copy of `role-bindings.txt`, remove what the customer doesn't grant.

---

## 3. What changes in a connector config

```bash
playground connector create-or-update -c my-sink --dry-run << EOF
{ "connector.class": "…", "confluent.topic.bootstrap.servers": "broker:9092", "value.converter.schema.registry.url": "http://schema-registry:8081", … }
EOF
```

| Environment | Keys added or replaced |
| --- | --- |
| `sasl-plain`, `ldap-sasl-plain`, `ldap-authorizer-sasl-plain` | `<prefix>.sasl.jaas.config` (`client` / `client-secret`), `<prefix>.security.protocol=SASL_PLAINTEXT`, `<prefix>.sasl.mechanism=PLAIN` |
| `sasl-scram` | the same with `ScramLoginModule`, `SCRAM-SHA-256` |
| `sasl-ssl` | `<prefix>.bootstrap.servers=broker:9092`, JAAS, `SASL_SSL`, truststore / keystore; `*.converter.schema.registry.url=https://schema-registry:8081` + its keystore / truststore |
| `2way-ssl` | `SSL`, keystore / truststore; the same for the Schema Registry url |
| `kerberos`, `ssl_kerberos` | `GSSAPI`, `sasl.kerberos.service.name`, the keytab JAAS |
| `rbac-sasl-plain` | `principal.service.name=connectorSA`, `principal.service.password=connectorSA`, `<prefix>` JAAS as `admin` |
| `plaintext` | nothing |

`<prefix>` is each prefix found in the config: `confluent.topic`, `redo.log.consumer`, `reporter.admin` /
`reporter.producer`, `database.history.producer` / `.consumer`, `schema.history.internal.producer` / `.consumer`.

Gotchas:

- **A key the config doesn't have is not added**: a connector that only uses the worker's connection (most sinks and
  sources) gets nothing, because the worker already has the security settings (`CONNECT_SECURITY_PROTOCOL`,
  `CONNECT_SASL_*` in the environment's compose file). If the customer's connector has its own producer / consumer /
  admin overrides, write them yourself.
- **`--skip-automatic-connector-config`** sends the config as written: use it to reproduce a customer config that
  forgot one of those keys (and see the failure).
- On Confluent Cloud, the same function points those keys to `${file:/datacloud:…}` secrets: it's the same mechanism
  as here, with the cluster's API key.

---

## 4. Reproducing authentication and authorization errors

| Error | How |
| --- | --- |
| `TopicAuthorizationException` / `GroupAuthorizationException` on RBAC | `playground rbac role-binding delete --principal User:connectorSA --role ResourceOwner --resource Topic:*`, then create or restart the connector |
| a connector without the right to its topic only | `role-binding create --file` with a copy of `role-bindings.txt` (`start-environment --rbac-role-bindings-file`), or delete the wildcard and grant the topics one by one |
| ACLs with `ldap-authorizer-sasl-plain` | the groups come from LDAP: change the ACL of the group with `playground container exec -c broker --command "kafka-acls --bootstrap-server broker:9092 --command-config /service/kafka/users/kafka.properties …"` |
| SASL authentication failure | a connector override with a wrong password: `"producer.override.sasl.jaas.config": "… password=\"wrong\";"` (the worker allows overrides: `connector.client.config.override.policy=All`) |
| TLS handshake failure (`sasl-ssl`, `2way-ssl`) | a client without the keystore: `playground container exec -c connect --command "kafka-topics --bootstrap-server broker:9092 --list"` |
| Confluent Cloud | `playground rbac acl delete --connector <c> …` and `connector diagnose` (see the Reproduction toolkit) |

Gotchas:

- **A plaintext client on a TLS listener dies with `OutOfMemoryError: Java heap space`**: it reads the first TLS
  bytes as a message size. That's the symptom of a missing `security.protocol` / client config, not of a memory
  problem. Every `kafka-*` tool run by hand needs the environment's client config (`--command-config …`).
- **Restart the connector after a role binding change**: a running task keeps going with what it already opened. In
  the lab, the task failed on the restart that followed the deletion, and ran again on the restart after the role
  binding was created back.
- `playground rbac user add --user bob` creates an LDAP user for a test principal; `role-binding list --principal
  User:connectorSA` shows what a principal has.

---

## 5. Hands-on lab (≈15 min)

**Step 1: the FileStream example under SASL_SSL**

```bash
playground run -f "$PWD/connect/connect-filestream-sink/filestream-sink.sh" --environment sasl-ssl
# ✨ Following config was added to handle environment sasl-ssl: …
# ✅ RESULT: SUCCESS for filestream-sink.sh (took: 1min 21sec - )
playground state get run.environment
# sasl-ssl
playground topic produce -t filestream --nb-messages 3 --value '{"id": %g}'
playground topic consume -t filestream --min-expected-messages 8 --timeout 60
# 8 records: the 5 of the example + 3 (exit 0): the same commands as on plaintext
```

**Step 2: what the CLI uses under the hood**

```bash
playground container get-properties -c connect | grep -E "security.protocol|sasl.mechanism|listeners"
# confluent.topic.security.protocol=SASL_SSL
# consumer.sasl.mechanism=PLAIN … consumer.security.protocol=SASL_SSL
# listeners=https://0.0.0.0:8083
# producer.sasl.mechanism=PLAIN … producer.security.protocol=SASL_SSL
# sasl.mechanism=PLAIN
# security.protocol=SASL_SSL
playground connector create-or-update -c filestream-sink --dry-run << EOF
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/tmp/output.json",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://schema-registry:8081"
}
EOF
# ✨ Following config was added to handle environment sasl-ssl:
# <   "value.converter.schema.registry.url": "http://schema-registry:8081"
# >   "value.converter.schema.registry.ssl.key.password": "confluent",
# >   "value.converter.schema.registry.ssl.keystore.location": "/etc/kafka/secrets/kafka.connect.keystore.jks",
# >   "value.converter.schema.registry.ssl.truststore.location": "/etc/kafka/secrets/kafka.connect.truststore.jks", …
# >   "value.converter.schema.registry.url": "https://schema-registry:8081"
# 🌵 --dry-run: 🌎onprem connector filestream-sink would be updated with this config
playground container exec -c connect --command "kafka-topics --bootstrap-server broker:9092 --list"
# Error while executing topic command : The AdminClient thread has exited. Call: listTopics
# java.lang.OutOfMemoryError: Java heap space        <- a plaintext client reading TLS bytes as a message size: exit 1
playground container exec -c connect --command "kafka-topics --bootstrap-server broker:9092 --command-config /etc/kafka/secrets/client_without_interceptors.config --list"
# __consumer_offsets … filestream …                  <- with the client config the CLI uses
```

**Step 3: the same example under RBAC, then an authorization error**

```bash
playground run -f "$PWD/connect/connect-filestream-sink/filestream-sink.sh" --environment rbac-sasl-plain
# 🔐 Creating role binding ResourceOwner for User:connectorSA on Topic:* (kafka cluster) … (about 35 bindings)
# ✅ RESULT: SUCCESS for filestream-sink.sh (took: 1min 15sec - )
playground rbac role-binding list --principal User:connectorSA
# User:connectorSA  ResourceOwner  kafka            Group:*
# User:connectorSA  ResourceOwner  kafka            Topic:*
# User:connectorSA  ResourceOwner  kafka            TransactionalId:*
# User:connectorSA  ResourceOwner  schema-registry  Subject:*
playground rbac role-binding delete --principal User:connectorSA --role ResourceOwner --resource Topic:*
playground connector restart -c filestream-sink
playground connector wait -c filestream-sink --state FAILED --max-wait 120
playground connector status -c filestream-sink
# filestream-sink   ✅ RUNNING  0:🛑 FAILED   tasks: org.apache.kafka.common.errors.TopicAuthorizationException: Not authorized to access topics: [filestream]
playground rbac role-binding create --principal User:connectorSA --role ResourceOwner --resource Topic:*
playground connector restart -c filestream-sink
playground connector wait -c filestream-sink --max-wait 120
```

```bash
playground stop
```

---

## 6. Recipes for support repros

| Customer setup or symptom | Command |
| --- | --- |
| "works on our dev cluster, fails in the SSL cluster" | the example under `--environment sasl-ssl` (or `2way-ssl`), then `create-or-update --dry-run` to see which keys their config must carry |
| "the connector config has its own producer / consumer settings" | write them in the config, and `--skip-automatic-connector-config` to send it as the customer does |
| "`TopicAuthorizationException` with RBAC" | `rbac-sasl-plain`, delete the role binding of `connectorSA` on the topic (or start with `--rbac-role-bindings-file`) |
| "the connector can't create its topics / its DLQ" | RBAC: give `connectorSA` a narrower role on the topics (for example `DeveloperWrite`) instead of `ResourceOwner`: creating a topic needs more, see the Confluent RBAC role reference |
| "Kerberos ticket / principal errors" | `--environment kerberos` (or `ssl_kerberos`), principals and keytabs in `environment/kerberos/` |
| "users in LDAP, ACLs per group" | `ldap-authorizer-sasl-plain` |
| "Schema Registry over HTTPS with client certificates" | `sasl-ssl` / `2way-ssl`: the converter keys get the keystore / truststore, `playground schema …` uses the client certificate |
| "certificates expired in our repro folder" | `playground tools certs-create --output-folder <dir>` |
| "the same on Confluent Cloud" | a `ccloud/fm-*` example, and `playground rbac acl` for the service account |

In a repro model, keep `PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"<customer's type>"}` at the top: `playground
run` without `--environment` then uses the customer's setup, and CI can still run it elsewhere.

---

## 7. Cheat sheet

```bash
playground run -f <example> --environment plaintext|sasl-plain|sasl-scram|sasl-ssl|2way-ssl|kerberos|ssl_kerberos|ldap-sasl-plain|ldap-authorizer-sasl-plain|rbac-sasl-plain
playground start-environment --environment <type> [--docker-compose-override-file <example override>] [--rbac-role-bindings-file <file>]
playground state get run.environment
playground container get-properties -c connect|broker|schema-registry
playground connector create-or-update -c <c> [--dry-run] [--skip-automatic-connector-config] << EOF … EOF
playground tools certs-create --output-folder <dir> [-c <container>]...
playground rbac role-binding list|create|delete …    playground rbac user add|list|delete …    playground rbac acl …
```

- Every type = `environment/plaintext/docker-compose.yml` + its own file + the example's override.
- The CLI adapts produce / consume, connector configs and REST calls from `run.environment`: no flag to pass.
- Keys are added to a connector config only when it opens its own connection (`confluent.topic.*`, converters with a
  Schema Registry url, schema history, reporter). `--dry-run` shows them.
- Credentials are fixed and public, in `environment/<type>/`.
- Sources: [`environment/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment),
  [`start-environment.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/start-environment.sh),
  `add_connector_config_based_on_environment` / `get_connect_url_and_security` / `get_sr_url_and_security` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh).

---

**Links**

- 🎬 Video sessions: [🔐 The same example under SASL_SSL and RBAC](/sessions?id=🔐-the-same-example-under-sasl_ssl-and-rbac), [🕹️ Run an example: with the menu or with flags](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags) (`--environment sasl-ssl`)
- 🍪 Deep dives: [running examples and changing versions](/deep-dive-run-and-versions.md),
  [`connector create-or-update`](/deep-dive-connector-create-or-update.md) (`--dry-run`, `--skip-automatic-connector-config`),
  [containers](/deep-dive-container-lifecycle.md) (`get-properties`)
- 📖 [How it works: environments](/how-it-works.md) and [🚦 Reproduce an authorization error](/reusables?id=🚦-reproduce-an-authorization-error)
- 🧠 CLI reference: [playground run](/playground%20run),
  [playground rbac](/playground%20rbac), [playground tools certs-create](/playground%20tools%20certs-create)
