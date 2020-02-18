# ServiceNow Source connector (using Confluent Cloud)

## Objective

Quickly test [ServiceNow Source](https://docs.confluent.io/current/connect/kafka-connect-servicenow/source-connector/index.html#servicenow-source-connector-for-cp) connector using Confluent Cloud


## Register a test account

Go to [ServiceNow developer portal](https://developer.servicenow.com) and register an account.
Click on `Manage`->`Instance` and register for a New-York instance. After some time (about one hour in my case) on the waiting list, you should receive an email with details of your test instance.


## How to run

Simply run:

```
$ ./servicenow-source.sh <SERVICENOW_URL> <SERVICENOW_PASSWORD>
```

Note: you can also export these values as environment variable

## Details of what the script is doing

Creating ServiceNow Source connector

```bash
$ docker exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e CLOUD_KEY="$CLOUD_KEY" -e CLOUD_SECRET="$CLOUD_SECRET" -e SERVICENOW_URL="$SERVICENOW_URL" -e SERVICENOW_PASSWORD="$SERVICENOW_PASSWORD" -e TODAY="$TODAY" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.servicenow.ServiceNowSourceConnector",
                "kafka.topic": "topic-servicenow",
                "servicenow.url": "'"$SERVICENOW_URL"'",
                "tasks.max": "1",
                "servicenow.table": "incident",
                "servicenow.user": "admin",
                "servicenow.password": "'"$SERVICENOW_PASSWORD"'",
                "servicenow.since": "'"$TODAY"'",
                "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
                "confluent.topic.sasl.mechanism" : "PLAIN",
                "confluent.topic.bootstrap.servers": "'"$BOOTSTRAP_SERVERS"'",
                "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY'\" password=\"'$CLOUD_SECRET'\";",
                "confluent.topic.security.protocol" : "SASL_SSL",
                "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/servicenow-source/config | jq .
```

Create one record to ServiceNow

```
$ docker exec -e SERVICENOW_URL="$SERVICENOW_URL" -e SERVICENOW_PASSWORD="$SERVICENOW_PASSWORD" connect \
   curl -X POST \
    "${SERVICENOW_URL}/api/now/table/incident" \
    --user admin:"$SERVICENOW_PASSWORD" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' \
    -d '{"short_description": "This is test"}'
```

Verify we have received the data in `topic-servicenow` topic

```
$ timeout 60 docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e BASIC_AUTH_CREDENTIALS_SOURCE="$BASIC_AUTH_CREDENTIALS_SOURCE" connect bash -c 'kafka-console-consumer --topic topic-servicenow --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE --from-beginning --max-messages 1'
```

Results:

```json
{
    "payload": {
        "active": "true",
        "activity_due": "",
        "additional_assignee_list": "",
        "approval": "not requested",
        "approval_history": "",
        "approval_set": "",
        "assigned_to": "",
        "assignment_group": "",
        "business_duration": "",
        "business_service": "",
        "business_stc": "",
        "calendar_duration": "",
        "calendar_stc": "",
        "caller_id": "",
        "category": "inquiry",
        "caused_by": "",
        "child_incidents": "0",
        "close_code": "",
        "close_notes": "",
        "closed_at": "",
        "closed_by": "",
        "cmdb_ci": "",
        "comments": "",
        "comments_and_work_notes": "",
        "company": "",
        "contact_type": "",
        "contract": "",
        "correlation_display": "",
        "correlation_id": "",
        "delivery_plan": "",
        "delivery_task": "",
        "description": "",
        "due_date": "",
        "escalation": "0",
        "expected_start": "",
        "follow_up": "",
        "group_list": "",
        "hold_reason": "",
        "impact": "3",
        "incident_state": "1",
        "knowledge": "false",
        "location": "",
        "made_sla": "true",
        "notify": "1",
        "number": "INC0010003",
        "opened_at": 0,
        "opened_by": {
            "link": "https://dev57642.service-now.com/api/now/table/sys_user/6816f79cc0a8016401c5a33be04be441",
            "value": "6816f79cc0a8016401c5a33be04be441"
        },
        "order": "",
        "parent": "",
        "parent_incident": "",
        "priority": "5",
        "problem_id": "",
        "reassignment_count": "0",
        "reopen_count": "0",
        "reopened_by": "",
        "reopened_time": "",
        "resolved_at": "",
        "resolved_by": "",
        "rfc": "",
        "service_offering": "",
        "severity": "3",
        "short_description": "This is test",
        "sla_due": "",
        "state": "1",
        "subcategory": "",
        "sys_class_name": "incident",
        "sys_created_by": "admin",
        "sys_created_on": "2020-01-31 14:12:44",
        "sys_domain": {
            "link": "https://dev57642.service-now.com/api/now/table/sys_user_group/global",
            "value": "global"
        },
        "sys_domain_path": "/",
        "sys_id": "fba48173db6600107b7e5385ca96197e",
        "sys_mod_count": "0",
        "sys_tags": "",
        "sys_updated_by": "admin",
        "sys_updated_on": "2020-01-31 14:12:44",
        "time_worked": "",
        "upon_approval": "proceed",
        "upon_reject": "cancel",
        "urgency": "3",
        "user_input": "",
        "watch_list": "",
        "work_end": "",
        "work_notes": "",
        "work_notes_list": "",
        "work_start": ""
    },
    "schema": {
        "fields": [
            {
                "field": "sys_id",
                "optional": false,
                "type": "string"
            },
            {
                "field": "sys_created_on",
                "optional": false,
                "type": "string",
                "version": 1
            },
            {
                "field": "sys_created_by",
                "optional": false,
                "type": "string"
            },
            {
                "field": "sys_updated_on",
                "optional": false,
                "type": "string",
                "version": 1
            },
            {
                "field": "sys_updated_by",
                "optional": false,
                "type": "string"
            },
            {
                "field": "sys_mod_count",
                "optional": false,
                "type": "string"
            },
            {
                "field": "parent",
                "optional": true,
                "type": "string"
            },
            {
                "field": "made_sla",
                "optional": true,
                "type": "string"
            },
            {
                "field": "caused_by",
                "optional": true,
                "type": "string"
            },
            {
                "field": "watch_list",
                "optional": true,
                "type": "string"
            },
            {
                "field": "upon_reject",
                "optional": true,
                "type": "string"
            },
            {
                "field": "child_incidents",
                "optional": true,
                "type": "string"
            },
            {
                "field": "hold_reason",
                "optional": true,
                "type": "string"
            },
            {
                "field": "approval_history",
                "optional": true,
                "type": "string"
            },
            {
                "field": "number",
                "optional": true,
                "type": "string"
            },
            {
                "field": "resolved_by",
                "optional": true,
                "type": "string"
            },
            {
                "field": "opened_by",
                "fields": [
                    {
                        "field": "link",
                        "optional": false,
                        "type": "string"
                    },
                    {
                        "field": "value",
                        "optional": false,
                        "type": "string"
                    }
                ],
                "name": "opened_by",
                "optional": true,
                "type": "struct"
            },
            {
                "field": "user_input",
                "optional": true,
                "type": "string"
            },
            {
                "field": "sys_domain",
                "fields": [
                    {
                        "field": "link",
                        "optional": false,
                        "type": "string"
                    },
                    {
                        "field": "value",
                        "optional": false,
                        "type": "string"
                    }
                ],
                "name": "sys_domain",
                "optional": true,
                "type": "struct"
            },
            {
                "field": "state",
                "optional": true,
                "type": "string"
            },
            {
                "field": "knowledge",
                "optional": true,
                "type": "string"
            },
            {
                "field": "order",
                "optional": true,
                "type": "string"
            },
            {
                "field": "calendar_stc",
                "optional": true,
                "type": "string"
            },
            {
                "field": "closed_at",
                "optional": true,
                "type": "string",
                "version": 1
            },
            {
                "field": "cmdb_ci",
                "optional": true,
                "type": "string"
            },
            {
                "field": "delivery_plan",
                "optional": true,
                "type": "string"
            },
            {
                "field": "contract",
                "optional": true,
                "type": "string"
            },
            {
                "field": "impact",
                "optional": true,
                "type": "string"
            },
            {
                "field": "active",
                "optional": true,
                "type": "string"
            },
            {
                "field": "work_notes_list",
                "optional": true,
                "type": "string"
            },
            {
                "field": "business_service",
                "optional": true,
                "type": "string"
            },
            {
                "field": "priority",
                "optional": true,
                "type": "string"
            },
            {
                "field": "sys_domain_path",
                "optional": true,
                "type": "string"
            },
            {
                "field": "rfc",
                "optional": true,
                "type": "string"
            },
            {
                "field": "time_worked",
                "optional": true,
                "type": "string"
            },
            {
                "field": "expected_start",
                "optional": true,
                "type": "string"
            },
            {
                "field": "opened_at",
                "name": "org.apache.kafka.connect.data.Timestamp",
                "optional": true,
                "type": "int64",
                "version": 1
            },
            {
                "field": "business_duration",
                "optional": true,
                "type": "string",
                "version": 1
            },
            {
                "field": "group_list",
                "optional": true,
                "type": "string"
            },
            {
                "field": "work_end",
                "optional": true,
                "type": "string"
            },
            {
                "field": "caller_id",
                "optional": true,
                "type": "string"
            },
            {
                "field": "reopened_time",
                "optional": true,
                "type": "string"
            },
            {
                "field": "resolved_at",
                "optional": true,
                "type": "string",
                "version": 1
            },
            {
                "field": "approval_set",
                "optional": true,
                "type": "string"
            },
            {
                "field": "subcategory",
                "optional": true,
                "type": "string"
            },
            {
                "field": "work_notes",
                "optional": true,
                "type": "string"
            },
            {
                "field": "short_description",
                "optional": true,
                "type": "string"
            },
            {
                "field": "close_code",
                "optional": true,
                "type": "string"
            },
            {
                "field": "correlation_display",
                "optional": true,
                "type": "string"
            },
            {
                "field": "delivery_task",
                "optional": true,
                "type": "string"
            },
            {
                "field": "work_start",
                "optional": true,
                "type": "string"
            },
            {
                "field": "assignment_group",
                "optional": true,
                "type": "string"
            },
            {
                "field": "additional_assignee_list",
                "optional": true,
                "type": "string"
            },
            {
                "field": "business_stc",
                "optional": true,
                "type": "string"
            },
            {
                "field": "description",
                "optional": true,
                "type": "string"
            },
            {
                "field": "calendar_duration",
                "optional": true,
                "type": "string",
                "version": 1
            },
            {
                "field": "close_notes",
                "optional": true,
                "type": "string"
            },
            {
                "field": "notify",
                "optional": true,
                "type": "string"
            },
            {
                "field": "service_offering",
                "optional": true,
                "type": "string"
            },
            {
                "field": "sys_class_name",
                "optional": true,
                "type": "string"
            },
            {
                "field": "closed_by",
                "optional": true,
                "type": "string"
            },
            {
                "field": "follow_up",
                "optional": true,
                "type": "string"
            },
            {
                "field": "parent_incident",
                "optional": true,
                "type": "string"
            },
            {
                "field": "contact_type",
                "optional": true,
                "type": "string"
            },
            {
                "field": "reopened_by",
                "optional": true,
                "type": "string"
            },
            {
                "field": "incident_state",
                "optional": true,
                "type": "string"
            },
            {
                "field": "urgency",
                "optional": true,
                "type": "string"
            },
            {
                "field": "problem_id",
                "optional": true,
                "type": "string"
            },
            {
                "field": "company",
                "optional": true,
                "type": "string"
            },
            {
                "field": "reassignment_count",
                "optional": true,
                "type": "string"
            },
            {
                "field": "activity_due",
                "optional": true,
                "type": "string",
                "version": 1
            },
            {
                "field": "assigned_to",
                "optional": true,
                "type": "string"
            },
            {
                "field": "severity",
                "optional": true,
                "type": "string"
            },
            {
                "field": "comments",
                "optional": true,
                "type": "string"
            },
            {
                "field": "approval",
                "optional": true,
                "type": "string"
            },
            {
                "field": "sla_due",
                "optional": true,
                "type": "string"
            },
            {
                "field": "comments_and_work_notes",
                "optional": true,
                "type": "string"
            },
            {
                "field": "due_date",
                "optional": true,
                "type": "string"
            },
            {
                "field": "reopen_count",
                "optional": true,
                "type": "string"
            },
            {
                "field": "sys_tags",
                "optional": true,
                "type": "string"
            },
            {
                "field": "escalation",
                "optional": true,
                "type": "string"
            },
            {
                "field": "upon_approval",
                "optional": true,
                "type": "string"
            },
            {
                "field": "correlation_id",
                "optional": true,
                "type": "string"
            },
            {
                "field": "location",
                "optional": true,
                "type": "string"
            },
            {
                "field": "category",
                "optional": true,
                "type": "string"
            }
        ],
        "optional": false,
        "type": "struct"
    }
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
