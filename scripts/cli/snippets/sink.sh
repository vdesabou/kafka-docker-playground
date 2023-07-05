# 📥 playground topic produce (https://kafka-docker-playground.io/#/cli?id=%f0%9f%93%a5-produce)

# 💫 Magically produce to topic.

# 🔥 You can either:

# 1. Set your own schema (avro, json-schema, protobuf) with stdin (<< 'EOF')

# Json-schema

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

# AVRO

playground topic produce -t topic-avro --nb-messages 1 << 'EOF'
{
    "type": "record",
    "namespace": "com.github.vdesabou",
    "name": "Customer",
    "fields": [
        {
            "name": "count",
            "type": "long",
            "doc": "count"
        },
        {
            "name": "first_name",
            "type": "string",
            "doc": "First Name of Customer"
        },
        {
            "name": "last_name",
            "type": "string",
            "doc": "Last Name of Customer"
        },
        {
            "name": "address",
            "type": "string",
            "doc": "Address of Customer"
        }
    ]
}
EOF

# PROTOBUF

playground topic produce -t topic-proto --nb-messages 10 << 'EOF'
syntax = "proto3";

message Order {
  float         total = 1;
  repeated Item items = 2;

  message Item {
    string name  = 1;
    float  price = 2;
  }
}
EOF


# You can also generate json data using json or sql format using syntax from MaterializeInc/datagen

# JSON:

playground topic produce -t topic-json --nb-messages 5 << 'EOF'
[
    {
        "_meta": {
            "topic": "",
            "key": "",
            "relationships": [
            ]
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
        "city": "faker.address.city()",
        "company": "faker.company.name()"
    }
]
EOF


# SQL:

playground topic produce -t topic-json-sql --nb-messages 10 << 'EOF'
CREATE TABLE "notused"."notused" (
  "id" int PRIMARY KEY,
  "name" varchar COMMENT 'faker.internet.userName()',
  "merchant_id" int NOT NULL COMMENT 'faker.datatype.number()',
  "price" int COMMENT 'faker.datatype.number()',
  "status" int COMMENT 'faker.datatype.boolean()',
  "created_at" datetime DEFAULT (now())
);
EOF

# JSON with SCHEMA:

playground topic produce -t topic-json-with-schema --nb-messages 10 << 'EOF'
{
  "schema": {
    "type": "struct",
    "fields": [
      {
        "type": "string",
        "optional": false,
        "field": "record"
      }
    ]
  },
  "payload": {
    "record": "cdcd"
  }
}
EOF

# Simple records:

playground topic produce -t topic-string --nb-messages 30 << 'EOF'
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

# With key:

playground topic produce -t topic-json-multiple-lines --nb-messages 10 --key "mykey" << 'EOF'
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

# Tombstone:

playground topic produce -t topic-json-multiple-lines --key mykey --tombstone 


# ☠️ Dead Letter Queue

# If you need to add a Dead Letter Queue, you can use in connector config:

               "errors.tolerance": "all",
               "errors.deadletterqueue.topic.name": "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "errors.deadletterqueue.context.headers.enable": "true",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
