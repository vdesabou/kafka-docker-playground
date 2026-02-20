#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "8.0.99"
then
     logerror "CP 8.1.1 is required to have support for value.converter.value.schema.id.serializer configuration property"
     exit 1
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"
log "Generating data"
docker exec -i connect bash -c "mkdir -p /tmp/kafka-connect/examples/ && curl -sSL -k 'https://api.mockaroo.com/api/17c84440?count=10&key=25fd9c80' -o /tmp/kafka-connect/examples/file.json"

log "Creating FileStream Source connector"
playground connector create-or-update --connector filestream-source  << EOF
{
    "tasks.max": "1",
    "connector.class": "org.apache.kafka.connect.file.FileStreamSourceConnector",
    "topic": "filestream",
    "file": "/tmp/kafka-connect/examples/file.json",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081",
    "value.converter.value.schema.id.serializer": "io.confluent.kafka.serializers.schema.id.HeaderSchemaIdSerializer",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF

sleep 5

log "Verify we have received the data in filestream topic"
playground topic consume --topic filestream --min-expected-messages 5 --timeout 60

# 14:16:11 ℹ️ Verify we have received the data in filestream topic
# 14:16:17 ℹ️ ✨ Display content of topic filestream, it contains 9 messages
# 14:16:17 ℹ️ 🔮🙅 topic is not using any schema for key
# 14:16:18 ℹ️ 🔮🔰 topic is using avro for value
# 14:16:19 ℹ️ 🔰 subject filestream-value 💯 version 1 (id 1)
# "string"
# CreateTime:2026-02-20 14:15:59.954|Partition:0|Offset:0|Headers:__value_schema_id:      ]q�Uk�^3|Key:|Value:|ValueSchemaId:
# �u��]|null|"{\"id\":1,\"first_name\":\"Uriel\",\"last_name\":\"Slate\",\"email\":\"uslate0@ow.ly\",\"gender\":\"Male\",\"ip_address\":\"151.99.146.85\",\"last_login\":\"2019-03-21T22:29:38Z\",\"account_balance\":10996.24,\"country\":\"JP\",\"favorite_color\":\"#f3daf4\"}"|095d71cf-1255-6b9d-5e33-0ad575b3df5d
# CreateTime:2026-02-20 14:15:59.955|Partition:0|Offset:1|Headers:__value_schema_id:      ]q�Uk�^3|Key:|Value:|ValueSchemaId:
# �u��]|null|"{\"id\":2,\"first_name\":\"Hamid\",\"last_name\":\"Waterfall\",\"email\":\"hwaterfall1@behance.net\",\"gender\":\"Male\",\"ip_address\":\"210.24.183.179\",\"last_login\":\"2018-01-13T20:12:26Z\",\"account_balance\":19326.19,\"country\":\"CM\",\"favorite_color\":\"#ac2200\"}"|095d71cf-1255-6b9d-5e33-0ad575b3df5d
# CreateTime:2026-02-20 14:15:59.955|Partition:0|Offset:2|Headers:__value_schema_id:      ]q�Uk�^3|Key:|Value:|ValueSchemaId:
# �u��]|null|"{\"id\":3,\"first_name\":\"Nannie\",\"last_name\":\"Bouch\",\"email\":\"nbouch2@usda.gov\",\"gender\":\"Female\",\"ip_address\":\"239.190.85.230\",\"last_login\":\"2017-07-13T23:17:44Z\",\"account_balance\":4877.04,\"country\":\"PH\",\"favorite_color\":\"#a7db3c\"}"|095d71cf-1255-6b9d-5e33-0ad575b3df5d
# CreateTime:2026-02-20 14:15:59.955|Partition:0|Offset:3|Headers:__value_schema_id:      ]q�Uk�^3|Key:|Value:|ValueSchemaId:
# �u��]|null|"{\"id\":4,\"first_name\":\"Traci\",\"last_name\":\"Bonnyson\",\"email\":\"tbonnyson3@gizmodo.com\",\"gender\":\"Female\",\"ip_address\":\"156.168.16.251\",\"last_login\":\"2017-01-24T03:47:01Z\",\"account_balance\":12354.74,\"country\":\"SE\",\"favorite_color\":\"#9190b2\"}"|095d71cf-1255-6b9d-5e33-0ad575b3df5d
# CreateTime:2026-02-20 14:15:59.955|Partition:0|Offset:4|Headers:__value_schema_id:      ]q�Uk�^3|Key:|Value:|ValueSchemaId:
# �u��]|null|"{\"id\":5,\"first_name\":\"Patrizia\",\"last_name\":\"Barkshire\",\"email\":\"pbarkshire4@reuters.com\",\"gender\":\"Female\",\"ip_address\":\"35.109.125.176\",\"last_login\":\"2017-10-25T13:14:37Z\",\"account_balance\":6172.62,\"country\":\"SE\",\"favorite_color\":\"#a982b6\"}"|095d71cf-1255-6b9d-5e33-0ad575b3df5d
# CreateTime:2026-02-20 14:15:59.955|Partition:0|Offset:5|Headers:__value_schema_id:      ]q�Uk�^3|Key:|Value:|ValueSchemaId:
# �u��]|null|"{\"id\":6,\"first_name\":\"Janina\",\"last_name\":\"Tunstall\",\"email\":\"jtunstall5@jalbum.net\",\"gender\":\"Female\",\"ip_address\":\"145.71.214.124\",\"last_login\":\"2017-04-21T19:55:14Z\",\"account_balance\":15797.34,\"country\":\"MA\",\"favorite_color\":\"#432edc\"}"|095d71cf-1255-6b9d-5e33-0ad575b3df5d
# CreateTime:2026-02-20 14:15:59.955|Partition:0|Offset:6|Headers:__value_schema_id:      ]q�Uk�^3|Key:|Value:|ValueSchemaId:
# �u��]|null|"{\"id\":7,\"first_name\":\"Prudy\",\"last_name\":\"Chaperling\",\"email\":\"pchaperling6@fotki.com\",\"gender\":\"Female\",\"ip_address\":\"95.209.150.57\",\"last_login\":\"2014-05-02T14:01:20Z\",\"account_balance\":6248.91,\"country\":\"CA\",\"favorite_color\":\"#09850c\"}"|095d71cf-1255-6b9d-5e33-0ad575b3df5d
# CreateTime:2026-02-20 14:15:59.955|Partition:0|Offset:7|Headers:__value_schema_id:      ]q�Uk�^3|Key:|Value:|ValueSchemaId:
# �u��]|null|"{\"id\":8,\"first_name\":\"Tabbie\",\"last_name\":\"La Vigne\",\"email\":\"tlavigne7@devhub.com\",\"gender\":\"Male\",\"ip_address\":\"122.179.126.185\",\"last_login\":\"2016-05-28T04:46:48Z\",\"account_balance\":18076.19,\"country\":\"KR\",\"favorite_color\":\"#d58e57\"}"|095d71cf-1255-6b9d-5e33-0ad575b3df5d
# CreateTime:2026-02-20 14:15:59.955|Partition:0|Offset:8|Headers:__value_schema_id:      ]q�Uk�^3|Key:|Value:|ValueSchemaId:
# �u��]|null|"{\"id\":9,\"first_name\":\"Allene\",\"last_name\":\"Gascoyen\",\"email\":\"agascoyen8@sfgate.com\",\"gender\":\"Female\",\"ip_address\":\"6.171.2.158\",\"last_login\":\"2015-05-14T00:02:25Z\",\"account_balance\":2965.91,\"country\":\"SE\",\"favorite_color\":\"#8f7d5e\"}"|095d71cf-1255-6b9d-5e33-0ad575b3df5d