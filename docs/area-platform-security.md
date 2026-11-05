# 🛡️ Platform, security and Cloud infra

For cases about **Confluent for Kubernetes** (CRs, support bundles, upgrades, KRaft migration), **security**
(SASL, SSL / mTLS, Kerberos, LDAP, RBAC, OAuth / OIDC, ACLs, secrets, audit logs), **certificates**, and the
**client side of Confluent Cloud connectivity**. Every example runs under the customer's security setup with one flag:
the CLI then talks to the secured cluster for you.

## 🚀 5 commands to try

```bash
# the same example, under the customer's security: sasl-plain, sasl-scram, sasl-ssl, 2way-ssl, sasl-oauthbearer,
# kerberos, ssl_kerberos, ldap-sasl-plain, ldap-authorizer-sasl-plain, rbac-sasl-plain, cfk, cfk-rbac…
playground run -f "$PWD/connect/connect-filestream-sink/filestream-sink.sh" --environment rbac-sasl-plain

playground container get-properties -c broker                  # what the component really loaded (listeners, JAAS, authorizer)
playground rbac role-binding list --principal User:connectorSA  # who can do what
playground tools cert inspect --server broker:9092              # chain, SANs, expiry, what a client would trust
playground analyze logs --sample cfk_bundle --output-dir /tmp/cfk-bundle   # a CFK support bundle digest, no environment needed
```

## ❓ Your question, the answer

### ☸️ Confluent for Kubernetes

| Question | Command or example |
| --- | --- |
| Run CP on Kubernetes like the customer | `--environment cfk` (or `cfk-rbac`, with OpenLDAP and role bindings) on any `connect/` example, `CFK_VERSION=<version>` for another operator version; CFK against Confluent Cloud: [ccloud/confluent-for-kubernetes](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/confluent-for-kubernetes) |
| "Here is the support bundle" | `playground analyze logs -f <bundle> --output-dir /tmp/cfk-reports`: rollout issues, KRaft migration, plugin install, `--problem "<what the customer says>"` for a verdict |
| "Here is a new bundle, what changed?" | `playground analyze logs -f <older bundle> -f <newer bundle>` |
| The customer's `Connector` CR doesn't behave | `playground connector create-or-update` / `validate` / `diff` read CFK CRs directly |
| Which operator code logs this error? | `playground debug cfk sourcecode --bundle <bundle> --grep "<message>"` |
| What would a bundle of my repro look like? | `playground debug cfk generate-bundle`, then `analyze logs` on it |

### 🔐 Security

| Question | Command or example |
| --- | --- |
| Works in dev, fails in the SSL cluster | the same example with `--environment sasl-ssl` (or `2way-ssl`), `connector create-or-update --dry-run` for the security keys the config must carry |
| `TopicAuthorizationException` with RBAC | `--environment rbac-sasl-plain`, `rbac role-binding delete --principal User:connectorSA …` to reproduce it on purpose, `--rbac-role-bindings-file` to start with the customer's bindings |
| ACLs: centralized (MDS) or Kafka ACLs, DENY vs role binding | `playground rbac acl create\|list\|delete` (`--kafka-acls` for Kafka ACLs), example [other/rbac-centralized-acls](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/rbac-centralized-acls) |
| OAuth / OIDC: `invalid_token`, key rotation, issuer or audience mismatch | `--environment sasl-oauthbearer` (Keycloak), recipes in [environment/sasl-oauthbearer](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/sasl-oauthbearer) |
| Kerberos principal or ticket errors | `--environment kerberos` (or `ssl_kerberos`) |
| Users and groups in LDAP | `--environment ldap-sasl-plain`, `ldap-authorizer-sasl-plain`, examples [other/ldap-authorizer-with-ldap-failover](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/ldap-authorizer-with-ldap-failover), [other/rbac-with-azure-ad](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/rbac-with-azure-ad) |
| `PKIX path building failed`, expired certificate, hostname mismatch | `playground tools cert inspect --file <certificate or keystore> --truststore <truststore> --hostname <host>` (or `--server <host:port>`) |
| JKS ↔ PKCS12 ↔ PEM, Kafka PEM properties | `playground tools cert convert --to pkcs12\|jks\|pem\|der\|properties` |
| Certificates for a repro | `playground tools cert create --output-folder <dir>` |
| Audit logs, authentication logs, secrets | examples [other/audit-logs](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/audit-logs), [other/capture-authentication-logs](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/capture-authentication-logs), [other/secrets-management](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/secrets-management), [other/connect-secret-registry](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/connect-secret-registry) |
| Security plugins of Schema Registry and REST Proxy, Control Center with LDAP | [other/schema-registry-security-plugin](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/schema-registry-security-plugin), [other/rest-proxy-security-plugin](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/rest-proxy-security-plugin), [other/control-center-ldap-auth](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/control-center-ldap-auth) |
| SSL handshake or Kerberos details in the JVM | `playground debug java-debug` and the SSL / Kerberos traces of the [🐞 Debugging the JVM](/deep-dive-java-debugging.md) deep dive |

### 🌐 Connectivity to Confluent Cloud

The playground can't recreate PrivateLink, peering or private DNS. It covers the **client side** of a connectivity
case, against a real Confluent Cloud cluster with any `ccloud/` example:

| Question | Command or example |
| --- | --- |
| Is the TLS chain, SNI or hostname the problem? | `playground tools cert inspect --server <bootstrap host>:9092` |
| Resets, retransmissions, TLS alerts on the wire | `playground debug tcp-dump`, then `playground analyze tcp-dump` |
| Behaviour on a slow or lossy link | `playground debug degrade-traffic -c connect --latency 80ms --action start` |
| The client goes through a proxy | [ccloud/haproxy](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/haproxy), the `*-proxy.sh` connector examples, `playground tcp-proxy` |
| A fully managed connector loses an ACL | `playground run --ccloud-service-account`, `playground rbac acl delete --connector <c> …` |

## 🍪 Deep dives

- [🔐 Secured environments](/deep-dive-secured-environments.md): SASL, SSL, Kerberos, LDAP, RBAC, OAuth
- [☸️ Confluent for Kubernetes](/deep-dive-cfk.md): the cfk environment, support bundles
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
