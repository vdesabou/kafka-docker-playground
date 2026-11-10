# mTLS: a certificate renewal breaks the ACLs (`ssl.principal.mapping.rules`)

## Description

With mTLS (`ssl.client.auth=required`), the broker turns the distinguished name (DN) of the client certificate
into a principal with `ssl.principal.mapping.rules`, and the ACLs are written for that principal. The rules are tried
in order, and the first one that matches wins. `DEFAULT` keeps the whole DN.

A frequent support case: **the certificate of an application is renewed, and the application gets
`TopicAuthorizationException`**. The new certificate has the same CN and comes from the same CA, so the TLS handshake
works, but another part of the DN changed (here `OU=TEST` → `OU=PROD`). The rule no longer matches, the principal
falls back to `DEFAULT`, and the ACLs of the application don't apply to it any more.

The example runs on [environment/2way-ssl](../../environment/2way-ssl/README.md) with the KRaft `StandardAuthorizer`
(`docker-compose.2way-ssl.yml`) and the rule of the environment:

```properties
ssl.principal.mapping.rules=RULE:^CN=(.*?),OU=TEST.*$/$1/,DEFAULT
```

| Certificate | Distinguished name | Principal |
| --- | --- | --- |
| `orders-app` | `CN=orders-app,OU=TEST,O=CONFLUENT,L=PaloAlto,ST=Ca,C=US` | `User:orders-app` |
| `orders-app-renewed` | `CN=orders-app,OU=PROD,O=CONFLUENT,L=PaloAlto,ST=Ca,C=US` | `User:CN=orders-app,OU=PROD,O=CONFLUENT,L=PaloAlto,ST=Ca,C=US` (`DEFAULT`) |

Both certificates are signed by the CA of the environment (`create-client-cert.bash`, in the connect image).

The example checks:

1. with an ACL `ALLOW WRITE` on `Topic:orders` for `User:orders-app`, the `orders-app` certificate can write
2. the renewed certificate gets `TopicAuthorizationException`, and the broker log shows the principal it computed:
   the full DN (`kafka.authorizer.logger` at `INFO`)
3. workaround without broker change: an ACL on the full DN
4. fix: a rule that matches both certificates. `ssl.principal.mapping.rules` is **not** a dynamic broker config
   (`playground broker config set` refuses it): the broker is recreated with
   `playground container set-environment-variables`. Then both certificates are `User:orders-app` again

## How to run

```bash
playground run -f other/mtls-principal-mapping/mtls-principal-mapping.sh
```

What step 2 prints: the DN of the renewed certificate (`playground tools cert inspect`), then the request the broker
denied, with the principal it computed (the idempotent producer is refused at `InitProducerId`, before any record):

```text
   #1 CN=orders-app,OU=PROD,O=CONFLUENT,L=PaloAlto,ST=Ca,C=US
✅ the certificate orders-app-renewed is not authorized to write to orders (TopicAuthorizationException)
INFO Principal = User:CN=orders-app,OU=PROD,O=CONFLUENT,L=PaloAlto,ST=Ca,C=US is Denied operation = WRITE from host = 172.27.0.7 on resource = Topic:UNKNOWN:NONE for request = InitProducerId with resourceRefCount = 0 based on rule DefaultDeny (kafka.authorizer.logger)
```

And step 4, `playground broker config set` on the rule:

```text
org.apache.kafka.common.errors.InvalidRequestException: Cannot update these configs dynamically: [ssl.principal.mapping.rules]
```

## Commands

```bash
# the DN of a certificate
playground tools cert inspect --file other/mtls-principal-mapping/security/kafka.orders-app-renewed.keystore.jks --password confluent

# the principal the broker computed for a denied request
playground container logs -c broker --grep "is Denied" --no-follow --tail 2000

# change the rule (not dynamic: the broker is recreated). $$ is the docker compose escape of $
playground container set-environment-variables -c broker --env 'KAFKA_SSL_PRINCIPAL_MAPPING_RULES: RULE:^CN=(.*?),OU=(TEST|PROD),.*$$/$$1/,DEFAULT'
playground container get-properties -c broker | grep ssl.principal.mapping.rules
```

## Support recipes

| Customer situation | Change in the example |
| --- | --- |
| "it broke after the certificates were renewed" | ask for the old and the new DN (`keytool -list -v`, `openssl x509 -noout -subject`), put them in `create_client_cert`, and the customer's `ssl.principal.mapping.rules` in `docker-compose.2way-ssl.yml` |
| a rule with `/L` or `/U` (lower or upper case) | the ACL must use the converted case: `User:orders-app`, not `User:ORDERS-APP` |
| the DN attributes in another order, or with spaces (`CN=orders-app, OU=TEST`) | the rule is a regular expression on the DN as Java prints it (RFC 2253: no space after the commas): check it against the DN the broker logs |
| SASL_SSL with mTLS on the same listener | the principal comes from SASL, not from the certificate: `ssl.principal.mapping.rules` doesn't apply |
