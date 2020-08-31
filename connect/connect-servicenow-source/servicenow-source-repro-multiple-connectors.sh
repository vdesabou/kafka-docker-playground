#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

SERVICENOW_URL=${SERVICENOW_URL:-$1}
SERVICENOW_PASSWORD=${SERVICENOW_PASSWORD:-$2}

if [ -z "$SERVICENOW_URL" ]
then
     logerror "SERVICENOW_URL is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [[ "$SERVICENOW_URL" != */ ]]
then
    logerror "SERVICENOW_URL does not end with "/" Example: https://dev12345.service-now.com/ "
    exit 1
fi

if [ -z "$SERVICENOW_PASSWORD" ]
then
     logerror "SERVICENOW_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

TODAY=$(date '+%Y-%m-%d')

log "Creating ServiceNow Source connector 1"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.servicenow.ServiceNowSourceConnector",
                    "kafka.topic": "topic-servicenow1",
                    "servicenow.url": "'"$SERVICENOW_URL"'",
                    "tasks.max": "1",
                    "servicenow.table": "incident",
                    "servicenow.user": "admin",
                    "servicenow.password": "'"$SERVICENOW_PASSWORD"'",
                    "servicenow.since": "'"$TODAY"'",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/servicenow-source1/config | jq .


sleep 10

log "Create one record to ServiceNow"
docker exec -e SERVICENOW_URL="$SERVICENOW_URL" -e SERVICENOW_PASSWORD="$SERVICENOW_PASSWORD" connect \
   curl -X POST \
    "${SERVICENOW_URL}/api/now/table/incident" \
    --user admin:"$SERVICENOW_PASSWORD" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' \
    -d '{"short_description": "This is test"}'

sleep 5

log "Verify we have received the data in topic-servicenow1 topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic topic-servicenow1 --from-beginning --max-messages 1



# {
#     "payload": {
#         "active": "true",
#         "activity_due": "",
#         "additional_assignee_list": "",
#         "approval": "not requested",
#         "approval_history": "",
#         "approval_set": "",
#         "assigned_to": "",
#         "assignment_group": "",
#         "business_duration": "",
#         "business_service": "",
#         "business_stc": "",
#         "calendar_duration": "",
#         "calendar_stc": "",
#         "caller_id": "",
#         "category": "inquiry",
#         "caused_by": "",
#         "child_incidents": "0",
#         "close_code": "",
#         "close_notes": "",
#         "closed_at": "",
#         "closed_by": "",
#         "cmdb_ci": "",
#         "comments": "",
#         "comments_and_work_notes": "",
#         "company": "",
#         "contact_type": "",
#         "contract": "",
#         "correlation_display": "",
#         "correlation_id": "",
#         "delivery_plan": "",
#         "delivery_task": "",
#         "description": "",
#         "due_date": "",
#         "escalation": "0",
#         "expected_start": "",
#         "follow_up": "",
#         "group_list": "",
#         "hold_reason": "",
#         "impact": "3",
#         "incident_state": "1",
#         "knowledge": "false",
#         "location": "",
#         "made_sla": "true",
#         "notify": "1",
#         "number": "INC0010001",
#         "opened_at": 0,
#         "opened_by": {
#             "link": "https://dev97797.service-now.com/api/now/table/sys_user/6816f79cc0a8016401c5a33be04be441",
#             "value": "6816f79cc0a8016401c5a33be04be441"
#         },
#         "order": "",
#         "parent": "",
#         "parent_incident": "",
#         "priority": "5",
#         "problem_id": "",
#         "reassignment_count": "0",
#         "reopen_count": "0",
#         "reopened_by": "",
#         "reopened_time": "",
#         "resolved_at": "",
#         "resolved_by": "",
#         "rfc": "",
#         "service_offering": "",
#         "severity": "3",
#         "short_description": "This is test",
#         "sla_due": "",
#         "state": "1",
#         "subcategory": "",
#         "sys_class_name": "incident",
#         "sys_created_by": "admin",
#         "sys_created_on": "2020-04-09 09:18:15",
#         "sys_domain": {
#             "link": "https://dev97797.service-now.com/api/now/table/sys_user_group/global",
#             "value": "global"
#         },
#         "sys_domain_path": "/",
#         "sys_id": "76f61bf12fcc1010774cd7492799b6b1",
#         "sys_mod_count": "0",
#         "sys_tags": "",
#         "sys_updated_by": "admin",
#         "sys_updated_on": "2020-04-09 09:18:15",
#         "time_worked": "",
#         "upon_approval": "proceed",
#         "upon_reject": "cancel",
#         "urgency": "3",
#         "user_input": "",
#         "watch_list": "",
#         "work_end": "",
#         "work_notes": "",
#         "work_notes_list": "",
#         "work_start": ""
#     },
#     "schema": {
#         "fields": [
#             {
#                 "field": "sys_id",
#                 "optional": false,
#                 "type": "string"
#             },
#             {
#                 "field": "sys_created_on",
#                 "optional": false,
#                 "type": "string",
#                 "version": 1
#             },
#             {
#                 "field": "sys_created_by",
#                 "optional": false,
#                 "type": "string"
#             },
#             {
#                 "field": "sys_updated_on",
#                 "optional": false,
#                 "type": "string",
#                 "version": 1
#             },
#             {
#                 "field": "sys_updated_by",
#                 "optional": false,
#                 "type": "string"
#             },
#             {
#                 "field": "sys_mod_count",
#                 "optional": false,
#                 "type": "string"
#             },
#             {
#                 "field": "parent",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "made_sla",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "caused_by",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "watch_list",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "upon_reject",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "child_incidents",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "hold_reason",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "approval_history",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "number",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "resolved_by",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "opened_by",
#                 "fields": [
#                     {
#                         "field": "link",
#                         "optional": false,
#                         "type": "string"
#                     },
#                     {
#                         "field": "value",
#                         "optional": false,
#                         "type": "string"
#                     }
#                 ],
#                 "name": "opened_by",
#                 "optional": true,
#                 "type": "struct"
#             },
#             {
#                 "field": "user_input",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "sys_domain",
#                 "fields": [
#                     {
#                         "field": "link",
#                         "optional": false,
#                         "type": "string"
#                     },
#                     {
#                         "field": "value",
#                         "optional": false,
#                         "type": "string"
#                     }
#                 ],
#                 "name": "sys_domain",
#                 "optional": true,
#                 "type": "struct"
#             },
#             {
#                 "field": "state",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "knowledge",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "order",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "calendar_stc",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "closed_at",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "cmdb_ci",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "delivery_plan",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "contract",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "impact",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "active",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "work_notes_list",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "business_service",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "priority",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "sys_domain_path",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "rfc",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "time_worked",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "expected_start",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "opened_at",
#                 "name": "org.apache.kafka.connect.data.Timestamp",
#                 "optional": true,
#                 "type": "int64",
#                 "version": 1
#             },
#             {
#                 "field": "business_duration",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "group_list",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "work_end",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "caller_id",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "reopened_time",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "resolved_at",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "approval_set",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "subcategory",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "work_notes",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "short_description",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "close_code",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "correlation_display",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "delivery_task",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "work_start",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "assignment_group",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "additional_assignee_list",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "business_stc",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "description",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "calendar_duration",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "close_notes",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "notify",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "service_offering",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "sys_class_name",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "closed_by",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "follow_up",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "parent_incident",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "contact_type",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "reopened_by",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "incident_state",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "urgency",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "problem_id",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "company",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "reassignment_count",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "activity_due",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "assigned_to",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "severity",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "comments",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "approval",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "sla_due",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "comments_and_work_notes",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "due_date",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "reopen_count",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "sys_tags",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "escalation",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "upon_approval",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "correlation_id",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "location",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "category",
#                 "optional": true,
#                 "type": "string"
#             }
#         ],
#         "optional": false,
#         "type": "struct"
#     }
# }

TODAY=$(date '+%Y-%m-%d')
log "Creating ServiceNow Source connector 2"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.servicenow.ServiceNowSourceConnector",
                    "kafka.topic": "topic-servicenow2",
                    "servicenow.url": "'"$SERVICENOW_URL"'",
                    "tasks.max": "1",
                    "servicenow.table": "alm_facility",
                    "servicenow.user": "admin",
                    "servicenow.password": "'"$SERVICENOW_PASSWORD"'",
                    "servicenow.since": "'"$TODAY"'",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/servicenow-source2/config | jq .


sleep 10

log "Create one record to ServiceNow"
docker exec -e SERVICENOW_URL="$SERVICENOW_URL" -e SERVICENOW_PASSWORD="$SERVICENOW_PASSWORD" connect \
   curl -X POST \
    "${SERVICENOW_URL}/api/now/table/alm_facility" \
    --user admin:"$SERVICENOW_PASSWORD" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' \
    -d '{"comments": "This is test"}'

sleep 5

log "Verify we have received the data in topic-servicenow2 topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic topic-servicenow2 --from-beginning --max-messages 1

## ORIGINAL output (without no other connector)

{
    "payload": {
        "acquisition_method": "",
        "asset_tag": "",
        "assigned": "",
        "assigned_to": "",
        "beneficiary": "",
        "checked_in": "",
        "checked_out": "",
        "ci": "",
        "comments": "This is test",
        "company": "",
        "cost": "0",
        "cost_center": "",
        "delivery_date": "",
        "department": "",
        "depreciated_amount": "0",
        "depreciation": "",
        "depreciation_date": "",
        "display_name": "",
        "disposal_reason": "",
        "due": "",
        "due_in": "",
        "expenditure_type": "",
        "gl_account": "",
        "install_date": "",
        "install_status": "1",
        "invoice_number": "",
        "justification": "",
        "lease_id": "",
        "location": "",
        "managed_by": "",
        "model": "",
        "model_category": "",
        "old_status": "",
        "old_substatus": "",
        "order_date": "",
        "owned_by": "",
        "parent": "",
        "po_number": "",
        "pre_allocated": "false",
        "purchase_date": "",
        "quantity": "1",
        "request_line": "",
        "resale_price": "0",
        "reserved_for": "",
        "residual": "0",
        "residual_date": "",
        "retired": "",
        "retirement_date": "",
        "salvage_value": "0",
        "serial_number": "",
        "skip_sync": "false",
        "stockroom": "",
        "substatus": "",
        "support_group": "",
        "supported_by": "",
        "sys_class_name": "alm_facility",
        "sys_created_by": "admin",
        "sys_created_on": "2020-04-09 09:42:22",
        "sys_domain": {
            "link": "https://dev97797.service-now.com/api/now/table/sys_user_group/global",
            "value": "global"
        },
        "sys_domain_path": "/",
        "sys_id": "c08cdbb92fcc1010774cd7492799b6b2",
        "sys_mod_count": "0",
        "sys_tags": "",
        "sys_updated_by": "admin",
        "sys_updated_on": "2020-04-09 09:42:22",
        "vendor": "",
        "warranty_expiration": "",
        "work_notes": ""
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
                "field": "skip_sync",
                "optional": true,
                "type": "string"
            },
            {
                "field": "residual_date",
                "optional": true,
                "type": "string"
            },
            {
                "field": "residual",
                "optional": true,
                "type": "string"
            },
            {
                "field": "request_line",
                "optional": true,
                "type": "string"
            },
            {
                "field": "due_in",
                "optional": true,
                "type": "string"
            },
            {
                "field": "model_category",
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
                "field": "disposal_reason",
                "optional": true,
                "type": "string"
            },
            {
                "field": "model",
                "optional": true,
                "type": "string"
            },
            {
                "field": "install_date",
                "optional": true,
                "type": "string"
            },
            {
                "field": "gl_account",
                "optional": true,
                "type": "string"
            },
            {
                "field": "invoice_number",
                "optional": true,
                "type": "string"
            },
            {
                "field": "warranty_expiration",
                "optional": true,
                "type": "string"
            },
            {
                "field": "asset_tag",
                "optional": true,
                "type": "string"
            },
            {
                "field": "depreciated_amount",
                "optional": true,
                "type": "string"
            },
            {
                "field": "substatus",
                "optional": true,
                "type": "string"
            },
            {
                "field": "pre_allocated",
                "optional": true,
                "type": "string"
            },
            {
                "field": "owned_by",
                "optional": true,
                "type": "string"
            },
            {
                "field": "checked_out",
                "optional": true,
                "type": "string"
            },
            {
                "field": "display_name",
                "optional": true,
                "type": "string"
            },
            {
                "field": "sys_domain_path",
                "optional": true,
                "type": "string"
            },
            {
                "field": "delivery_date",
                "optional": true,
                "type": "string"
            },
            {
                "field": "retirement_date",
                "optional": true,
                "type": "string"
            },
            {
                "field": "beneficiary",
                "optional": true,
                "type": "string"
            },
            {
                "field": "install_status",
                "optional": true,
                "type": "string"
            },
            {
                "field": "cost_center",
                "optional": true,
                "type": "string"
            },
            {
                "field": "supported_by",
                "optional": true,
                "type": "string"
            },
            {
                "field": "assigned",
                "optional": true,
                "type": "string"
            },
            {
                "field": "purchase_date",
                "optional": true,
                "type": "string"
            },
            {
                "field": "work_notes",
                "optional": true,
                "type": "string"
            },
            {
                "field": "managed_by",
                "optional": true,
                "type": "string"
            },
            {
                "field": "sys_class_name",
                "optional": true,
                "type": "string"
            },
            {
                "field": "po_number",
                "optional": true,
                "type": "string"
            },
            {
                "field": "stockroom",
                "optional": true,
                "type": "string"
            },
            {
                "field": "checked_in",
                "optional": true,
                "type": "string"
            },
            {
                "field": "resale_price",
                "optional": true,
                "type": "string"
            },
            {
                "field": "vendor",
                "optional": true,
                "type": "string"
            },
            {
                "field": "company",
                "optional": true,
                "type": "string"
            },
            {
                "field": "retired",
                "optional": true,
                "type": "string"
            },
            {
                "field": "justification",
                "optional": true,
                "type": "string"
            },
            {
                "field": "department",
                "optional": true,
                "type": "string"
            },
            {
                "field": "expenditure_type",
                "optional": true,
                "type": "string"
            },
            {
                "field": "depreciation",
                "optional": true,
                "type": "string"
            },
            {
                "field": "assigned_to",
                "optional": true,
                "type": "string"
            },
            {
                "field": "depreciation_date",
                "optional": true,
                "type": "string"
            },
            {
                "field": "old_status",
                "optional": true,
                "type": "string"
            },
            {
                "field": "comments",
                "optional": true,
                "type": "string"
            },
            {
                "field": "cost",
                "optional": true,
                "type": "string"
            },
            {
                "field": "quantity",
                "optional": true,
                "type": "string"
            },
            {
                "field": "acquisition_method",
                "optional": true,
                "type": "string"
            },
            {
                "field": "ci",
                "optional": true,
                "type": "string"
            },
            {
                "field": "old_substatus",
                "optional": true,
                "type": "string"
            },
            {
                "field": "serial_number",
                "optional": true,
                "type": "string"
            },
            {
                "field": "sys_tags",
                "optional": true,
                "type": "string"
            },
            {
                "field": "order_date",
                "optional": true,
                "type": "string"
            },
            {
                "field": "support_group",
                "optional": true,
                "type": "string"
            },
            {
                "field": "reserved_for",
                "optional": true,
                "type": "string"
            },
            {
                "field": "due",
                "optional": true,
                "type": "string"
            },
            {
                "field": "location",
                "optional": true,
                "type": "string"
            },
            {
                "field": "lease_id",
                "optional": true,
                "type": "string"
            },
            {
                "field": "salvage_value",
                "optional": true,
                "type": "string"
            }
        ],
        "optional": false,
        "type": "struct"
    }
}


## AFTER

# {
#     "payload": {
#         "acquisition_method": "",
#         "active": null,
#         "activity_due": null,
#         "additional_assignee_list": null,
#         "approval": null,
#         "approval_history": null,
#         "approval_set": null,
#         "asset_tag": "",
#         "assigned": "",
#         "assigned_to": "",
#         "assignment_group": null,
#         "beneficiary": "",
#         "business_duration": null,
#         "business_service": null,
#         "business_stc": null,
#         "calendar_duration": null,
#         "calendar_stc": null,
#         "caller_id": null,
#         "category": null,
#         "caused_by": null,
#         "checked_in": "",
#         "checked_out": "",
#         "child_incidents": null,
#         "ci": "",
#         "close_code": null,
#         "close_notes": null,
#         "closed_at": null,
#         "closed_by": null,
#         "cmdb_ci": null,
#         "comments": "This is test",
#         "comments_and_work_notes": null,
#         "company": "",
#         "contact_type": null,
#         "contract": null,
#         "correlation_display": null,
#         "correlation_id": null,
#         "cost": "0",
#         "cost_center": "",
#         "delivery_date": "",
#         "delivery_plan": null,
#         "delivery_task": null,
#         "department": "",
#         "depreciated_amount": "0",
#         "depreciation": "",
#         "depreciation_date": "",
#         "description": null,
#         "display_name": "",
#         "disposal_reason": "",
#         "due": "",
#         "due_date": null,
#         "due_in": "",
#         "escalation": null,
#         "expected_start": null,
#         "expenditure_type": "",
#         "follow_up": null,
#         "gl_account": "",
#         "group_list": null,
#         "hold_reason": null,
#         "impact": null,
#         "incident_state": null,
#         "install_date": "",
#         "install_status": "1",
#         "invoice_number": "",
#         "justification": "",
#         "knowledge": null,
#         "lease_id": "",
#         "location": "",
#         "made_sla": null,
#         "managed_by": "",
#         "model": "",
#         "model_category": "",
#         "notify": null,
#         "number": null,
#         "old_status": "",
#         "old_substatus": "",
#         "opened_at": null,
#         "opened_by": null,
#         "order": null,
#         "order_date": "",
#         "owned_by": "",
#         "parent": "",
#         "parent_incident": null,
#         "po_number": "",
#         "pre_allocated": "false",
#         "priority": null,
#         "problem_id": null,
#         "purchase_date": "",
#         "quantity": "1",
#         "reassignment_count": null,
#         "reopen_count": null,
#         "reopened_by": null,
#         "reopened_time": null,
#         "request_line": "",
#         "resale_price": "0",
#         "reserved_for": "",
#         "residual": "0",
#         "residual_date": "",
#         "resolved_at": null,
#         "resolved_by": null,
#         "retired": "",
#         "retirement_date": "",
#         "rfc": null,
#         "salvage_value": "0",
#         "serial_number": "",
#         "service_offering": null,
#         "severity": null,
#         "short_description": null,
#         "skip_sync": "false",
#         "sla_due": null,
#         "state": null,
#         "stockroom": "",
#         "subcategory": null,
#         "substatus": "",
#         "support_group": "",
#         "supported_by": "",
#         "sys_class_name": "alm_facility",
#         "sys_created_by": "admin",
#         "sys_created_on": "2020-04-09 09:42:22",
#         "sys_domain": {
#             "link": "https://dev97797.service-now.com/api/now/table/sys_user_group/global",
#             "value": "global"
#         },
#         "sys_domain_path": "/",
#         "sys_id": "c08cdbb92fcc1010774cd7492799b6b2",
#         "sys_mod_count": "0",
#         "sys_tags": "",
#         "sys_updated_by": "admin",
#         "sys_updated_on": "2020-04-09 09:42:22",
#         "time_worked": null,
#         "upon_approval": null,
#         "upon_reject": null,
#         "urgency": null,
#         "user_input": null,
#         "vendor": "",
#         "warranty_expiration": "",
#         "watch_list": null,
#         "work_end": null,
#         "work_notes": "",
#         "work_notes_list": null,
#         "work_start": null
#     },
#     "schema": {
#         "fields": [
#             {
#                 "field": "sys_id",
#                 "optional": false,
#                 "type": "string"
#             },
#             {
#                 "field": "sys_created_on",
#                 "optional": false,
#                 "type": "string",
#                 "version": 1
#             },
#             {
#                 "field": "sys_created_by",
#                 "optional": false,
#                 "type": "string"
#             },
#             {
#                 "field": "sys_updated_on",
#                 "optional": false,
#                 "type": "string",
#                 "version": 1
#             },
#             {
#                 "field": "sys_updated_by",
#                 "optional": false,
#                 "type": "string"
#             },
#             {
#                 "field": "sys_mod_count",
#                 "optional": false,
#                 "type": "string"
#             },
#             {
#                 "field": "parent",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "made_sla",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "caused_by",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "watch_list",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "upon_reject",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "child_incidents",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "hold_reason",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "approval_history",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "number",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "resolved_by",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "opened_by",
#                 "fields": [
#                     {
#                         "field": "link",
#                         "optional": false,
#                         "type": "string"
#                     },
#                     {
#                         "field": "value",
#                         "optional": false,
#                         "type": "string"
#                     }
#                 ],
#                 "name": "opened_by",
#                 "optional": true,
#                 "type": "struct"
#             },
#             {
#                 "field": "user_input",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "sys_domain",
#                 "fields": [
#                     {
#                         "field": "link",
#                         "optional": false,
#                         "type": "string"
#                     },
#                     {
#                         "field": "value",
#                         "optional": false,
#                         "type": "string"
#                     }
#                 ],
#                 "name": "sys_domain",
#                 "optional": true,
#                 "type": "struct"
#             },
#             {
#                 "field": "state",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "knowledge",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "order",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "calendar_stc",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "closed_at",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "cmdb_ci",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "delivery_plan",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "contract",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "impact",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "active",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "work_notes_list",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "business_service",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "priority",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "sys_domain_path",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "rfc",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "time_worked",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "expected_start",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "opened_at",
#                 "name": "org.apache.kafka.connect.data.Timestamp",
#                 "optional": true,
#                 "type": "int64",
#                 "version": 1
#             },
#             {
#                 "field": "business_duration",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "group_list",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "work_end",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "caller_id",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "reopened_time",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "resolved_at",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "approval_set",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "subcategory",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "work_notes",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "short_description",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "close_code",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "correlation_display",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "delivery_task",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "work_start",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "assignment_group",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "additional_assignee_list",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "business_stc",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "description",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "calendar_duration",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "close_notes",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "notify",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "service_offering",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "sys_class_name",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "closed_by",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "follow_up",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "parent_incident",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "contact_type",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "reopened_by",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "incident_state",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "urgency",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "problem_id",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "company",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "reassignment_count",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "activity_due",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "assigned_to",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "severity",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "comments",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "approval",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "sla_due",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "comments_and_work_notes",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "due_date",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "reopen_count",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "sys_tags",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "escalation",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "upon_approval",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "correlation_id",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "location",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "category",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "skip_sync",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "residual_date",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "residual",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "request_line",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "due_in",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "model_category",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "disposal_reason",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "model",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "install_date",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "gl_account",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "invoice_number",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "warranty_expiration",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "asset_tag",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "depreciated_amount",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "substatus",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "pre_allocated",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "owned_by",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "checked_out",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "display_name",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "delivery_date",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "retirement_date",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "beneficiary",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "install_status",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "cost_center",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "supported_by",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "assigned",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "purchase_date",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "managed_by",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "po_number",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "stockroom",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "checked_in",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "resale_price",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "vendor",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "retired",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "justification",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "department",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "expenditure_type",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "depreciation",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "depreciation_date",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "old_status",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "cost",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "quantity",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "acquisition_method",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "ci",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "old_substatus",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "serial_number",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "order_date",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "support_group",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "reserved_for",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "due",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "lease_id",
#                 "optional": true,
#                 "type": "string"
#             },
#             {
#                 "field": "salvage_value",
#                 "optional": true,
#                 "type": "string"
#             }
#         ],
#         "optional": false,
#         "type": "struct"
#     }
# }

