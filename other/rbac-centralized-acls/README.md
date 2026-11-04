# MDS centralized ACLs with RBAC

## Description

On a cluster with RBAC ([environment/rbac-sasl-plain](../../environment/rbac-sasl-plain/README.md)), ACLs can be
stored in two places, both enforced by the `ConfluentServerAuthorizer`:

| Store | Created with | Stored in | Access rule provider |
| --- | --- | --- | --- |
| **centralized** ACLs | the MDS REST API (`confluent iam acl`, `playground rbac acl create`) | the `_confluent-metadata-auth` topic | `CONFLUENT` |
| regular Kafka ACLs | `kafka-acls` (`playground rbac acl create --kafka-acls`) | ZooKeeper, or the KRaft metadata log | `ZK_ACL` / `KRAFT_ACL` |

The broker of the environment sets `confluent.authorizer.access.rule.providers=CONFLUENT,ZK_ACL` (`KRAFT_ACL` with
KRaft) and `confluent.authorizer.group.provider=RBAC`: groups come from LDAP.

The example checks, as LDAP users with no role binding (`appSA`, member of the `KafkaDevelopers` group, and
`badapp`, in no group):

1. `User:appSA` gets `TopicAuthorizationException` on `acl-demo`, then can write once a centralized ACL allows it
2. `playground rbac acl list` shows the store of each ACL, but **`kafka-acls --list` does not show centralized ACLs**
3. a centralized **DENY ACL wins over a role binding** (`DeveloperWrite`), and deleting it restores the access
4. a centralized ACL on an **LDAP group** (`Group:KafkaDevelopers`) applies to its members only, and a regular
   Kafka ACL for `User:badapp` is enforced together with the centralized ones

## How to run

```bash
playground run -f other/rbac-centralized-acls/centralized-acls.sh
```

## Commands

```bash
# centralized ACL (MDS REST API)
playground rbac acl create --principal User:appSA --operation WRITE --operation DESCRIBE --resource Topic:acl-demo
# DENY
playground rbac acl create --principal User:appSA --operation WRITE --resource Topic:acl-deny --deny
playground rbac acl delete --principal User:appSA --operation WRITE --resource Topic:acl-deny --deny
# LDAP group
playground rbac acl create --principal Group:KafkaDevelopers --operation WRITE --operation DESCRIBE --resource Topic:acl-group
# regular Kafka ACL (kafka-acls)
playground rbac acl create --principal User:badapp --operation WRITE --operation DESCRIBE --resource Topic:acl-group --kafka-acls
# both stores
playground rbac acl list
```

Produce as another LDAP user than the `admin` user of the CLI:

```bash
playground topic produce -t acl-demo --nb-messages 1 --producer-property 'sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="appSA" password="appSA";' << 'EOF'
{"id": %g}
EOF
```

## Output

`playground rbac acl list` at the end of the run (CP 8.4.0):

```text
PRINCIPAL              PERMISSION  OPERATION  RESOURCE         PATTERN  HOST  STORE
Group:KafkaDevelopers  ALLOW       DESCRIBE   Topic:acl-group  LITERAL  *     centralized
User:appSA             ALLOW       WRITE      Topic:acl-demo   LITERAL  *     centralized
Group:KafkaDevelopers  ALLOW       WRITE      Topic:acl-group  LITERAL  *     centralized
User:appSA             ALLOW       DESCRIBE   Topic:acl-demo   LITERAL  *     centralized
User:badapp            ALLOW       WRITE      Topic:acl-group  LITERAL  *     kafka-acls
User:badapp            ALLOW       DESCRIBE   Topic:acl-group  LITERAL  *     kafka-acls
```

while `kafka-acls --list --principal User:appSA` only prints its header, the two centralized ACLs of `appSA` are
not there:

```text
ACLs for principal `User:appSA`
```

The ACLs take effect within a few seconds (the brokers read them from `_confluent-metadata-auth`): the example
retries each check for up to 30 seconds.
