#!/bin/bash

### playground topic produce demo

# https://kafka-docker-playground.io/#/playground%20topic%20produce


## Starting sasl-plain environment
playground run

## hello world example
playground topic produce --topic mytopic --consume --delete-topic --value "hello world"

## verbose
playground topic produce --topic mytopic --consume --delete-topic --value "hello world" --verbose

## showing that same command can be used with different environment, including confluent cloud
playground switch-ccloud

# same command with ccloud
playground topic produce --topic mytopic --consume --delete-topic --value "hello world" --verbose

playground switch-back


## tab completion with fzf for key and value
# --key with avro mykey.avsc
# --value with lead.avsc
playground topic produce --topic mytopic --consume --delete-topic --nb-messages 10 --value

## --no-null
# --value with lead.avsc
playground topic produce --topic mytopic --consume --delete-topic --nb-messages 10 --no-null --value

## input file redirection
playground topic produce --topic mytopic --consume --delete-topic < avro-schema.avsc

## heredoc
playground topic produce --topic mytopic --consume --delete-topic --nb-messages 3 << 'EOF'
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
      "name": "myDecimal",
      "type": [
        "null",
        {
          "logicalType": "decimal",
          "precision": 15,
          "scale": 2,
          "type": "bytes"
        }
      ]
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

## standard json
playground topic produce --topic mytopic --consume --delete-topic --nb-messages 10 << 'EOF'
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
    "record": "record%g"
  }
}
EOF

## raw data
playground topic produce --topic mytopic --consume --delete-topic --nb-messages 500 << 'EOF'
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


## json or sql format using syntax from https://github.com/MaterializeInc/datagen
playground topic produce --topic mytopic --consume --delete-topic --nb-messages 10 --value 


## key and kafka headers
playground topic produce --topic mytopic --consume --delete-topic --nb-messages 5 --key "mykey1" --headers "header1:value1,header2:value2" << 'EOF'
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

## tombstone
playground topic produce --topic mytopic --consume --tombstone --key "mykey1"

## --generate-only and --forced-value
playground topic produce --topic mytopic --delete-topic --generate-only < avro-schema.avsc

playground topic produce --topic mytopic --consume --delete-topic --nb-messages 1 --forced-value '{"count":2,"first_name":"Vincent","last_name":"Emile","address":"Aileen","createdDate":1715668821000,"myDecimal":null,"warranty_expiration":{"int":18860}}' < avro-schema.avsc

## record-size
playground topic produce --topic mytopic --consume --delete-topic --nb-messages 3 --record-size 10485760 << 'EOF'
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



##  --value-subject-name-strategy
playground topic produce --topic mytopic --consume --delete-topic --nb-messages 10 --value-subject-name-strategy TopicRecordNameStrategy < avro-schema.avsc

playground topic consume --topic mytopic --value-subject mytopic-com.github.vdesabou.Customer

## --validate
playground topic produce --topic mytopic --consume --delete-topic --nb-messages 3 --validate --validate-config scrub.invalid.names=true << 'EOF'
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

## Producing large number of messages
# –compression-codec
# –sleep-time-between-batch

playground topic produce --topic mytopic --consume --delete-topic --nb-messages -1 --record-size 1000 --key 1 < avro-schema.avsc