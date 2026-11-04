# SASL/OAUTHBEARER (OAuth 2.0 / OIDC with Keycloak)

## Description

This is a deployment with no encryption but with SASL/OAUTHBEARER authentication (OIDC, KIP-768), with
[Keycloak](https://www.keycloak.org/) as identity provider:

* 1 keycloak (realm `kafka`, imported from [keycloak/kafka-realm.json](keycloak/kafka-realm.json))
* 1 broker (KRaft controller, or zookeeper with CP 7.x)
* 1 connect
* 1 schema-registry
* 1 ksqldb-server (with `--enable-ksqldb`)
* 1 control-center (with `--enable-control-center`)

It needs CP 7.4 or later (Apache Kafka 3.4, where `OAuthBearerLoginCallbackHandler` and
`OAuthBearerValidatorCallbackHandler` moved to `org.apache.kafka.common.security.oauthbearer`): with an older
`--tag`, the environment exits with code 111.

Every component logs in with the OAuth `client_credentials` grant, as its own Keycloak client:

| Keycloak client | Secret | Used by | Principal seen by the brokers |
| --- | --- | --- | --- |
| `broker` | `broker-secret` | inter-broker listener | `User:broker` |
| `connect` | `connect-secret` | the Connect workers (and their producers / consumers) | `User:connect` |
| `schemaregistry` | `schemaregistry-secret` | Schema Registry | `User:schemaregistry` |
| `ksqldb` | `ksqldb-secret` | ksqlDB | `User:ksqldb` |
| `controlcenter` | `controlcenter-secret` | Control Center | `User:controlcenter` |
| `client` | `client-secret` | `playground topic produce\|consume`, the kafka-* tools, the `confluent.topic.*` / `reporter.*` / `*.history.*` keys that `playground connector create-or-update` adds | `User:client` |

Tokens issued by Keycloak:

* `iss`: `http://keycloak:8080/realms/kafka` (fixed with `KC_HOSTNAME`, whatever the host used to get the token)
* `aud`: contains `kafka` (an audience mapper on each client)
* `azp`: the client id. `sub` is the UUID of the service account user, so the brokers take the principal from `azp`
  (`sasl.oauthbearer.sub.claim.name=azp`)
* lifespan: 1 hour (`accessTokenLifespan` of the realm)

Brokers validate the tokens with:

```properties
sasl.oauthbearer.jwks.endpoint.url=http://keycloak:8080/realms/kafka/protocol/openid-connect/certs
sasl.oauthbearer.expected.issuer=http://keycloak:8080/realms/kafka
sasl.oauthbearer.expected.audience=kafka
sasl.oauthbearer.sub.claim.name=azp
listener.name.broker.oauthbearer.sasl.server.callback.handler.class=org.apache.kafka.common.security.oauthbearer.OAuthBearerValidatorCallbackHandler
```

Client config ([client.properties](client.properties), mounted as `/tmp/client.properties` in broker, connect and
schema-registry):

```properties
sasl.mechanism=OAUTHBEARER
security.protocol=SASL_PLAINTEXT
sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginCallbackHandler
sasl.oauthbearer.token.endpoint.url=http://keycloak:8080/realms/kafka/protocol/openid-connect/token
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required \
  clientId="client" \
  clientSecret="client-secret";
```

The REST endpoints (Connect, Schema Registry, ksqlDB) are not authenticated, as in `sasl-plain`.

Keycloak admin console: http://localhost:8180/admin (`admin` / `admin`).

## How to run

Simply run:

```
$ just use <playground run> command and search for start.sh in this folder
```

or run a connector example on it:

```bash
playground run -f connect/connect-http-sink/http_no_auth.sh --environment sasl-oauthbearer
```

## Good to know

* **`org.apache.kafka.sasl.oauthbearer.allowed.urls` (CP 8.x / Kafka 4.x)**: Kafka refuses any token or JWKS
  endpoint that is not listed in this JVM system property, and the list is empty by default. Every JVM that logs in
  sets it: `KAFKA_OPTS` on brokers and connect (the kafka-* tools started with `docker exec` inherit it),
  `SCHEMA_REGISTRY_OPTS` (connect also has it, for `kafka-avro-console-producer`), `KSQL_OPTS`, `CONTROL_CENTER_OPTS`,
  plus `KAFKA_OPTS` on schema-registry, ksqldb-server and control-center for the `ub kafka-ready` check of the
  images. Without it, the client fails with:

  ```text
  org.apache.kafka.common.config.ConfigException: Invalid value http://keycloak:8080/realms/kafka/protocol/openid-connect/token for configuration sasl.oauthbearer.token.endpoint.url: The URL cannot be accessed due to restrictions. Allowed URL list: []. Update the system property 'org.apache.kafka.sasl.oauthbearer.allowed.urls' to allow the URL to be accessed.
  ```

  ⚠️ An example whose `docker-compose.plaintext.yml` sets `KAFKA_OPTS` on connect replaces the one of this
  environment: on CP 8.x, add
  `-Dorg.apache.kafka.sasl.oauthbearer.allowed.urls=http://keycloak:8080/realms/kafka/protocol/openid-connect/token,http://keycloak:8080/realms/kafka/protocol/openid-connect/certs`
  to it.

* **`clientId` / `clientSecret` JAAS options are deprecated with Kafka 4.1+ (CP 8.1+)**: the clients log
  `WARN The OAuth JAAS option clientSecret was configured in sasl.jaas.config, but that JAAS option is deprecated and will be removed. Please update your configuration to use the sasl.oauthbearer.client.credentials.client.secret configuration instead.`
  The environment keeps the JAAS options, which work from CP 7.4 to 8.x. The new keys are
  `sasl.oauthbearer.client.credentials.client.id` and `sasl.oauthbearer.client.credentials.client.secret`.

## Recipes for support repros

| Customer symptom | How to reproduce it here |
| --- | --- |
| `SaslAuthenticationException: {"status":"invalid_token"}` right after the IdP rotated its signing keys | `docker rm -f keycloak` then `playground container recreate`: the new Keycloak has new keys. The first login fails (broker log: `UnresolvableKeyException: Unable to find a suitable verification key for JWS w/ header {... "kid" : "..."}`), the broker refreshes the JWKS (`OAuth JWKS refresh of http://keycloak:8080/realms/kafka/protocol/openid-connect/certs complete`) and the next login succeeds |
| token expiry, re-authentication, `connections.max.reauth.ms` | lower `accessTokenLifespan` in `keycloak/kafka-realm.json` (seconds), then `docker rm -f keycloak` + `playground container recreate` (the realm is only imported by a new container). Set `KAFKA_CONNECTIONS_MAX_REAUTH_MS` on the brokers in an override to force re-authentication of long-lived connections |
| issuer or audience mismatch (`sasl.oauthbearer.expected.issuer` / `expected.audience`) | change `KAFKA_SASL_OAUTHBEARER_EXPECTED_ISSUER` or `KAFKA_SASL_OAUTHBEARER_EXPECTED_AUDIENCE` of the brokers in an override, the clients then fail to authenticate |
| principal is a UUID in ACLs / audit logs | remove `KAFKA_SASL_OAUTHBEARER_SUB_CLAIM_NAME` from the brokers: the principal becomes the `sub` claim (`User:<uuid of the service account>`) instead of the client id |
| `Allowed URL list: []` after an upgrade to CP 8 | remove `-Dorg.apache.kafka.sasl.oauthbearer.allowed.urls=…` from `KAFKA_OPTS` of a component |
| see what is in a token | `docker exec connect curl -s -d grant_type=client_credentials -d client_id=connect -d client_secret=connect-secret http://keycloak:8080/realms/kafka/protocol/openid-connect/token \| jq -r .access_token`, then decode the middle part (base64url) |
