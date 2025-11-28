#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function produce () {

playground topic produce --tombstone --topic a-topic --key mykey

playground topic produce -t topic-json --nb-messages 10 << 'EOF'
{
    "_meta": {
        "topic": "",
        "key": "",
        "relationships": []
    },
    "nested": {
        "phone": "faker.phone.imei()",
        "website": "faker.internet.domainName()"
    },
    "id": "iteration.index",
    "name": "faker.internet.userName()",
    "email": "faker.internet.exampleEmail()",
    "phone": "faker.phone.imei()",
    "website": "faker.internet.domainName()",
    "city": "faker.location.city()",
    "company": "faker.company.name()"
}
EOF

playground topic produce -t topic-datagen-users --nb-messages 10 << 'EOF'
{
        "namespace": "ksql",
        "name": "users",
        "type": "record",
        "fields": [
                {"name": "registertime", "type": {
                    "type": "long",
                    "arg.properties": {
                        "range": {
                            "min": 1487715775521,
                            "max": 1519273364600
                        }
                    }
                }},
                {"name": "userid", "type": {
                    "type": "string",
                    "arg.properties": {
                        "regex": "User_[1-9]"
                    }
                }},
                {"name": "regionid", "type": {
                    "type": "string",
                    "arg.properties": {
                        "regex": "Region_[1-9]"
                    }
                }},
                {"name": "gender", "type": {
                    "type": "string",
                    "arg.properties": {
                        "options": [
                            "MALE",
                            "FEMALE",
                            "OTHER"
                        ]
                    }
                }}
        ]
}
EOF

playground  topic produce -t topic-datagen-json-schema --nb-messages 1 --value predefined-schemas/datagen/purchase.avro --derive-value-schema-as JSON 

playground topic produce -t topic-avro --nb-messages 10 << 'EOF'
{
    "fields": [
    {
        "name": "count",
        "type": "long"
    },
    {
        "name": "first_name",
        "type": "string"
    },
    {
        "name": "last_name",
        "type": "string"
    },
    {
        "default": null,
        "name": "address",
        "type": [
        "null",
        "string"
        ]
    },
    {
        "name": "last_sale_date",
        "type": {
        "logicalType": "timestamp-millis",
        "type": "long"
        }
    },
    {
        "name": "last_sale_price",
        "type": {
        "logicalType": "decimal",
        "precision": 15,
        "scale": 2,
        "type": "bytes"
        }
    },
    {
        "name": "last_connection",
        "type": {
        "logicalType": "date",
        "type": "int"
        }
    }
    ],
    "name": "Customer",
    "namespace": "com.github.vdesabou",
    "type": "record"
}
EOF

playground topic produce -t topic-json-schema --nb-messages 3 << 'EOF'
{
    "$schema": "http://json-schema.org/draft-07/schema#",
    "additionalProperties": false,
    "$id": "http://lh.test/Customer.schema.json",
    "title": "Customer",
    "description": "Customer description",
    "type": "object",
    "properties": {
    "name": {
        "description": "Customer name",
        "type": "string",
        "maxLength": 25
    },
    "surname": {
        "description": "Customer surname",
        "type": "string",
        "minLength": 2
    },
    "email": {
        "description": "Email",
        "type": "string",
        "pattern": "^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\\.[a-zA-Z0-9-.]+$"
    }
    },
    "required": [
    "name",
    "surname"
    ]
}
EOF


playground topic produce -t topic-proto --nb-messages 1 << 'EOF'
syntax = "proto3";

package com.github.vdesabou;

message Customer {
    int64 count = 1;
    string first_name = 2;
    string last_name = 3;
    string address = 4;
}
EOF

playground topic produce -t topic-jsql --nb-messages 10 << 'EOF'
CREATE TABLE "notused"."notused" (
    "id" int PRIMARY KEY,
    "name" varchar COMMENT 'faker.internet.userName()',
    "merchant_id" int NOT NULL COMMENT 'faker.number.int()',
    "price" int COMMENT 'faker.number.int()',
    "status" int COMMENT 'faker.datatype.boolean()',
    "created_at" datetime DEFAULT (now())
);
EOF

playground topic produce -t topic-string --nb-messages 5000 << 'EOF'
Ad et ut pariatur officia eos.
Nesciunt fugit nam libero ut qui itaque sed earum at itaque nesciunt eveniet atque.
Quidem libero quis quod et illum excepturi voluptas et in perspiciatis iusto neque.
Quibusdam commodi explicabo dolores molestiae qui delectus dolorum fugiat molestiae natus assumenda omnis expedita.
Et sunt aut architecto suscipit fugiat qui voluptate iure vel doloremque eum culpa.
Qui enim facilis eos similique aperiam totam eius et at dolor dolores.
Ut sunt quia qui quia consectetur aut reiciendis.
Modi adipisci iusto aut voluptatem dolores laudantium.
Sequi sint quia quibusdam molestias minus et aliquid voluptatum aliquam.
Rerum aut amet quo possimus nihil velit quisquam ut cumque.
Pariatur ad officiis voluptatibus quia vel corporis ea fugit adipisci porro.
EOF

# key and headers
# mykey1 %g can also be used
playground topic produce -t topic-json-multiple-lines --nb-messages 10 --key "mykey1" --headers "header1:value1,header2:value2" << 'EOF'
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

# avro key
playground topic produce -t topic-avro-with-key --nb-messages 10 --key '
{
    "fields": [
    {
        "name": "id",
        "type": "long"
    }
    ],
    "name": "Key",
    "namespace": "com.github.vdesabou",
    "type": "record"
}
' << 'EOF'
{
    "fields": [
    {
        "doc": "count",
        "name": "count",
        "type": "long"
    },
    {
        "doc": "First Name of Customer",
        "name": "first_name",
        "type": "string"
    },
    {
        "doc": "Last Name of Customer",
        "name": "last_name",
        "type": "string"
    }
    ],
    "name": "Customer",
    "namespace": "com.github.vdesabou",
    "type": "record"
}
EOF

# tombstone
playground topic produce -t topic-json-multiple-lines --tombstone --key "mykey1"

# input file
playground topic produce -t topic-avro-example3 < ../../scripts/cli/predefined-schemas/avro/lead.avsc

# record-size
playground topic produce -t topic-avro-example-big-size --nb-messages 1 --record-size 8300000 << 'EOF'
{
    "fields": [
    {
        "doc": "count",
        "name": "count",
        "type": "long"
    },
    {
        "doc": "First Name of Customer",
        "name": "first_name",
        "type": "string"
    },
    {
        "doc": "Last Name of Customer",
        "name": "last_name",
        "type": "string"
    },
    {
        "doc": "Address of Customer",
        "name": "address",
        "type": "string"
    }
    ],
    "name": "Customer",
    "namespace": "com.github.vdesabou",
    "type": "record"
}
EOF

# validate
set +e
playground topic produce -t topic-json-schema-validate --nb-messages 3 --validate << 'EOF'
{
    "$schema": "http://json-schema.org/draft-07/schema#",
    "additionalProperties": false,
    "$id": "http://lh.test/Customer.schema.json",
    "title": "Customer",
    "description": "Customer description",
    "type": "object",
    "properties": {
    "name": {
        "description": "Customer name",
        "type": "string",
        "maxLength": 25
    },
    "surname": {
        "description": "Customer surname",
        "type": "string",
        "minLength": 2
    },
    "email": {
        "description": "Email",
        "type": "string",
        "pattern": "^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\\.[a-zA-Z0-9-.]+$"
    },
    "holiday": {
        "oneOf": [
        {
            "title": "Not included",
            "type": "null"
        },
        {}
        ]
    },
    "f2": {}
    },
    "required": [
    "name",
    "surname"
    ]
}
EOF
set -e

#  --value-subject-name-strategy
playground topic produce -t topic-avro-example-value-subject-name-strategy --nb-messages 10 --value-subject-name-strategy TopicRecordNameStrategy << 'EOF'
{
    "fields": [
    {
        "doc": "count",
        "name": "count",
        "type": "long"
    },
    {
        "doc": "First Name of Customer",
        "name": "first_name",
        "type": "string"
    },
    {
        "doc": "Last Name of Customer",
        "name": "last_name",
        "type": "string"
    },
    {
        "doc": "Address of Customer",
        "name": "address",
        "type": "string"
    }
    ],
    "name": "Customer",
    "namespace": "com.github.vdesabou",
    "type": "record"
}
EOF

# --generate-only
playground topic produce -t topic-avro-example-forced-value --nb-messages 10  --generate-only << 'EOF'
{
    "fields": [
    {
        "doc": "count",
        "name": "count",
        "type": "long"
    },
    {
        "doc": "First Name of Customer",
        "name": "first_name",
        "type": "string"
    },
    {
        "doc": "Last Name of Customer",
        "name": "last_name",
        "type": "string"
    },
    {
        "doc": "Address of Customer",
        "name": "address",
        "type": "string"
    },
    {
        "name": "createdDate",
        "type": {
        "logicalType": "timestamp-millis",
        "type": "long"
        }
    },
    {
        "default": null,
        "name": "warranty_expiration",
        "type": [
        "null",
        {
            "logicalType": "date",
            "type": "int"
        }
        ]
    }
    ],
    "name": "Customer",
    "namespace": "com.github.vdesabou",
    "type": "record"
}
EOF

# --forced-value
playground topic produce -t topic-avro-example-forced-value --nb-messages 1 --forced-value '{"count":4,"first_name":"Vincent","last_name":"de Saboulin","address":"xxx","createdDate":1697852606000,"warranty_expiration":{"int":19653}}' << 'EOF'
{
    "fields": [
    {
        "doc": "count",
        "name": "count",
        "type": "long"
    },
    {
        "doc": "First Name of Customer",
        "name": "first_name",
        "type": "string"
    },
    {
        "doc": "Last Name of Customer",
        "name": "last_name",
        "type": "string"
    },
    {
        "doc": "Address of Customer",
        "name": "address",
        "type": "string"
    },
    {
        "name": "createdDate",
        "type": {
        "logicalType": "timestamp-millis",
        "type": "long"
        }
    },
    {
        "default": null,
        "name": "warranty_expiration",
        "type": [
        "null",
        {
            "logicalType": "date",
            "type": "int"
        }
        ]
    }
    ],
    "name": "Customer",
    "namespace": "com.github.vdesabou",
    "type": "record"
}
EOF

# --derive-value-schema-as
playground topic produce --topic fleet --value predefined-schemas/datagen/fleet_mgmt_location.avro --derive-value-schema-as AVRO --nb-messages 10000 --key predefined-schemas/datagen/fleet_mgmt_description.avro --derive-key-schema-as AVRO 
}

function consume () {
    for topic in $(playground --output-level WARN topic list)
    do
        log "📥 Consuming from topic ${topic}"
        playground topic consume --topic $topic
    done
}

for environment in plaintext ccloud; do
    log "🏗️ Starting environment for ${environment}"
    playground start-environment --environment ${environment}
    produce
    consume
    log "🧹 Stopping environment for ${environment}"
    playground stop
done
