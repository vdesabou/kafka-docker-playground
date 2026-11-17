# 🛡️ Platform, security and Cloud infra

For cases about **Confluent for Kubernetes** and **cp-ansible** (CRs, inventories, support bundles, upgrades and
day-2 changes, KRaft migration), **security**
(SASL, SSL / mTLS, Kerberos, LDAP, RBAC, OAuth / OIDC, ACLs, secrets, audit logs), **certificates**, and the
**client side of Confluent Cloud connectivity**. Every example runs under the customer's security setup with one flag:
the CLI then talks to the secured cluster for you.

> [!TIP]
> **🔁 New: [Day-2 operations with cp-ansible and CFK](/day-2-operations.md).** Examples replay a change on a
> running cluster, the way the cp-ansible and CFK procedures describe it, with a producer and a sink connector running
> through it: CP rolling upgrades, a **CFK ZooKeeper to KRaft migration** (`KRaftMigrationJob`), PLAINTEXT to SASL_SSL with CFK and cp-ansible, adding and removing brokers, a **CFK operator upgrade** (plain `helm upgrade`: every pod restarted twice; the
> block-reconcile procedure: one roll per component), PLAINTEXT to SASL_SSL, RBAC, scale out, static to dynamic KRaft
> quorum. Each one shows the classic mistake next to the right procedure, measured on the same cluster, prints every
> `kubectl` / `helm` / `ansible-playbook` command it runs, and ends with a no-record-lost check.

> [!TIP]
> **🐳 A log bundle, with nothing installed but Docker.** `playground analyze logs` is also a public image: run it on
> the CFK support bundle attached to the case, from the folder that holds it, with no clone, no CLI and no environment.
> `--network none`: the logs never leave the machine.
> `docker run --rm --network none -v "$PWD":/data -e KDP_HOST_DIR="$PWD" ghcr.io/vdesabou/kdp-analyze-logs -f <bundle>.zip --sanitize`
> (to try it first: `cd /tmp && docker run --rm --network none -v "$PWD":/data -e KDP_HOST_DIR="$PWD" ghcr.io/vdesabou/kdp-analyze-logs --sample cfk_bundle`).
> More: [🐳 With nothing installed but Docker](/deep-dive-analyze-logs.md?id=🐳-with-nothing-installed-but-docker).

## 🚀 5 commands to try

```bash
# the same example, under the customer's security: sasl-plain, sasl-scram, sasl-ssl, 2way-ssl, sasl-oauthbearer,
# kerberos, ssl_kerberos, ldap-sasl-plain, ldap-authorizer-sasl-plain, rbac-sasl-plain, rbac-oauth, cfk, cfk-rbac…
playground run -f "$PWD/connect/connect-filestream-sink/filestream-sink.sh" --environment rbac-sasl-plain

playground container get-properties -c broker                  # what the component really loaded (listeners, JAAS, authorizer)
playground rbac role-binding list --principal User:connectorSA  # who can do what
playground tools cert inspect --server broker:9092              # chain, SANs, expiry, what a client would trust
playground analyze logs --sample cfk_bundle --output-dir /tmp/cfk-bundle   # a CFK support bundle digest, no environment needed
```

Every security example: `playground find-example --category security --limit 50`; CFK: `--category cfk`.

## ❓ Your question, the answer

### 🔁 Day-2 operations: upgrades and changes on a running cluster

What the clients see during the change, the classic mistake next to the right procedure, every low-level command
printed as it runs: [🔁 Day-2 operations](/day-2-operations.md).

| Question | Command or example |
| --- | --- |
| "Our producers failed while cp-ansible upgraded the cluster" | [`other/cp-ansible-day2/rolling-upgrade.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/rolling-upgrade.sh): the default `deployment_strategy` (`parallel`) restarts every broker at once, `rolling` one at a time; on the customer's inventory: `playground ansible upgrade --to <version>` |
| "We enabled SASL_SSL / RBAC with cp-ansible and some applications stopped" | [`enable-sasl-ssl.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/enable-sasl-ssl.sh) (the forgotten PLAINTEXT client), [`enable-rbac.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/enable-rbac.sh) (the application without a role binding) |
| Add brokers or controllers with cp-ansible, static to dynamic KRaft quorum | [`scale-out-brokers.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/scale-out-brokers.sh), [`static-to-dynamic-quorum.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cp-ansible-day2/static-to-dynamic-quorum.sh), `playground ansible add-host <host>` |
| "We upgraded CP with CFK, what should the clients see?" | [`other/cfk-day2/cfk-rolling-upgrade.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cfk-day2/cfk-rolling-upgrade.sh), or `playground cfk upgrade --to <version>` on a running cfk environment |
| "After the CFK upgrade every component restarted, some twice" | [`other/cfk-day2/cfk-operator-upgrade.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cfk-day2/cfk-operator-upgrade.sh): `playground cfk operator upgrade --to <version> --no-block-reconcile` (what they did) against `playground cfk operator upgrade --to <version>` (the procedure) |
| "We ran `helm upgrade`, the operator still runs the old version" | `--reuse-values` keeps the old `image.tag`: `helm -n confluent get values confluent-operator --all \| grep tag`; `playground cfk operator upgrade` uses `--reset-then-reuse-values` |
| Change a CR and see what the operator does; restart the brokers the supported way | `playground cfk patch <kind>/<name> '<patch>'` (waits for the roll, prints each pod as it restarts and the events), `playground cfk roll kafka/kafka` (annotation `kafkacluster-manual-roll`) |
| "Our ZooKeeper to KRaft migration is stuck", "is it stuck or just slow?" | `playground cfk kraft-migration status`; a complete migration with a workload, each sub-phase and its duration: [`other/cfk-day2/cfk-kraft-migration.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cfk-day2/cfk-kraft-migration.sh) |
| "After the KRaft migration Argo CD / Flux can't change the Kafka CR" | the locks of the migration were not released (`… is locked during KRaft migration`): `playground cfk kraft-migration release-lock` |
| "We enabled SASL_SSL with CFK: nothing happened / producers failed during the roll / connect can't reach Kafka" | [`other/cfk-day2/cfk-enable-sasl-ssl.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cfk-day2/cfk-enable-sasl-ssl.sh): `ApplyFailed` hidden in the CR conditions, the `replication` listener inheriting `internal` (the inter-broker protocol changed in one roll), Connect and Schema Registry with a PLAINTEXT `dependencies.kafka` |
| "We added brokers, they hold nothing" / "we reduced spec.replicas and nothing happened" | [`other/cfk-day2/cfk-scale-out-brokers.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/cfk-day2/cfk-scale-out-brokers.sh): Self-Balancing enabled but `STARTING`, `playground topic reassign`, the shrink refused in the CR conditions |
| "Our configOverrides disappeared" | a JSON merge patch replaces the whole list: `playground cfk patch kafka/kafka '<patch>'` shows it, `--type json` with an `add` operation keeps the list |

### ☸️ Confluent for Kubernetes

| Question | Command or example |
| --- | --- |
| Run CP on Kubernetes like the customer | `--environment cfk` (or `cfk-rbac`, with OpenLDAP and role bindings) on any `connect/` example, `CFK_VERSION=<version>` for another operator version |
| "Here is the support bundle" | `playground analyze logs -f <bundle> --output-dir /tmp/cfk-reports`: rollout issues, KRaft migration, plugin install, `--problem "<what the customer says>"` for a verdict · 👀 or [`playground analyze watch`](/deep-dive-analyze-logs?id=%f0%9f%91%80-every-download-analyzed-without-typing-anything): every file downloaded to `~/Downloads` analyzed automatically |
| "Here is a new bundle, what changed?" | `playground analyze logs -f <older bundle> -f <newer bundle>` |
| The customer's `Connector` CR doesn't behave | `playground connector create-or-update` / `validate` / `diff` read CFK CRs directly |
| Which operator code logs this error? | `playground debug cfk sourcecode --bundle <bundle> --grep "<message>"` |
| What would a bundle of my repro look like? | `playground debug cfk generate-bundle`, then `analyze logs` on it |
| Upgrade CP or the operator, ZooKeeper to KRaft, change a CR, restart the brokers | `playground cfk upgrade\|operator upgrade\|kraft-migration\|patch\|roll`, with a workload: [🔁 Day-2 operations](/day-2-operations.md) |

### 🅰️ cp-ansible

| Question | Command or example |
| --- | --- |
| The playbook fails, renders a wrong properties file, or an upgrade breaks | `playground start-environment --environment ansible` (`--tag` for CP, `ANSIBLE_CP_VERSION` / `ANSIBLE_CORE_VERSION` for the customer's cp-ansible and ansible-core), or the customer's own `hosts.yml` with `--ansible-inventory <hosts.yml>` (connection, host names, vault values, certificates and mirrors adapted, each change printed), then edit `environment/ansible/inventory/hosts.yml` and run the playbook again: recipes in [environment/ansible](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/ansible) |
| A connector, ksqlDB or Control Center on a cluster deployed by cp-ansible | any `connect/` example with `--environment ansible` (`--enable-ksqldb`, `--enable-control-center`, `--enable-multiple-brokers`… add hosts): the example's compose override becomes inventory variables, and the `playground` commands work on the hosts (logs from journald, `broker stop` through systemd) |
| The same with security | `--environment ansible-sasl-ssl`: SASL/PLAIN and SSL on every listener, https REST APIs, certificates generated by cp-ansible |
| Change a variable, upgrade, add hosts on the running cluster | `playground ansible inventory set <path> <value>` then `playground ansible playbook --rolling`, `playground ansible upgrade --to <version>`, `playground ansible add-host <host>`; with a workload: [🔁 Day-2 operations](/day-2-operations.md) |

### 🔐 Security

| Question | Command or example |
| --- | --- |
| Works in dev, fails in the SSL cluster | the same example with `--environment sasl-ssl` (or `2way-ssl`), `connector create-or-update --dry-run` for the security keys the config must carry |
| `TopicAuthorizationException` with RBAC | `--environment rbac-sasl-plain`, `rbac role-binding delete --principal User:connectorSA …` to reproduce it on purpose, `--rbac-role-bindings-file` to start with the customer's bindings |
| ACLs: centralized (MDS) or Kafka ACLs, DENY vs role binding | `playground rbac acl create\|list\|delete` (`--kafka-acls` for Kafka ACLs), example [other/rbac-centralized-acls](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/rbac-centralized-acls) |
| mTLS: `TopicAuthorizationException` after a certificate renewal, `ssl.principal.mapping.rules` | example [other/mtls-principal-mapping](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/mtls-principal-mapping): the principal of the renewed certificate in the broker log (`kafka.authorizer.logger`), ACL on the full DN, rule fixed with `playground container set-environment-variables` (not a dynamic config) |
| OAuth / OIDC: `invalid_token`, key rotation, issuer or audience mismatch | `--environment sasl-oauthbearer` (Keycloak), recipes in [environment/sasl-oauthbearer](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/sasl-oauthbearer) |
| RBAC with OAuth / OIDC (MDS with an external identity provider, no LDAP): `Group:` role binding from the `groups` claim, REST API `401`, connector principal | `--environment rbac-oauth` (Keycloak), `playground rbac user add --user <client> --group <group>` adds a Keycloak client, recipes in [environment/rbac-oauth](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/rbac-oauth) |
| Kerberos principal or ticket errors | `--environment kerberos` (or `ssl_kerberos`) |
| Kerberos: "works for hours, then fails at the next reconnect", `Could not renew TGT … kinit -R`, `Checksum failed` at re-login, `terminated during authentication` on a GSSAPI client | example [other/kerberos-ticket-expiry](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/kerberos-ticket-expiry): 3 minute tickets set on the KDC (`modprinc -maxlife`), keytab vs ticket cache, a keytab out of date, `connections.max.reauth.ms`; `playground analyze logs` names each case |
| Users and groups in LDAP | `--environment ldap-sasl-plain`, `ldap-authorizer-sasl-plain`, examples [other/ldap-authorizer-with-ldap-failover](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/ldap-authorizer-with-ldap-failover) |
| `PKIX path building failed`, expired certificate, hostname mismatch | `playground tools cert inspect --file <certificate or keystore> --truststore <truststore> --hostname <host>` (or `--server <host:port>`) |
| JKS ↔ PKCS12 ↔ PEM, Kafka PEM properties | `playground tools cert convert --to pkcs12\|jks\|pem\|der\|properties` |
| Certificates for a repro | `playground tools cert create --output-folder <dir>` |
| Audit logs, authentication logs, secrets | examples [other/audit-logs](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/audit-logs), [other/capture-authentication-logs](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/capture-authentication-logs), [other/secrets-management](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/secrets-management), [other/connect-secret-registry](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/connect-secret-registry) |
| Security plugins of Schema Registry and REST Proxy, Control Center with LDAP | [other/schema-registry-security-plugin](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/schema-registry-security-plugin), [other/rest-proxy-security-plugin](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/rest-proxy-security-plugin), [other/control-center-ldap-auth](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/control-center-ldap-auth) |
| SSL handshake or Kerberos details in the JVM | `playground debug java-debug` and the SSL / Kerberos traces of the [🐞 Debugging the JVM](/deep-dive-java-debugging.md) deep dive |

### 🌐 Connectivity to Confluent Cloud

The playground can't recreate PrivateLink, peering or private DNS. It covers the **client side** of a connectivity
case, against a real Confluent Cloud cluster with any `ccloud/` example. Start with the five checks (DNS of the
bootstrap and of every broker, TCP, TLS and SNI, authentication) of the
[client-side checklist](/deep-dive-network-traffic?id=_6-confluent-cloud-connectivity-a-client-side-checklist):

| Question | Command or example |
| --- | --- |
| Is the TLS chain, SNI or hostname the problem? | `playground tools cert inspect --server <bootstrap host>:9092` |
| Resets, retransmissions, TLS alerts on the wire | `playground debug tcp-dump`, then `playground analyze tcp-dump` (also on a capture sent by the customer: `-f ccloud.pcap`) |
| Behaviour on a slow or lossy link | `playground debug degrade-traffic -c connect --latency 80ms --action start` |
| The client goes through a proxy | [ccloud/haproxy](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/haproxy), the `*-proxy.sh` connector examples, `playground tcp-proxy` |
| A fully managed connector loses an ACL | `playground run --ccloud-service-account`, `playground rbac acl delete --connector <c> …` |

## 🍪 Deep dives

- [🔐 Secured environments](/deep-dive-secured-environments.md): SASL, SSL, Kerberos, LDAP, RBAC, OAuth
- [🔁 Day-2 operations](/day-2-operations.md): upgrades and changes on a running cluster, cp-ansible and CFK
- [☸️ Confluent for Kubernetes](/deep-dive-cfk.md): the cfk environment, support bundles, `playground cfk`
- [🅰️ cp-ansible](/deep-dive-ansible.md): the ansible environment, the customer's inventory, `playground ansible`
- [🔑 Credentials and secrets](/deep-dive-secrets.md)
- [🐌 A slow or broken network](/deep-dive-network-traffic.md), [🏚 Break one TCP connection](/deep-dive-tcp-proxy.md)
- [🐞 Debugging the JVM](/deep-dive-java-debugging.md): SSL, Kerberos and class loading traces, testssl
- [🌤️ Fully managed connectors](/deep-dive-fully-managed.md): service accounts and ACLs on Confluent Cloud

## 🎬 Bite size sessions

- [🔐 The same example under SASL_SSL and RBAC](/sessions?id=🔐-the-same-example-under-sasl_ssl-and-rbac)
- [☸️ What is wrong in this CFK cluster?](/sessions?id=☸️-what-is-wrong-in-this-cfk-cluster)
- [🐌 A slow or broken network, on purpose](/sessions?id=🐌-a-slow-or-broken-network-on-purpose)
- [👤 A fully managed connector with a service account loses an ACL](/sessions?id=👤-a-fully-managed-connector-with-a-service-account-loses-an-acl)

## 🧪 A support case in 3 commands

"Our connector fails with `TopicAuthorizationException` since the RBAC change": run it under RBAC, remove the role
binding the customer lost, and watch the connector fail.

```bash
playground run -f "$PWD/connect/connect-filestream-sink/filestream-sink.sh" --environment rbac-sasl-plain

playground rbac role-binding delete --principal User:connectorSA --role ResourceOwner --resource 'Topic:*'

playground connector restart -c filestream-sink && playground connector wait -c filestream-sink --state FAILED --max-wait 180
```

Then `rbac role-binding create` with the same arguments, restart, and the connector is `RUNNING` again. Turn it into a
reproduction model with `playground repro bootstrap` (see [🛠 Reproduction models](/toolkit-reproduction-models.md)).
