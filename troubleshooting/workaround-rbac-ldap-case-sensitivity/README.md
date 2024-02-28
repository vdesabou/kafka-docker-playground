# Testing a potential workaround for RBAC/LDAP case sensitivity issue

**TL;DR**: it does not work 😃

When using RBAC, users of Confluent Platform need to provide case-sensitive usernames when logging in with MDS.

This is known issue which is documented:

```
The user ID specified in group role bindings is case-specific, and must match the case specified in the AD record
```

The cause is that LDAP is not case sensitive but MDS and role bindings are case sensitive.

Unfortunately, at this time there is no known workaround.
We recommend checking the LDAP directory case sensitivity matches the role bindings for users and groups, to avoid unexpected authorization.

Here is an attempt of a potential workaround:

A workaround consisting in defining group-based role bindings instead of user-based role bindings.
Check whether creating group-level role bindings would actually solve the case sensitivity issue. This needs to be tested both in [user search mode](https://docs.confluent.io/platform/current/security/ldap-authorizer/configuration.html#sample-configuration-for-user-based-search) and [group search mode](https://docs.confluent.io/platform/current/security/ldap-authorizer/configuration.html#sample-configuration-for-group-based-search).


The current behaviour is the following:

* User logs in with a case which does not match the LDAP entry
* User is not able to see any clusters in Control Center, nor perform any operation on the Kafka cluster

The end goal is the following:

* User logs in with a case which does not match the LDAP entry (as a reminder, LDAP authentication is not case sensitive)
* User is able to see the cluster on which the group permissions have been set, and is able to perform operations, say a write in a Kafka topic


## How to run

Simply run:

```
$ just use <playground run> command and search for start-with-group-based-search.sh in this folder
```

or

```
$ just use <playground run> command and search for start-with-user-based-search.sh in this folder
```

## Details of what the script is doing

Create role binding for group `KafkaDevelopers`

```bash
KAFKA_DEVELOPPERS_GROUP="Group:KafkaDevelopers"
confluent iam rolebinding create \
    --principal "$KAFKA_DEVELOPPERS_GROUP"  \
    --role SystemAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal "$KAFKA_DEVELOPPERS_GROUP" \
    --role SystemAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal "$KAFKA_DEVELOPPERS_GROUP" \
    --role SystemAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --connect-cluster-id $CONNECT

confluent iam rolebinding create \
    --principal "$KAFKA_DEVELOPPERS_GROUP" \
    --role SystemAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --ksql-cluster-id $KSQLDB
```

User `alice` is part of this group:

```
dn: cn=KafkaDevelopers,ou=groups,{{ LDAP_BASE_DN }}
changetype: modify
add: memberuid
memberuid: cn=alice,ou=users,{{ LDAP_BASE_DN }}
```

For user search based, I've added `memberOf`

```
dn: cn=alice,ou=users,{{ LDAP_BASE_DN }}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: alice
sn: LookingGlass
givenName: Alice
cn: alice
displayName: Alice LookingGlass
uidNumber: 10000
gidNumber: 5000
userPassword: alice-secret
gecos: alice
loginShell: /bin/bash
homeDirectory: /home/alice
memberOf: cn=KafkaDevelopers,ou=groups,{{ LDAP_BASE_DN }}
```

Config for group based search:

```yml
KAFKA_LDAP_SEARCH_MODE: GROUPS
KAFKA_LDAP_GROUP_SEARCH_BASE: ou=groups,dc=confluentdemo,dc=io
KAFKA_LDAP_GROUP_NAME_ATTRIBUTE: cn
KAFKA_LDAP_GROUP_MEMBER_ATTRIBUTE: memberUid
KAFKA_LDAP_GROUP_OBJECT_CLASS: posixGroup
KAFKA_LDAP_GROUP_MEMBER_ATTRIBUTE_PATTERN: cn=(.*),ou=users,dc=confluentdemo,dc=io
KAFKA_LDAP_USER_SEARCH_BASE: ou=users,dc=confluentdemo,dc=io
KAFKA_LDAP_USER_NAME_ATTRIBUTE: uid
KAFKA_LDAP_USER_OBJECT_CLASS: inetOrgPerson
```

Config for user based search:

```yml
KAFKA_LDAP_SEARCH_MODE: USERS
KAFKA_LDAP_USER_SEARCH_BASE: ou=users,dc=confluentdemo,dc=io
KAFKA_LDAP_USER_NAME_ATTRIBUTE: uid
KAFKA_LDAP_USER_OBJECT_CLASS: inetOrgPerson
KAFKA_LDAP_USER_MEMBEROF_ATTRIBUTE: memberOf
KAFKA_LDAP_USER_MEMBEROF_ATTRIBUTE_PATTERN: "cn=(.*),ou=groups,.*"
```

To verify it does not work, connect to Control Center at [http://127.0.0.1:9021](http://127.0.0.1:9021]):

* with `alice`/`alice-secret`: you can login and see the cluster
* with `ALICE`/`alice-secret`: you can login and but not see the cluster
