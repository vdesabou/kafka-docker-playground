# RBAC with OAuth / OIDC (MDS with an external identity provider)

## Description

Confluent Platform with RBAC where the identity provider is OAuth / OIDC ([Keycloak](https://www.keycloak.org/)) instead
of LDAP: no encryption, SASL/OAUTHBEARER for the clients, bearer tokens for MDS and the REST APIs. This is the setup of
customers who plug Okta, Entra ID (Azure AD), Ping or Keycloak into Confluent Platform RBAC (CP 7.7+,
`confluent.metadata.server.user.store=OAUTH`).

* 1 keycloak (realm `kafka`, imported from [keycloak/kafka-realm.json](keycloak/kafka-realm.json)), the only source of
  users and groups
* 1 broker (KRaft) with the Metadata Service (MDS) on `http://localhost:8091`
* 1 KRaft controller
* 1 connect, 1 schema-registry
* 1 ksqldb-server (with `--enable-ksqldb`)

It needs CP 7.7 or later in KRaft mode (default with CP 8, `ENABLE_KRAFT=true` with CP 7.7 to 7.9): otherwise the
environment exits with code 111. Control Center is not available (it logs users in with OIDC SSO, an authorization
code flow in the browser): `--enable-control-center` is ignored with a warning.

Listeners of the broker:

| Listener | Port | SASL mechanisms |
| --- | --- | --- |
| `BROKER` | `broker:9092` | `OAUTHBEARER` for every client (tokens of Keycloak, or tokens of MDS), `PLAIN` for inter-broker traffic, the metrics reporter and the controller's MDS client (static user `admin` / `admin-secret`) |
| `HOST` | `localhost:29092` | same as `BROKER` |
| `CONTROLLER` | `controller:9093` | `PLAINTEXT` |

## How to run

```bash
playground start-environment --environment rbac-oauth
```

or run a connector example on it:

```bash
playground run -f connect/connect-datagen-source/datagen-source.sh --environment rbac-oauth
```

## Users and groups

Users are the confidential clients of the Keycloak realm `kafka`, logging in with the OAuth `client_credentials`
grant. The secret of client `<id>` is `<id>-secret`.

| Keycloak client | Keycloak groups | Used by |
| --- | --- | --- |
| `superuser` | | super user (`KAFKA_SUPER_USERS`) and `SystemAdmin` on every cluster: the `playground` CLI (MDS, Connect, Schema Registry and ksqlDB REST APIs, kafka-* tools with [client.properties](client.properties)) |
| `schemaregistry` | | Schema Registry |
| `connect` | | the Connect workers |
| `connector` | | the connectors (see below) |
| `ksqldb` | | ksqlDB |
| `client` | | Schema Registry access of `playground topic produce\|consume` |
| `alice`, `bob` | `kafka-developers` | to try group-based role bindings |
| `badapp` | | no role binding |

Tokens issued by Keycloak:

* `iss`: `http://keycloak:8080/realms/kafka` (fixed with `KC_HOSTNAME`, whatever the host used to get the token)
* `aud`: contains `kafka` (an audience mapper on each client)
* `azp`: the client id, used as principal (`User:<client id>`): `sub` is the UUID of the service account user
* `groups`: the Keycloak groups of the client (group membership mapper, `full.path` false), used for `Group:<name>`
  role bindings
* lifespan: 1 hour (`accessTokenLifespan` of the realm)

The same four settings appear on every component that validates tokens:

| Component | Keys |
| --- | --- |
| broker listeners | `listener.name.<listener>.sasl.oauthbearer.jwks.endpoint.url`, `…expected.issuer`, `…expected.audience`, `…sub.claim.name=azp`, `listener.name.<listener>.oauthbearer.sasl.server.callback.handler.class=io.confluent.kafka.server.plugins.auth.token.CompositeBearerValidatorCallbackHandler`, `listener.name.<listener>.principal.builder.class=io.confluent.kafka.security.authenticator.OAuthKafkaPrincipalBuilder`, `confluent.oauth.groups.claim.name=groups` |
| MDS | `confluent.metadata.server.user.store=OAUTH`, `confluent.metadata.server.oauthbearer.jwks.endpoint.url`, `…expected.issuer`, `…expected.audience`, `…sub.claim.name`, `…groups.claim.name` |
| Schema Registry, Connect, ksqlDB REST | `rest.servlet.initializor.classes=io.confluent.common.security.jetty.initializer.AuthenticationHandler` (ksqlDB: `ksql.authentication.plugin.class=io.confluent.ksql.security.VertxAuthenticationHandlerPlugin`), `oauthbearer.jwks.endpoint.url`, `oauthbearer.expected.issuer`, `oauthbearer.expected.audience`, `oauthbearer.sub.claim.name`, `oauthbearer.groups.claim.name` |
| their MDS client | `confluent.metadata.http.auth.credentials.provider=OAUTHBEARER`, `confluent.metadata.oauthbearer.token.endpoint.url`, `confluent.metadata.oauthbearer.login.client.id`, `confluent.metadata.oauthbearer.login.client.secret` |

Users can be changed on the running environment, without restart (it calls the admin API of Keycloak):

```bash
playground rbac user list
playground rbac user add --user carol --group kafka-developers     # Keycloak client carol, secret carol-secret
playground rbac user delete --user carol
```

A new group membership is in the next token of the client: a client that already has a token sees it when it gets a
new one.

## Connectors

`playground connector create-or-update` creates connectors as `superuser`, and adds to their config:

* `producer.override.*`, `consumer.override.*` and `admin.override.*` SASL/OAUTHBEARER keys with the Keycloak client
  `connector` (unless the config already sets their `sasl.jaas.config`): the connectors run as `User:connector`, not
  as the worker principal `User:connect`
* the same keys for the extra Kafka clients of some connectors (`confluent.topic.*`, `redo.log.consumer.*`,
  `schema.history.internal.*`, `database.history.*`, `reporter.*`)
* `<converter>.bearer.auth.credentials.source=OAUTHBEARER`, `bearer.auth.issuer.endpoint.url`,
  `bearer.auth.client.id=connector` and `bearer.auth.client.secret` for each converter with a
  `schema.registry.url` (unless it already sets `basic.auth` or `bearer.auth`). The default value converter of the
  worker (Avro) has them too

## Role bindings

The default role bindings are listed in [role-bindings.txt](role-bindings.txt), one per line, and created by
`start.sh` through the MDS REST API. See them on a running environment with:

```bash
playground rbac role-binding list
playground rbac role-binding list --principal Group:kafka-developers
```

Change permissions on the running environment with `playground rbac` (it calls the MDS REST API with a bearer token
of the Keycloak client `superuser`):

```bash
playground rbac role-binding create --principal User:badapp --role DeveloperRead --resource Topic:orders
playground rbac role-binding create --principal Group:kafka-developers --role ResourceOwner --resource Topic:orders --prefix
playground rbac acl create --principal User:badapp --operation READ --resource Topic:orders
```

Role bindings a component needs at startup can be created before connect, schema-registry and ksqlDB start with
`playground start-environment --environment rbac-oauth --rbac-role-bindings-file "$PWD/role-bindings.sh"`.

## Call the REST APIs by hand

Get a token of a Keycloak client (from the host, Keycloak is published on port 8180), then pass it as bearer token:

```bash
token=$(curl -s -d grant_type=client_credentials -d client_id=superuser -d client_secret=superuser-secret http://localhost:8180/realms/kafka/protocol/openid-connect/token | jq -r .access_token)
curl -s --oauth2-bearer "$token" http://localhost:8091/security/1.0/metadataClusterId
curl -s --oauth2-bearer "$token" http://localhost:8083/connectors
curl -s --oauth2-bearer "$token" http://localhost:8081/subjects
```

The payload of a token (middle part, base64url):

```bash
cut -d. -f2 <<< "$token" | tr '_-' '/+' | base64 -d 2> /dev/null | jq '{iss, aud, azp, groups, exp}'
```

Keycloak admin console: http://localhost:8180/admin (`admin` / `admin`).

## Good to know

* **`org.apache.kafka.sasl.oauthbearer.allowed.urls` (CP 8.x / Kafka 4.x)**: Kafka refuses any token or JWKS
  endpoint that is not listed in this JVM system property, as in [sasl-oauthbearer](../sasl-oauthbearer/README.md).
  Every JVM that logs in sets it (`KAFKA_OPTS`, `SCHEMA_REGISTRY_OPTS`, `KSQL_OPTS`). An example whose
  `docker-compose.plaintext.yml` sets `KAFKA_OPTS` on connect replaces the one of this environment: on CP 8.x, add
  `-Dorg.apache.kafka.sasl.oauthbearer.allowed.urls=http://keycloak:8080/realms/kafka/protocol/openid-connect/token,http://keycloak:8080/realms/kafka/protocol/openid-connect/certs`
  to it.
* **No basic auth**: with `user.store=OAUTH`, MDS has no user directory to check a password against, so the REST APIs
  only accept bearer tokens (`curl -u user:password` gets `401`).
* **MDS tokens still exist**: MDS signs its own tokens with [conf/keypair.pem](conf) (generated by `start.sh`), and the
  brokers and REST servers accept them next to the Keycloak ones (`CompositeBearerValidatorCallbackHandler`,
  `public.key.path`).

## Recipes for support repros

| Customer symptom | How to reproduce it here |
| --- | --- |
| `TopicAuthorizationException` for an OAuth client, "which role binding is missing?" | `playground rbac user add --user myapp`, produce with its token (`clientId="myapp" clientSecret="myapp-secret"` in a copy of [client.properties](client.properties)), then `playground rbac role-binding create --principal User:myapp --role DeveloperWrite --resource Topic:<topic>` |
| a role binding on a group does not apply | `Group:kafka-developers` bindings apply to `alice` and `bob`. Remove the `groups` mapper of a client in the Keycloak admin console, or change `KAFKA_CONFLUENT_OAUTH_GROUPS_CLAIM_NAME` of the brokers in an override: the group is no longer seen. Groups with `full.path` true are `Group:/kafka-developers` |
| the principal is a UUID in role bindings / audit logs | set `KAFKA_LISTENER_NAME_BROKER_SASL_OAUTHBEARER_SUB_CLAIM_NAME` (and the `*_OAUTHBEARER_SUB_CLAIM_NAME` of MDS and the REST servers) to `sub` in an override: the principal becomes `User:<uuid of the service account>` |
| REST API answers `401` | the token is from another issuer or audience (`*_OAUTHBEARER_EXPECTED_ISSUER`, `*_OAUTHBEARER_EXPECTED_AUDIENCE`), expired, or sent as basic auth |
| a connector fails with `TopicAuthorizationException` while the worker works | the connector runs as `User:connector` (`*.override.sasl.jaas.config`): `playground rbac role-binding delete --principal User:connector --role ResourceOwner --resource Topic:*` then bind it on the topics of the connector only |
| the IdP rotated its signing keys | `docker rm -f keycloak` then `playground container recreate`: the new Keycloak has new keys, the first login fails with `invalid_token` and the brokers refresh the JWKS |
| `Allowed URL list: []` after an upgrade to CP 8 | remove `-Dorg.apache.kafka.sasl.oauthbearer.allowed.urls=…` from `KAFKA_OPTS` of a component |
