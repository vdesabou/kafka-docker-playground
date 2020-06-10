# Audit logs

## Objective

Quickly test [Audit logs](https://docs.confluent.io/current/security/audit-logs.html#audit-logs).


## How to run

Simply run:

```
$ ./start-rbac-sasl-plain.sh
```

## Details of what the script is doing

[RBAC environment](../../environment/rbac-sasl-plain) is used, so it has already:

```yml
  broker:
    environment:
      KAFKA_AUTHORIZER_CLASS_NAME: io.confluent.kafka.security.authorizer.ConfluentServerAuthorizer
```

This test has following override configuration:

```yml
  broker:
    environment:
      KAFKA_CONFLUENT_SECURITY_EVENT_ROUTER_CONFIG: "{\"routes\":{\"crn:///kafka=*/group=*\":{\"consume\":{\"allowed\":\"confluent-audit-log-events\",\"denied\":\"confluent-audit-log-events\"}},\"crn:///kafka=*/topic=*\":{\"produce\":{\"allowed\":\"confluent-audit-log-events\",\"denied\":\"confluent-audit-log-events\"},\"consume\":{\"allowed\":\"confluent-audit-log-events\",\"denied\":\"confluent-audit-log-events\"}}},\"destinations\":{\"topics\":{\"confluent-audit-log-events\":{\"retention_ms\":7776000000}}},\"default_topics\":{\"allowed\":\"confluent-audit-log-events\",\"denied\":\"confluent-audit-log-events\"},\"excluded_principals\":[\"User:kafka\",\"User:ANONYMOUS\"]}"
```

which is:

```json
{
    "default_topics": {
        "allowed": "confluent-audit-log-events",
        "denied": "confluent-audit-log-events"
    },
    "destinations": {
        "topics": {
            "confluent-audit-log-events": {
                "retention_ms": 7776000000
            }
        }
    },
    "excluded_principals": [
        "User:kafka",
        "User:ANONYMOUS"
    ],
    "routes": {
        "crn:///kafka=*/group=*": {
            "consume": {
                "allowed": "confluent-audit-log-events",
                "denied": "confluent-audit-log-events"
            }
        },
        "crn:///kafka=*/topic=*": {
            "consume": {
                "allowed": "confluent-audit-log-events",
                "denied": "confluent-audit-log-events"
            },
            "produce": {
                "allowed": "confluent-audit-log-events",
                "denied": "confluent-audit-log-events"
            }
        }
    }
}
```

Checking messages from topic `confluent-audit-log-events`

```bash
$ docker exec -i connect kafka-console-consumer --bootstrap-server broker:9092 --topic confluent-audit-log-events --consumer.config /etc/kafka/secrets/client_sasl_plain.config --from-beginning --max-messages 5
```

Results:

```json
{
    "confluentRouting": {
        "route": "confluent-audit-log-events"
    },
    "data": {
        "authenticationInfo": {
            "principal": "User:admin"
        },
        "authorizationInfo": {
            "granted": true,
            "operation": "Read",
            "patternType": "LITERAL",
            "resourceName": "_confluent-metadata-auth",
            "resourceType": "Topic",
            "superUserAuthorization": true
        },
        "methodName": "kafka.FetchConsumer",
        "request": {
            "client_id": "_confluent-metadata-auth-consumer-1",
            "correlation_id": "456"
        },
        "requestMetadata": {
            "client_address": "/192.168.176.4"
        },
        "resourceName": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg/topic=_confluent-metadata-auth",
        "serviceName": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg"
    },
    "datacontenttype": "application/json",
    "id": "7a1bd9a9-7923-4550-8603-dc48fbc5772f",
    "source": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg",
    "specversion": "0.3",
    "subject": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg/topic=_confluent-metadata-auth",
    "time": "2020-03-31T10:00:03.532Z",
    "type": "io.confluent.kafka.server/authorization"
}

{
    "confluentRouting": {
        "route": "confluent-audit-log-events"
    },
    "data": {
        "authenticationInfo": {
            "principal": "User:admin"
        },
        "authorizationInfo": {
            "granted": true,
            "operation": "Describe",
            "patternType": "LITERAL",
            "resourceName": "_confluent-license",
            "resourceType": "Topic",
            "superUserAuthorization": true
        },
        "methodName": "kafka.ListOffsets",
        "request": {
            "client_id": "_confluent-license-consumer-1",
            "correlation_id": "5"
        },
        "requestMetadata": {
            "client_address": "/192.168.176.4"
        },
        "resourceName": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg/topic=_confluent-license",
        "serviceName": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg"
    },
    "datacontenttype": "application/json",
    "id": "04ed8bf2-e3b9-4dbd-b738-f7eb8c923255",
    "source": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg",
    "specversion": "0.3",
    "subject": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg/topic=_confluent-license",
    "time": "2020-03-31T10:00:03.540Z",
    "type": "io.confluent.kafka.server/authorization"
}

{
    "confluentRouting": {
        "route": "confluent-audit-log-events"
    },
    "data": {
        "authenticationInfo": {
            "principal": "User:admin"
        },
        "authorizationInfo": {
            "granted": true,
            "operation": "Describe",
            "patternType": "LITERAL",
            "resourceName": "_confluent-license",
            "resourceType": "Topic",
            "superUserAuthorization": true
        },
        "methodName": "kafka.ListOffsets",
        "request": {
            "client_id": "_confluent-license-consumer-1",
            "correlation_id": "6"
        },
        "requestMetadata": {
            "client_address": "/192.168.176.4"
        },
        "resourceName": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg/topic=_confluent-license",
        "serviceName": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg"
    },
    "datacontenttype": "application/json",
    "id": "f42dddf8-1af9-4a5a-87fb-4abad389ddf2",
    "source": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg",
    "specversion": "0.3",
    "subject": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg/topic=_confluent-license",
    "time": "2020-03-31T10:00:03.550Z",
    "type": "io.confluent.kafka.server/authorization"
}

{
    "confluentRouting": {
        "route": "confluent-audit-log-events"
    },
    "data": {
        "authenticationInfo": {
            "principal": "User:admin"
        },
        "authorizationInfo": {
            "granted": true,
            "operation": "Read",
            "patternType": "LITERAL",
            "resourceName": "_confluent-license",
            "resourceType": "Topic",
            "superUserAuthorization": true
        },
        "methodName": "kafka.FetchConsumer",
        "request": {
            "client_id": "_confluent-license-consumer-1",
            "correlation_id": "7"
        },
        "requestMetadata": {
            "client_address": "/192.168.176.4"
        },
        "resourceName": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg/topic=_confluent-license",
        "serviceName": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg"
    },
    "datacontenttype": "application/json",
    "id": "f5100e3b-0b55-4ce8-8d94-907617bcfd91",
    "source": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg",
    "specversion": "0.3",
    "subject": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg/topic=_confluent-license",
    "time": "2020-03-31T10:00:03.573Z",
    "type": "io.confluent.kafka.server/authorization"
}

{
    "confluentRouting": {
        "route": "confluent-audit-log-events"
    },
    "data": {
        "authenticationInfo": {
            "principal": "User:admin"
        },
        "authorizationInfo": {
            "granted": true,
            "operation": "Read",
            "patternType": "LITERAL",
            "resourceName": "_confluent-metadata-auth",
            "resourceType": "Topic",
            "superUserAuthorization": true
        },
        "methodName": "kafka.FetchConsumer",
        "request": {
            "client_id": "_confluent-metadata-auth-consumer-1",
            "correlation_id": "460"
        },
        "requestMetadata": {
            "client_address": "/192.168.176.4"
        },
        "resourceName": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg/topic=_confluent-metadata-auth",
        "serviceName": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg"
    },
    "datacontenttype": "application/json",
    "id": "7ab5db76-543d-4a43-9862-1f135b9638c0",
    "source": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg",
    "specversion": "0.3",
    "subject": "crn:///kafka=qL97v6UYSyOOwnIPIHurGg/topic=_confluent-metadata-auth",
    "time": "2020-03-31T10:00:05.591Z",
    "type": "io.confluent.kafka.server/authorization"
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021]), use `superUser`/`superUser`to login.

You may also log in as [other users](https://github.com/confluentinc/cp-demo/tree/5.4.1-post/scripts//security/ldap_users) to learn how each user’s view changes depending on their permissions.
