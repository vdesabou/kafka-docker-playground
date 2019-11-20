# Couchbase Source connector

## Objective

Quickly test [Couchbase Source](https://docs.couchbase.com/kafka-connector/3.4/index.html) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)


## How to run

Simply run:

```
$ ./couchbase.sh
```

Note: if you want to test with a custom `event.filter.class` class, use:

```
$ ./couchbase-with-key-filter.sh
```

It will filter using key starting with `airline`

Couchbase UI is available at [127.0.0.1:8091](http://127.0.0.1:8091) `Administrator/password`

## Details of what the script is doing

Creating Couchbase cluster

```bash
$ docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli cluster-init --cluster-username Administrator --cluster-password password --services=data,index,query"
```

Install Couchbase bucket example `travel-sample`

```bash
$ docker exec couchbase bash -c "/opt/couchbase/bin/cbdocloader -c localhost:8091 -u Administrator -p password -b travel-sample -m 100 /opt/couchbase/samples/travel-sample.zip"
```

Creating Couchbase sink connector

```bash
$ docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "couchbase-source",
               "config": {
                    "connector.class": "com.couchbase.connect.kafka.CouchbaseSourceConnector",
                    "tasks.max": "2",
                    "topic.name": "test-travel-sample",
                    "connection.cluster_address": "couchbase",
                    "connection.timeout.ms": "2000",
                    "connection.bucket": "travel-sample",
                    "connection.username": "Administrator",
                    "connection.password": "password",
                    "use_snapshots": "false",
                    "dcp.message.converter.class": "com.couchbase.connect.kafka.handler.source.DefaultSchemaSourceHandler",
                    "event.filter.class": "com.couchbase.connect.kafka.filter.AllPassFilter",
                    "couchbase.stream_from": "SAVED_OFFSET_OR_BEGINNING",
                    "couchbase.compression": "ENABLED",
                    "couchbase.flow_control_buffer": "128m",
                    "couchbase.persistence_polling_interval": "100ms"
          }}' \
     http://localhost:8083/connectors | jq .
```

Verifying topic test-travel-sample

```bash
$ docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic test-travel-sample --from-beginning --max-messages 2
```

Results:

```json
{
    "bucket": {
        "string": "travel-sample"
    },
    "bySeqno": 1,
    "cas": 1574178029434109952,
    "content": {
        "bytes": "{\"activity\":\"see\",\"address\":null,\"alt\":\"technically not in the City\",\"city\":\"Greater London\",\"content\":\"Magnificent 19th century bridge, decorated with high towers and featuring a drawbridge. The bridge opens several times each day to permit ships to pass through \u00e2 timings are dependent on demand, and are not regularly scheduled. When Tower Bridge was built, the area to the west of it was a bustling port \u00e2 necessitating a bridge that could permit tall boats to pass. Now the South Bank area sits to its west, and the regenerated Butler's Wharf area of shops, reasonably-priced riverside restaurants and the London Design Museum lie to its east. For a small charge you can get the lift to the top level of the bridge and admire the view: this includes a visit to a museum dedicated to the bridge's history and engineering, and photographic exhibitions along the Walkways between the towers.\",\"country\":\"United Kingdom\",\"directions\":\"tube: Tower Hill\",\"email\":\"enquiries@towerbridge.org.uk\",\"geo\":{\"accuracy\":\"RANGE_INTERPOLATED\",\"lat\":51.5058,\"lon\":-0.0752},\"hours\":\"Exhibition 10AM-5PM\",\"id\":16051,\"image\":null,\"name\":\"Tower Bridge\",\"phone\":\"+44 20 7403-3761\",\"price\":\"Bridge free, exhibition \u00c2\u00a36\",\"state\":null,\"title\":\"London/City of London\",\"tollfree\":null,\"type\":\"landmark\",\"url\":\"http://www.towerbridge.org.uk/\"}"
    },
    "event": "mutation",
    "expiration": {
        "int": 0
    },
    "flags": {
        "int": 33554432
    },
    "key": "landmark_16051",
    "lockTime": {
        "int": 0
    },
    "partition": 512,
    "revSeqno": 1,
    "vBucketUuid": {
        "long": 102664342885368
    }
}


{
    "bucket": {
        "string": "travel-sample"
    },
    "bySeqno": 1,
    "cas": 1574178029849280512,
    "content": {
        "bytes": "{\"activity\":\"buy\",\"address\":null,\"alt\":null,\"city\":\"London\",\"content\":\"An eclectic mix of shops and restaurants, the design shops at Gabriel's Wharf are exclusively run by small businesses who design and manufacture their own products, the majority of work available will have been made by the person selling it to you. If you can't find exactly what you are looking for it is possible to commission many of the designers directly. Shops to look out for include Bicha, Game of Graces and Anne Kyyro Quinn.\",\"country\":\"United Kingdom\",\"directions\":null,\"email\":null,\"geo\":{\"accuracy\":\"APPROXIMATE\",\"lat\":51.5078,\"lon\":-0.1101},\"hours\":null,\"id\":16320,\"image\":null,\"name\":\"Gabriel's Wharf\",\"phone\":null,\"price\":null,\"state\":null,\"title\":\"London/South Bank\",\"tollfree\":null,\"type\":\"landmark\",\"url\":\"http://www.coinstreet.org/\"}"
    },
    "event": "mutation",
    "expiration": {
        "int": 0
    },
    "flags": {
        "int": 33554432
    },
    "key": "landmark_16320",
    "lockTime": {
        "int": 0
    },
    "partition": 0,
    "revSeqno": 1,
    "vBucketUuid": {
        "long": 259802932746954
    }
}
```

Results with `event.filter.class=example.KeyFilter`:

```json
{
    "bucket": {
        "string": "travel-sample"
    },
    "bySeqno": 1,
    "cas": 1574238314779770880,
    "content": {
        "bytes": "{\"callsign\":\"HORIZON AIR\",\"country\":\"United States\",\"iata\":\"QX\",\"icao\":\"QXE\",\"id\":2778,\"name\":\"Horizon Air\",\"type\":\"airline\"}"
    },
    "event": "mutation",
    "expiration": {
        "int": 0
    },
    "flags": {
        "int": 33554432
    },
    "key": "airline_2778",
    "lockTime": {
        "int": 0
    },
    "partition": 516,
    "revSeqno": 1,
    "vBucketUuid": {
        "long": 6995549830315
    }
}

{
    "bucket": {
        "string": "travel-sample"
    },
    "bySeqno": 1,
    "cas": 1574238314803691520,
    "content": {
        "bytes": "{\"callsign\":\"US-HELI\",\"country\":\"United States\",\"iata\":null,\"icao\":\"USH\",\"id\":5268,\"name\":\"US Helicopter\",\"type\":\"airline\"}"
    },
    "event": "mutation",
    "expiration": {
        "int": 0
    },
    "flags": {
        "int": 33554432
    },
    "key": "airline_5268",
    "lockTime": {
        "int": 0
    },
    "partition": 3,
    "revSeqno": 1,
    "vBucketUuid": {
        "long": 201263331966714
    }
}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
