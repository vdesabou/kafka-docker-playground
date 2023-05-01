#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating syslog connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "topic": "logs",
                "tasks.max": "1",
                "connector.class": "io.confluent.connect.syslog.SyslogSourceConnector",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "syslog.port": "42514",
                "syslog.listener": "UDP",
                "syslog.reverse.dns.remote.ip": "true",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/syslog-source/config


log "Creating elasticsearch connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
                "connection.url": "http://elasticsearch:9200",
                "connection.username": "elastic",
                "connection.password": "elastic",
                "type.name": "_doc",
                "behavior.on.malformed.documents": "warn",
                "errors.tolerance": "all",
                "errors.log.enable": "true",
                "errors.log.include.messages": "true",
                "topics": "SSH_BAD_AUTH_COUNT",
                "key.ignore": "true",
                "schema.ignore": "true",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "transforms": "RenameField",
               "transforms.RenameField.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
               "transforms.RenameField.renames": "TIME:@timestamp"
          }' \
     http://localhost:8083/connectors/elastic-sink/config

log "Create ssh logs"
docker exec -i connect bash -c 'kafka-topics --bootstrap-server broker:9092 --topic ssh_logs --partitions 1 --replication-factor 1 --create'

log "Create the ksqlDB stream"
docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [[ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ]] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE OR REPLACE STREAM SSH_LOGS (
   level BIGINT,
   sshd_auth_type VARCHAR,
   sshd_user VARCHAR,
   ssh_auth_log_line VARCHAR,
   sshd_result VARCHAR,
   sshd_port BIGINT,
   host VARCHAR,
   sshd_protocol VARCHAR,
   sshd_client_ip VARCHAR)
   WITH (KAFKA_TOPIC='ssh_logs', VALUE_FORMAT='JSON');

CREATE OR REPLACE TABLE SSH_TABLE_LOGS
    WITH (kafka_topic='SSH_TABLE_LOGS') AS
    SELECT SSHD_USER,
           COUNT(SSHD_USER) AS BAD_AUTH_COUNT,
           WINDOWSTART as WINDOW_START,
           WINDOWEND as WINDOW_END,
           AS_VALUE(SSHD_USER) USER
    FROM SSH_LOGS
    WINDOW TUMBLING (SIZE 5 MINUTES)
    WHERE SSHD_RESULT = 'Failed'
    GROUP BY SSHD_USER;
    
CREATE OR REPLACE STREAM SSH_STREAM_COUNT_LOGS (
      USER VARCHAR,
      BAD_AUTH_COUNT BIGINT,
      WINDOW_START BIGINT,
      WINDOW_END BIGINT
    )
    WITH (kafka_topic='SSH_TABLE_LOGS', value_format='JSON');
    
CREATE OR REPLACE STREAM SSH_BAD_AUTH_COUNT AS SELECT *
    FROM SSH_STREAM_COUNT_LOGS;

EOF

# sleep 5

# Import elastic index & dashboard
curl -X POST \
     -H "Content-Type: application/json" \
     -H "kbn-xsrf: reporting" \
     --data '
        {
            "override": false,
            "refresh_fields": false,
            "index_pattern": {
                "title": "ssh_bad_auth_count",
                "fields": {
                  "BAD_AUTH_COUNT": {
                    "count": 0,
                    "name": "BAD_AUTH_COUNT",
                    "type": "number",
                    "esTypes": [
                      "long"
                    ],
                    "scripted": false,
                    "searchable": true,
                    "aggregatable": true,
                    "readFromDocValues": true,
                    "format": {
                      "id": "number"
                    },
                    "shortDotsEnable": false,
                    "isMapped": true
                  },
                  "USER": {
                    "count": 0,
                    "name": "USER",
                    "type": "string",
                    "esTypes": [
                      "text"
                    ],
                    "scripted": false,
                    "searchable": true,
                    "aggregatable": false,
                    "readFromDocValues": false,
                    "format": {
                      "id": "string"
                    },
                    "shortDotsEnable": false,
                    "isMapped": true
                  },
                  "USER.keyword": {
                    "count": 0,
                    "name": "USER.keyword",
                    "type": "string",
                    "esTypes": [
                      "keyword"
                    ],
                    "scripted": false,
                    "searchable": true,
                    "aggregatable": true,
                    "readFromDocValues": true,
                    "subType": {
                      "multi": {
                        "parent": "USER"
                      }
                    },
                    "format": {
                      "id": "string"
                    },
                    "shortDotsEnable": false,
                    "isMapped": true
                  },
                  "WINDOW_END": {
                    "count": 0,
                    "name": "WINDOW_END",
                    "type": "number",
                    "esTypes": [
                      "long"
                    ],
                    "scripted": false,
                    "searchable": true,
                    "aggregatable": true,
                    "readFromDocValues": true,
                    "format": {
                      "id": "number"
                    },
                    "shortDotsEnable": false,
                    "isMapped": true
                  },
                  "WINDOW_START": {
                    "count": 0,
                    "name": "WINDOW_START",
                    "type": "number",
                    "esTypes": [
                      "long"
                    ],
                    "scripted": false,
                    "searchable": true,
                    "aggregatable": true,
                    "readFromDocValues": true,
                    "format": {
                      "id": "number"
                    },
                    "shortDotsEnable": false,
                    "isMapped": true
                  },
                  "_id": {
                    "count": 0,
                    "name": "_id",
                    "type": "string",
                    "esTypes": [
                      "_id"
                    ],
                    "scripted": false,
                    "searchable": true,
                    "aggregatable": true,
                    "readFromDocValues": false,
                    "format": {
                      "id": "string"
                    },
                    "shortDotsEnable": false,
                    "isMapped": true
                  },
                  "_index": {
                    "count": 0,
                    "name": "_index",
                    "type": "string",
                    "esTypes": [
                      "_index"
                    ],
                    "scripted": false,
                    "searchable": true,
                    "aggregatable": true,
                    "readFromDocValues": false,
                    "format": {
                      "id": "string"
                    },
                    "shortDotsEnable": false,
                    "isMapped": true
                  },
                  "_score": {
                    "count": 0,
                    "name": "_score",
                    "type": "number",
                    "scripted": false,
                    "searchable": false,
                    "aggregatable": false,
                    "readFromDocValues": false,
                    "format": {
                      "id": "number"
                    },
                    "shortDotsEnable": false,
                    "isMapped": true
                  },
                  "_source": {
                    "count": 0,
                    "name": "_source",
                    "type": "_source",
                    "esTypes": [
                      "_source"
                    ],
                    "scripted": false,
                    "searchable": false,
                    "aggregatable": false,
                    "readFromDocValues": false,
                    "format": {
                      "id": "_source"
                    },
                    "shortDotsEnable": false,
                    "isMapped": true
                  },
                  "_type": {
                    "count": 0,
                    "name": "_type",
                    "type": "string",
                    "esTypes": [
                      "_type"
                    ],
                    "scripted": false,
                    "searchable": true,
                    "aggregatable": true,
                    "readFromDocValues": false,
                    "format": {
                      "id": "string"
                    },
                    "shortDotsEnable": false,
                    "isMapped": true
                  },
                  "WINDOW_START_DATE": {
                    "count": 1,
                    "script": "doc[\"WINDOW_START\"].value",
                    "name": "WINDOW_START_DATE",
                    "type": "date",
                    "scripted": true,
                    "searchable": true,
                    "aggregatable": true,
                    "readFromDocValues": false,
                    "format": {
                      "id": "date",
                      "params": {
                        "pattern": "LLL"
                      }
                    },
                    "shortDotsEnable": false
                  },
                  "WINDOW_END_DATE": {
                    "count": 3,
                    "script": "doc[\"WINDOW_END\"].value",
                    "name": "WINDOW_END_DATE",
                    "type": "date",
                    "scripted": true,
                    "searchable": true,
                    "aggregatable": true,
                    "readFromDocValues": false,
                    "format": {
                      "id": "date",
                      "params": {
                        "pattern": "LLL"
                      }
                    },
                    "shortDotsEnable": false
                  },
                  "WINDOW": {
                    "count": 0,
                    "script": "long epocWS = doc[\"WINDOW_START\"].value;\nlong epocWE = doc[\"WINDOW_END\"].value;\n\nInstant instantWS = Instant.ofEpochMilli(epocWS);\nInstant instantWE = Instant.ofEpochMilli(epocWE);\nDateTimeFormatter DATE_TIME_FORMATTER = DateTimeFormatter.ofPattern(\"yyyy-MM-dd HH:mm:ss\")\n    .withZone(ZoneId.of(\"Europe/Paris\"));\n            \nString begin = DATE_TIME_FORMATTER.format(instantWS);\nString end = DATE_TIME_FORMATTER.format(instantWE);\n\nreturn begin + \"/\" + end;",
                    "lang": "painless",
                    "name": "WINDOW",
                    "type": "string",
                    "scripted": true,
                    "searchable": true,
                    "aggregatable": true,
                    "readFromDocValues": false,
                    "format": {
                      "id": "string",
                      "params": {
                        "pattern": "0,0.[000]"
                      }
                    },
                    "shortDotsEnable": false
                  }
                },
                "typeMeta": {},
                "fieldFormats": {
                  "WINDOW_START_DATE": {
                    "id": "date",
                    "params": {
                      "pattern": "LLL"
                    }
                  },
                  "WINDOW_END_DATE": {
                    "id": "date",
                    "params": {
                      "parsedUrl": {
                        "origin": "http://localhost:5601",
                        "pathname": "/app/management/kibana/indexPatterns",
                        "basePath": ""
                      },
                      "pattern": "LLL",
                      "timezone": "Browser"
                    }
                  },
                  "WINDOW": {
                    "id": "string",
                    "params": {
                      "parsedUrl": {
                        "origin": "http://localhost:5601",
                        "pathname": "/app/management/kibana/indexPatterns",
                        "basePath": ""
                      },
                      "pattern": "0,0.[000]"
                    }
                  }
                },
                "runtimeFieldMap": {},
                "fieldAttrs": {
                  "WINDOW_END_DATE": {
                    "count": 3
                  },
                  "WINDOW_START_DATE": {
                    "count": 1
                  },
                  "WINDOW": {
                    "count": 0
                  }
                },
                "allowNoIndex": false
            }
        }' \
    "http://localhost:5601/api/index_patterns/index_pattern"

content=$(echo $(curl --silent -X GET \
     -H "Content-Type: application/json" \
     -H "kbn-xsrf: reporting" \
     --data '[]' \
    "http://localhost:5601/api/saved_objects/_find?type=index-pattern" | jq -r '.saved_objects[0].id')) 

log "Index pattern : ${content}"

curl -X POST \
    -H "Content-Type: application/json" \
    -H "kbn-xsrf: reporting" \
    --data '{
      "objects": [
        {
        "id": "076624e0-58f1-11ec-9ae7-ed37822fa749",
        "type": "dashboard",
        "namespaces": [
            "default"
        ],
        "updated_at": "2021-12-09T13:17:04.611Z",
        "version": "WzIwMDAsMV0=",
        "attributes": {
            "title": "List of users",
            "hits": 0,
            "description": "",
            "panelsJSON": "[{\"version\":\"7.15.2\",\"type\":\"lens\",\"gridData\":{\"x\":0,\"y\":0,\"w\":24,\"h\":15,\"i\":\"de8d829b-cacd-4d82-8f63-afbdf2cf3804\"},\"panelIndex\":\"de8d829b-cacd-4d82-8f63-afbdf2cf3804\",\"embeddableConfig\":{\"attributes\":{\"title\":\"\",\"visualizationType\":\"lnsDatatable\",\"type\":\"lens\",\"references\":[{\"type\":\"index-pattern\",\"id\":\"'${content}'\",\"name\":\"indexpattern-datasource-current-indexpattern\"},{\"type\":\"index-pattern\",\"id\":\"'${content}'\",\"name\":\"indexpattern-datasource-layer-d97567e7-530b-400f-a62a-515682887a78\"}],\"state\":{\"visualization\":{\"layerId\":\"d97567e7-530b-400f-a62a-515682887a78\",\"layerType\":\"data\",\"columns\":[{\"columnId\":\"5295bf5f-8eb7-4d9f-99d1-e46c19d757de\"},{\"columnId\":\"7b11f852-c290-4f32-a96f-2f5b491aab6f\"},{\"columnId\":\"e7e10b7b-e0ad-4fa0-b27b-00a03d2f4b44\",\"isTransposed\":true}]},\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filters\":[],\"datasourceStates\":{\"indexpattern\":{\"layers\":{\"d97567e7-530b-400f-a62a-515682887a78\":{\"columns\":{\"5295bf5f-8eb7-4d9f-99d1-e46c19d757de\":{\"label\":\"Window\",\"dataType\":\"string\",\"operationType\":\"terms\",\"scale\":\"ordinal\",\"sourceField\":\"WINDOW\",\"isBucketed\":true,\"params\":{\"size\":5,\"orderBy\":{\"type\":\"column\",\"columnId\":\"7b11f852-c290-4f32-a96f-2f5b491aab6f\"},\"orderDirection\":\"desc\",\"otherBucket\":true,\"missingBucket\":false},\"customLabel\":true},\"7b11f852-c290-4f32-a96f-2f5b491aab6f\":{\"label\":\"Bad Auth Count\",\"dataType\":\"number\",\"operationType\":\"max\",\"sourceField\":\"BAD_AUTH_COUNT\",\"isBucketed\":false,\"scale\":\"ratio\",\"customLabel\":true},\"e7e10b7b-e0ad-4fa0-b27b-00a03d2f4b44\":{\"label\":\"User\",\"dataType\":\"string\",\"operationType\":\"terms\",\"scale\":\"ordinal\",\"sourceField\":\"USER.keyword\",\"isBucketed\":true,\"params\":{\"size\":3,\"orderBy\":{\"type\":\"column\",\"columnId\":\"7b11f852-c290-4f32-a96f-2f5b491aab6f\"},\"orderDirection\":\"desc\",\"otherBucket\":true,\"missingBucket\":false},\"customLabel\":true}},\"columnOrder\":[\"e7e10b7b-e0ad-4fa0-b27b-00a03d2f4b44\",\"5295bf5f-8eb7-4d9f-99d1-e46c19d757de\",\"7b11f852-c290-4f32-a96f-2f5b491aab6f\"],\"incompleteColumns\":{}}}}}}},\"enhancements\":{}}},{\"version\":\"7.15.2\",\"type\":\"lens\",\"gridData\":{\"x\":24,\"y\":0,\"w\":24,\"h\":15,\"i\":\"9182bf5f-ffd5-43d0-873a-ca272cca90a0\"},\"panelIndex\":\"9182bf5f-ffd5-43d0-873a-ca272cca90a0\",\"embeddableConfig\":{\"attributes\":{\"title\":\"\",\"visualizationType\":\"lnsXY\",\"type\":\"lens\",\"references\":[{\"type\":\"index-pattern\",\"id\":\"'${content}'\",\"name\":\"indexpattern-datasource-current-indexpattern\"},{\"type\":\"index-pattern\",\"id\":\"'${content}'\",\"name\":\"indexpattern-datasource-layer-0006cb13-75e8-4822-94e0-8051d2f9cfee\"}],\"state\":{\"visualization\":{\"legend\":{\"isVisible\":true,\"position\":\"right\"},\"valueLabels\":\"hide\",\"fittingFunction\":\"None\",\"yRightExtent\":{\"mode\":\"full\"},\"axisTitlesVisibilitySettings\":{\"x\":true,\"yLeft\":true,\"yRight\":true},\"tickLabelsVisibilitySettings\":{\"x\":true,\"yLeft\":true,\"yRight\":true},\"labelsOrientation\":{\"x\":0,\"yLeft\":0,\"yRight\":0},\"gridlinesVisibilitySettings\":{\"x\":true,\"yLeft\":true,\"yRight\":true},\"preferredSeriesType\":\"bar_stacked\",\"layers\":[{\"layerId\":\"0006cb13-75e8-4822-94e0-8051d2f9cfee\",\"seriesType\":\"bar_stacked\",\"xAccessor\":\"b7ff79ad-6831-4ddf-82d0-2632ab5f926e\",\"splitAccessor\":\"d8059608-e964-439c-a101-98f252700b17\",\"accessors\":[\"821d7895-a9d8-41c2-8a11-aeb50e430544\"],\"layerType\":\"data\"}]},\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filters\":[],\"datasourceStates\":{\"indexpattern\":{\"layers\":{\"0006cb13-75e8-4822-94e0-8051d2f9cfee\":{\"columns\":{\"d8059608-e964-439c-a101-98f252700b17\":{\"label\":\"User\",\"dataType\":\"string\",\"operationType\":\"terms\",\"scale\":\"ordinal\",\"sourceField\":\"USER.keyword\",\"isBucketed\":true,\"params\":{\"size\":3,\"orderBy\":{\"type\":\"column\",\"columnId\":\"821d7895-a9d8-41c2-8a11-aeb50e430544\"},\"orderDirection\":\"desc\",\"otherBucket\":true,\"missingBucket\":false},\"customLabel\":true},\"b7ff79ad-6831-4ddf-82d0-2632ab5f926e\":{\"label\":\"Window\",\"dataType\":\"string\",\"operationType\":\"terms\",\"scale\":\"ordinal\",\"sourceField\":\"WINDOW\",\"isBucketed\":true,\"params\":{\"size\":10,\"orderBy\":{\"type\":\"column\",\"columnId\":\"821d7895-a9d8-41c2-8a11-aeb50e430544\"},\"orderDirection\":\"desc\",\"otherBucket\":true,\"missingBucket\":false},\"customLabel\":true},\"821d7895-a9d8-41c2-8a11-aeb50e430544\":{\"label\":\"Bad Auth Count\",\"dataType\":\"number\",\"operationType\":\"max\",\"sourceField\":\"BAD_AUTH_COUNT\",\"isBucketed\":false,\"scale\":\"ratio\",\"customLabel\":true}},\"columnOrder\":[\"d8059608-e964-439c-a101-98f252700b17\",\"b7ff79ad-6831-4ddf-82d0-2632ab5f926e\",\"821d7895-a9d8-41c2-8a11-aeb50e430544\"],\"incompleteColumns\":{}}}}}}},\"enhancements\":{}}},{\"version\":\"7.15.2\",\"type\":\"lens\",\"gridData\":{\"x\":0,\"y\":15,\"w\":24,\"h\":15,\"i\":\"1675c3b0-b192-4450-99fd-bb51c15115ee\"},\"panelIndex\":\"1675c3b0-b192-4450-99fd-bb51c15115ee\",\"embeddableConfig\":{\"attributes\":{\"title\":\"\",\"visualizationType\":\"lnsPie\",\"type\":\"lens\",\"references\":[{\"type\":\"index-pattern\",\"id\":\"'${content}'\",\"name\":\"indexpattern-datasource-current-indexpattern\"},{\"type\":\"index-pattern\",\"id\":\"'${content}'\",\"name\":\"indexpattern-datasource-layer-c5750222-81de-4755-9d60-87e5f314671b\"}],\"state\":{\"visualization\":{\"shape\":\"donut\",\"layers\":[{\"layerId\":\"c5750222-81de-4755-9d60-87e5f314671b\",\"groups\":[\"0ab8c4b3-0020-4fc5-b99f-28ece27d484a\"],\"metric\":\"0e76a0d6-4b3b-4687-afe6-e12148a0a890\",\"numberDisplay\":\"percent\",\"categoryDisplay\":\"default\",\"legendDisplay\":\"default\",\"nestedLegend\":false,\"layerType\":\"data\"}]},\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filters\":[],\"datasourceStates\":{\"indexpattern\":{\"layers\":{\"c5750222-81de-4755-9d60-87e5f314671b\":{\"columns\":{\"0ab8c4b3-0020-4fc5-b99f-28ece27d484a\":{\"label\":\"Top values of USER.keyword\",\"dataType\":\"string\",\"operationType\":\"terms\",\"scale\":\"ordinal\",\"sourceField\":\"USER.keyword\",\"isBucketed\":true,\"params\":{\"size\":5,\"orderBy\":{\"type\":\"column\",\"columnId\":\"0e76a0d6-4b3b-4687-afe6-e12148a0a890\"},\"orderDirection\":\"desc\",\"otherBucket\":true,\"missingBucket\":false}},\"0e76a0d6-4b3b-4687-afe6-e12148a0a890\":{\"label\":\"95th percentile of BAD_AUTH_COUNT\",\"dataType\":\"number\",\"operationType\":\"percentile\",\"sourceField\":\"BAD_AUTH_COUNT\",\"isBucketed\":false,\"scale\":\"ratio\",\"params\":{\"percentile\":95}}},\"columnOrder\":[\"0ab8c4b3-0020-4fc5-b99f-28ece27d484a\",\"0e76a0d6-4b3b-4687-afe6-e12148a0a890\"],\"incompleteColumns\":{}}}}}}},\"enhancements\":{}}}]",
            "optionsJSON": "{\"useMargins\":true,\"syncColors\":false,\"hidePanelTitles\":false}",
            "version": 1,
            "timeRestore": false,
            "kibanaSavedObjectMeta": {
            "searchSourceJSON": "{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"
            }
        },
        "references": [
            {
            "type": "index-pattern",
            "id": "'${content}'",
            "name": "de8d829b-cacd-4d82-8f63-afbdf2cf3804:indexpattern-datasource-current-indexpattern"
            },
            {
            "type": "index-pattern",
            "id": "'${content}'",
            "name": "de8d829b-cacd-4d82-8f63-afbdf2cf3804:indexpattern-datasource-layer-d97567e7-530b-400f-a62a-515682887a78"
            },
            {
            "type": "index-pattern",
            "id": "'${content}'",
            "name": "9182bf5f-ffd5-43d0-873a-ca272cca90a0:indexpattern-datasource-current-indexpattern"
            },
            {
            "type": "index-pattern",
            "id": "'${content}'",
            "name": "9182bf5f-ffd5-43d0-873a-ca272cca90a0:indexpattern-datasource-layer-0006cb13-75e8-4822-94e0-8051d2f9cfee"
            },
            {
            "type": "index-pattern",
            "id": "'${content}'",
            "name": "1675c3b0-b192-4450-99fd-bb51c15115ee:indexpattern-datasource-current-indexpattern"
            },
            {
            "type": "index-pattern",
            "id": "'${content}'",
            "name": "1675c3b0-b192-4450-99fd-bb51c15115ee:indexpattern-datasource-layer-c5750222-81de-4755-9d60-87e5f314671b"
            }
        ],
        "migrationVersion": {
            "dashboard": "7.15.0"
        },
        "coreMigrationVersion": "7.15.2"
        },
        {
        "id": "'${content}'",
        "type": "index-pattern",
        "namespaces": [
            "default"
        ],
        "updated_at": "2021-12-09T13:11:21.340Z",
        "version": "WzE3MjAsMV0=",
        "attributes": {
            "fieldAttrs": "{\"WINDOW_END_DATE\":{\"count\":3},\"WINDOW_START_DATE\":{\"count\":1}}",
            "title": "ssh_bad_auth_count",
            "fields": "[{\"count\":1,\"script\":\"doc[\\\"WINDOW_START\\\"].value\",\"name\":\"WINDOW_START_DATE\",\"type\":\"date\",\"scripted\":true,\"searchable\":true,\"aggregatable\":true,\"readFromDocValues\":false},{\"count\":3,\"script\":\"doc[\\\"WINDOW_END\\\"].value\",\"name\":\"WINDOW_END_DATE\",\"type\":\"date\",\"scripted\":true,\"searchable\":true,\"aggregatable\":true,\"readFromDocValues\":false},{\"count\":0,\"script\":\"long epocWS = doc[\\\"WINDOW_START\\\"].value;\\nlong epocWE = doc[\\\"WINDOW_END\\\"].value;\\n\\nInstant instantWS = Instant.ofEpochMilli(epocWS);\\nInstant instantWE = Instant.ofEpochMilli(epocWE);\\nDateTimeFormatter DATE_TIME_FORMATTER = DateTimeFormatter.ofPattern(\\\"yyyy-MM-dd HH:mm:ss\\\")\\n    .withZone(ZoneId.of(\\\"Europe/Paris\\\"));\\n            \\nString begin = DATE_TIME_FORMATTER.format(instantWS);\\nString end = DATE_TIME_FORMATTER.format(instantWE);\\n\\nreturn begin + \\\"/\\\" + end;\",\"name\":\"WINDOW\",\"type\":\"string\",\"scripted\":true,\"searchable\":true,\"aggregatable\":true,\"readFromDocValues\":false}]",
            "fieldFormatMap": "{\"WINDOW_START_DATE\":{\"id\":\"date\",\"params\":{\"pattern\":\"LLL\"}},\"WINDOW_END_DATE\":{\"id\":\"date\",\"params\":{\"parsedUrl\":{\"origin\":\"http://localhost:5601\",\"pathname\":\"/app/management/kibana/indexPatterns\",\"basePath\":\"\"},\"pattern\":\"LLL\",\"timezone\":\"Browser\"}},\"WINDOW\":{\"id\":\"string\",\"params\":{\"parsedUrl\":{\"origin\":\"http://localhost:5601\",\"pathname\":\"/app/management/kibana/indexPatterns\",\"basePath\":\"\"},\"pattern\":\"0,0.[000]\"}}}",
            "typeMeta": "{}",
            "runtimeFieldMap": "{}"
        },
        "references": [],
        "migrationVersion": {
            "index-pattern": "7.11.0"
        },
        "coreMigrationVersion": "7.15.2"
        }
    ]
  }' \
    "http://localhost:5601/api/kibana/dashboards/import?exclude=index-pattern"

dashboardId=$(echo $(curl -X POST \
    -H "Content-Type: application/json" \
    -H "kbn-xsrf: reporting" \
    --data '{
      "objects": [
        {
        "id": "076624e0-58f1-11ec-9ae7-ed37822fa749",
        "type": "dashboard",
        "namespaces": [
            "default"
        ],
        "updated_at": "2021-12-09T13:17:04.611Z",
        "version": "WzIwMDAsMV0=",
        "attributes": {
            "title": "List of users",
            "hits": 0,
            "description": "",
            "panelsJSON": "[{\"version\":\"7.15.2\",\"type\":\"lens\",\"gridData\":{\"x\":0,\"y\":0,\"w\":24,\"h\":15,\"i\":\"de8d829b-cacd-4d82-8f63-afbdf2cf3804\"},\"panelIndex\":\"de8d829b-cacd-4d82-8f63-afbdf2cf3804\",\"embeddableConfig\":{\"attributes\":{\"title\":\"\",\"visualizationType\":\"lnsDatatable\",\"type\":\"lens\",\"references\":[{\"type\":\"index-pattern\",\"id\":\"'${content}'\",\"name\":\"indexpattern-datasource-current-indexpattern\"},{\"type\":\"index-pattern\",\"id\":\"'${content}'\",\"name\":\"indexpattern-datasource-layer-d97567e7-530b-400f-a62a-515682887a78\"}],\"state\":{\"visualization\":{\"layerId\":\"d97567e7-530b-400f-a62a-515682887a78\",\"layerType\":\"data\",\"columns\":[{\"columnId\":\"5295bf5f-8eb7-4d9f-99d1-e46c19d757de\"},{\"columnId\":\"7b11f852-c290-4f32-a96f-2f5b491aab6f\"},{\"columnId\":\"e7e10b7b-e0ad-4fa0-b27b-00a03d2f4b44\",\"isTransposed\":true}]},\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filters\":[],\"datasourceStates\":{\"indexpattern\":{\"layers\":{\"d97567e7-530b-400f-a62a-515682887a78\":{\"columns\":{\"5295bf5f-8eb7-4d9f-99d1-e46c19d757de\":{\"label\":\"Window\",\"dataType\":\"string\",\"operationType\":\"terms\",\"scale\":\"ordinal\",\"sourceField\":\"WINDOW\",\"isBucketed\":true,\"params\":{\"size\":5,\"orderBy\":{\"type\":\"column\",\"columnId\":\"7b11f852-c290-4f32-a96f-2f5b491aab6f\"},\"orderDirection\":\"desc\",\"otherBucket\":true,\"missingBucket\":false},\"customLabel\":true},\"7b11f852-c290-4f32-a96f-2f5b491aab6f\":{\"label\":\"Bad Auth Count\",\"dataType\":\"number\",\"operationType\":\"max\",\"sourceField\":\"BAD_AUTH_COUNT\",\"isBucketed\":false,\"scale\":\"ratio\",\"customLabel\":true},\"e7e10b7b-e0ad-4fa0-b27b-00a03d2f4b44\":{\"label\":\"User\",\"dataType\":\"string\",\"operationType\":\"terms\",\"scale\":\"ordinal\",\"sourceField\":\"USER.keyword\",\"isBucketed\":true,\"params\":{\"size\":3,\"orderBy\":{\"type\":\"column\",\"columnId\":\"7b11f852-c290-4f32-a96f-2f5b491aab6f\"},\"orderDirection\":\"desc\",\"otherBucket\":true,\"missingBucket\":false},\"customLabel\":true}},\"columnOrder\":[\"e7e10b7b-e0ad-4fa0-b27b-00a03d2f4b44\",\"5295bf5f-8eb7-4d9f-99d1-e46c19d757de\",\"7b11f852-c290-4f32-a96f-2f5b491aab6f\"],\"incompleteColumns\":{}}}}}}},\"enhancements\":{}}},{\"version\":\"7.15.2\",\"type\":\"lens\",\"gridData\":{\"x\":24,\"y\":0,\"w\":24,\"h\":15,\"i\":\"9182bf5f-ffd5-43d0-873a-ca272cca90a0\"},\"panelIndex\":\"9182bf5f-ffd5-43d0-873a-ca272cca90a0\",\"embeddableConfig\":{\"attributes\":{\"title\":\"\",\"visualizationType\":\"lnsXY\",\"type\":\"lens\",\"references\":[{\"type\":\"index-pattern\",\"id\":\"'${content}'\",\"name\":\"indexpattern-datasource-current-indexpattern\"},{\"type\":\"index-pattern\",\"id\":\"'${content}'\",\"name\":\"indexpattern-datasource-layer-0006cb13-75e8-4822-94e0-8051d2f9cfee\"}],\"state\":{\"visualization\":{\"legend\":{\"isVisible\":true,\"position\":\"right\"},\"valueLabels\":\"hide\",\"fittingFunction\":\"None\",\"yRightExtent\":{\"mode\":\"full\"},\"axisTitlesVisibilitySettings\":{\"x\":true,\"yLeft\":true,\"yRight\":true},\"tickLabelsVisibilitySettings\":{\"x\":true,\"yLeft\":true,\"yRight\":true},\"labelsOrientation\":{\"x\":0,\"yLeft\":0,\"yRight\":0},\"gridlinesVisibilitySettings\":{\"x\":true,\"yLeft\":true,\"yRight\":true},\"preferredSeriesType\":\"bar_stacked\",\"layers\":[{\"layerId\":\"0006cb13-75e8-4822-94e0-8051d2f9cfee\",\"seriesType\":\"bar_stacked\",\"xAccessor\":\"b7ff79ad-6831-4ddf-82d0-2632ab5f926e\",\"splitAccessor\":\"d8059608-e964-439c-a101-98f252700b17\",\"accessors\":[\"821d7895-a9d8-41c2-8a11-aeb50e430544\"],\"layerType\":\"data\"}]},\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filters\":[],\"datasourceStates\":{\"indexpattern\":{\"layers\":{\"0006cb13-75e8-4822-94e0-8051d2f9cfee\":{\"columns\":{\"d8059608-e964-439c-a101-98f252700b17\":{\"label\":\"User\",\"dataType\":\"string\",\"operationType\":\"terms\",\"scale\":\"ordinal\",\"sourceField\":\"USER.keyword\",\"isBucketed\":true,\"params\":{\"size\":3,\"orderBy\":{\"type\":\"column\",\"columnId\":\"821d7895-a9d8-41c2-8a11-aeb50e430544\"},\"orderDirection\":\"desc\",\"otherBucket\":true,\"missingBucket\":false},\"customLabel\":true},\"b7ff79ad-6831-4ddf-82d0-2632ab5f926e\":{\"label\":\"Window\",\"dataType\":\"string\",\"operationType\":\"terms\",\"scale\":\"ordinal\",\"sourceField\":\"WINDOW\",\"isBucketed\":true,\"params\":{\"size\":10,\"orderBy\":{\"type\":\"column\",\"columnId\":\"821d7895-a9d8-41c2-8a11-aeb50e430544\"},\"orderDirection\":\"desc\",\"otherBucket\":true,\"missingBucket\":false},\"customLabel\":true},\"821d7895-a9d8-41c2-8a11-aeb50e430544\":{\"label\":\"Bad Auth Count\",\"dataType\":\"number\",\"operationType\":\"max\",\"sourceField\":\"BAD_AUTH_COUNT\",\"isBucketed\":false,\"scale\":\"ratio\",\"customLabel\":true}},\"columnOrder\":[\"d8059608-e964-439c-a101-98f252700b17\",\"b7ff79ad-6831-4ddf-82d0-2632ab5f926e\",\"821d7895-a9d8-41c2-8a11-aeb50e430544\"],\"incompleteColumns\":{}}}}}}},\"enhancements\":{}}},{\"version\":\"7.15.2\",\"type\":\"lens\",\"gridData\":{\"x\":0,\"y\":15,\"w\":24,\"h\":15,\"i\":\"1675c3b0-b192-4450-99fd-bb51c15115ee\"},\"panelIndex\":\"1675c3b0-b192-4450-99fd-bb51c15115ee\",\"embeddableConfig\":{\"attributes\":{\"title\":\"\",\"visualizationType\":\"lnsPie\",\"type\":\"lens\",\"references\":[{\"type\":\"index-pattern\",\"id\":\"'${content}'\",\"name\":\"indexpattern-datasource-current-indexpattern\"},{\"type\":\"index-pattern\",\"id\":\"'${content}'\",\"name\":\"indexpattern-datasource-layer-c5750222-81de-4755-9d60-87e5f314671b\"}],\"state\":{\"visualization\":{\"shape\":\"donut\",\"layers\":[{\"layerId\":\"c5750222-81de-4755-9d60-87e5f314671b\",\"groups\":[\"0ab8c4b3-0020-4fc5-b99f-28ece27d484a\"],\"metric\":\"0e76a0d6-4b3b-4687-afe6-e12148a0a890\",\"numberDisplay\":\"percent\",\"categoryDisplay\":\"default\",\"legendDisplay\":\"default\",\"nestedLegend\":false,\"layerType\":\"data\"}]},\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filters\":[],\"datasourceStates\":{\"indexpattern\":{\"layers\":{\"c5750222-81de-4755-9d60-87e5f314671b\":{\"columns\":{\"0ab8c4b3-0020-4fc5-b99f-28ece27d484a\":{\"label\":\"Top values of USER.keyword\",\"dataType\":\"string\",\"operationType\":\"terms\",\"scale\":\"ordinal\",\"sourceField\":\"USER.keyword\",\"isBucketed\":true,\"params\":{\"size\":5,\"orderBy\":{\"type\":\"column\",\"columnId\":\"0e76a0d6-4b3b-4687-afe6-e12148a0a890\"},\"orderDirection\":\"desc\",\"otherBucket\":true,\"missingBucket\":false}},\"0e76a0d6-4b3b-4687-afe6-e12148a0a890\":{\"label\":\"95th percentile of BAD_AUTH_COUNT\",\"dataType\":\"number\",\"operationType\":\"percentile\",\"sourceField\":\"BAD_AUTH_COUNT\",\"isBucketed\":false,\"scale\":\"ratio\",\"params\":{\"percentile\":95}}},\"columnOrder\":[\"0ab8c4b3-0020-4fc5-b99f-28ece27d484a\",\"0e76a0d6-4b3b-4687-afe6-e12148a0a890\"],\"incompleteColumns\":{}}}}}}},\"enhancements\":{}}}]",
            "optionsJSON": "{\"useMargins\":true,\"syncColors\":false,\"hidePanelTitles\":false}",
            "version": 1,
            "timeRestore": false,
            "kibanaSavedObjectMeta": {
            "searchSourceJSON": "{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"
            }
        },
        "references": [
            {
            "type": "index-pattern",
            "id": "'${content}'",
            "name": "de8d829b-cacd-4d82-8f63-afbdf2cf3804:indexpattern-datasource-current-indexpattern"
            },
            {
            "type": "index-pattern",
            "id": "'${content}'",
            "name": "de8d829b-cacd-4d82-8f63-afbdf2cf3804:indexpattern-datasource-layer-d97567e7-530b-400f-a62a-515682887a78"
            },
            {
            "type": "index-pattern",
            "id": "'${content}'",
            "name": "9182bf5f-ffd5-43d0-873a-ca272cca90a0:indexpattern-datasource-current-indexpattern"
            },
            {
            "type": "index-pattern",
            "id": "'${content}'",
            "name": "9182bf5f-ffd5-43d0-873a-ca272cca90a0:indexpattern-datasource-layer-0006cb13-75e8-4822-94e0-8051d2f9cfee"
            },
            {
            "type": "index-pattern",
            "id": "'${content}'",
            "name": "1675c3b0-b192-4450-99fd-bb51c15115ee:indexpattern-datasource-current-indexpattern"
            },
            {
            "type": "index-pattern",
            "id": "'${content}'",
            "name": "1675c3b0-b192-4450-99fd-bb51c15115ee:indexpattern-datasource-layer-c5750222-81de-4755-9d60-87e5f314671b"
            }
        ],
        "migrationVersion": {
            "dashboard": "7.15.0"
        },
        "coreMigrationVersion": "7.15.2"
        },
        {
        "id": "'${content}'",
        "type": "index-pattern",
        "namespaces": [
            "default"
        ],
        "updated_at": "2021-12-09T13:11:21.340Z",
        "version": "WzE3MjAsMV0=",
        "attributes": {
            "fieldAttrs": "{\"WINDOW_END_DATE\":{\"count\":3},\"WINDOW_START_DATE\":{\"count\":1}}",
            "title": "ssh_bad_auth_count",
            "fields": "[{\"count\":1,\"script\":\"doc[\\\"WINDOW_START\\\"].value\",\"name\":\"WINDOW_START_DATE\",\"type\":\"date\",\"scripted\":true,\"searchable\":true,\"aggregatable\":true,\"readFromDocValues\":false},{\"count\":3,\"script\":\"doc[\\\"WINDOW_END\\\"].value\",\"name\":\"WINDOW_END_DATE\",\"type\":\"date\",\"scripted\":true,\"searchable\":true,\"aggregatable\":true,\"readFromDocValues\":false},{\"count\":0,\"script\":\"long epocWS = doc[\\\"WINDOW_START\\\"].value;\\nlong epocWE = doc[\\\"WINDOW_END\\\"].value;\\n\\nInstant instantWS = Instant.ofEpochMilli(epocWS);\\nInstant instantWE = Instant.ofEpochMilli(epocWE);\\nDateTimeFormatter DATE_TIME_FORMATTER = DateTimeFormatter.ofPattern(\\\"yyyy-MM-dd HH:mm:ss\\\")\\n    .withZone(ZoneId.of(\\\"Europe/Paris\\\"));\\n            \\nString begin = DATE_TIME_FORMATTER.format(instantWS);\\nString end = DATE_TIME_FORMATTER.format(instantWE);\\n\\nreturn begin + \\\"/\\\" + end;\",\"name\":\"WINDOW\",\"type\":\"string\",\"scripted\":true,\"searchable\":true,\"aggregatable\":true,\"readFromDocValues\":false}]",
            "fieldFormatMap": "{\"WINDOW_START_DATE\":{\"id\":\"date\",\"params\":{\"pattern\":\"LLL\"}},\"WINDOW_END_DATE\":{\"id\":\"date\",\"params\":{\"parsedUrl\":{\"origin\":\"http://localhost:5601\",\"pathname\":\"/app/management/kibana/indexPatterns\",\"basePath\":\"\"},\"pattern\":\"LLL\",\"timezone\":\"Browser\"}},\"WINDOW\":{\"id\":\"string\",\"params\":{\"parsedUrl\":{\"origin\":\"http://localhost:5601\",\"pathname\":\"/app/management/kibana/indexPatterns\",\"basePath\":\"\"},\"pattern\":\"0,0.[000]\"}}}",
            "typeMeta": "{}",
            "runtimeFieldMap": "{}"
        },
        "references": [],
        "migrationVersion": {
            "index-pattern": "7.11.0"
        },
        "coreMigrationVersion": "7.15.2"
        }
    ]
  }' \
    "http://localhost:5601/api/kibana/dashboards/import?exclude=index-pattern" | jq -r '.objects[0].id'))

log "Try to connect with a wrong password on ssh endoint localhost:7022"
log "<ssh test@localhost -p 7022> or <ssh admin@localhost -p 7022>"
log "Explore in parallel Kibana dashboarding at http://localhost:5601/app/dashboards#/view/${dashboardId}?_g=(filters:!(),refreshInterval:(pause:!f,value:2000),time:(from:now-15m,to:now)) to show in real time metrics on SSH failure connections"