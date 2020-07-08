# Couchbase Source connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-couchbase-source/asciinema.gif?raw=true)

## Objective

Quickly test [Couchbase Source](https://docs.couchbase.com/kafka-connector/3.4/index.html) connector.




## How to run

Simply run:

```
$ ./couchbase.sh
```

Note: if you want to test with a custom `couchbase.event.filter` class, use:

```
$ ./couchbase-with-key-filter.sh
```

It will filter using key starting with `airline`

Note: if you want to test with some [SMT](https://docs.confluent.io/current/connect/transforms/index.html) `ExtractTopic$Key` and `RegexRouter`, use:

```
$ ./couchbase-with-transforms.sh
```

The transforms are defined with:

```json
"transforms": "KeyExample,dropSufffix",
"transforms.KeyExample.type": "io.confluent.connect.transforms.ExtractTopic$Key",
"transforms.KeyExample.skip.missing.or.null": "true",
"transforms.dropSufffix.type": "org.apache.kafka.connect.transforms.RegexRouter",
"transforms.dropSufffix.regex": "(.*)_.*",
"transforms.dropSufffix.replacement": "$1"
```

By using `ExtractTopic$Key`, the intermediate output topic will be the key, example `landmark_16320`or `airline_5268`
By then using `RegexRouter`defiined above, the final output topics will be `landmark`or `airline`

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
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
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
                    "couchbase.event.filter": "com.couchbase.connect.kafka.filter.AllPassFilter",
                    "couchbase.stream_from": "SAVED_OFFSET_OR_BEGINNING",
                    "couchbase.compression": "ENABLED",
                    "couchbase.flow_control_buffer": "128m",
                    "couchbase.persistence_polling_interval": "100ms"
          }' \
     http://localhost:8083/connectors/couchbase-source/config | jq .
```

Verifying topic `test-travel-sample`

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-travel-sample --from-beginning --max-messages 2
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

Results with `couchbase.event.filter=example.KeyFilter`:

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

Results with `SMTs`:

Verifying topic `airline`

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic airline --from-beginning --max-messages 1
```

```json
{
    "bucket": {
        "string": "travel-sample"
    },
    "bySeqno": 1,
    "cas": 1574783851504664576,
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
        "long": 279582906597089
    }
}
```

Verifying topic `airport`

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic airport --from-beginning --max-messages 1
```

```json
{
    "bucket": {
        "string": "travel-sample"
    },
    "bySeqno": 1,
    "cas": 1574783852721537024,
    "content": {
        "bytes": "{\"airportname\":\"Phillips Aaf\",\"city\":\"Aberdeen\",\"country\":\"United States\",\"faa\":\"APG\",\"geo\":{\"alt\":57.0,\"lat\":39.466219,\"lon\":-76.168808},\"icao\":\"KAPG\",\"id\":3772,\"type\":\"airport\",\"tz\":\"America/New_York\"}"
    },
    "event": "mutation",
    "expiration": {
        "int": 0
    },
    "flags": {
        "int": 33554432
    },
    "key": "airport_3772",
    "lockTime": {
        "int": 0
    },
    "partition": 514,
    "revSeqno": 1,
    "vBucketUuid": {
        "long": 277614761974054
    }
}
```

Verifying topic `hotel`

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic hotel --from-beginning --max-messages 1
```

```json
{"event":"mutation","partition":513,"key":"hotel_28958","cas":1574783858329911296,"bySeqno":1,"revSeqno":1,"expiration":{"int":0},"flags":{"int":33554432},"lockTime":{"int":0},"content":{"bytes":"{\"address\":\"Church Road, Cilybebyll, Pontardawe, SA8 3JR\",\"alias\":null,\"checkin\":null,\"checkout\":null,\"city\":\"Rhos\",\"country\":\"United Kingdom\",\"description\":\"2 self catering cottages,  sleeping 6 and 4-5 respectively.  Located in a very quiet hamlet, above the Swansea and Neath Valleys.  4* graded cottages, free Wi Fi, off road parking, cycle storage.  15 minutes from the M4 at Neath or Swansea.\",\"directions\":\"Easy access from the M4, Neath / Swansea\",\"email\":\"rees.lloyd@btinternet.com\",\"fax\":null,\"free_breakfast\":true,\"free_internet\":false,\"free_parking\":true,\"geo\":{\"accuracy\":\"APPROXIMATE\",\"lat\":51.72672,\"lon\":-3.82077},\"id\":28958,\"name\":\"Tan yr Eglwys Cottages\",\"pets_ok\":true,\"phone\":\"+44 1792 863367\",\"price\":\"Â£\",\"public_likes\":[],\"reviews\":[{\"author\":\"Roel Konopelski\",\"content\":\"Upon most encounters with slovenly appearances, most would amend, fearing the thrifty and gaping caverns of dues to be paid. However, there is a crossing point: precisely where this slum seemed to have leaped off the pylons of great hotels, creating a tourist-friendly New York stay into paralytic asphyxiation of horror. It looms precariously on it's two-star rating. The distraught condition of drug predators and illegals cramming their holed guts into the trickling walls probably purchased the minimal rating. To this corroded stature of suckitude, I may ask to command you a simple trot away, scorchingly applying pressure to the gas pedal. First off, the \\\"lobby\\\" is a tight and small space... just like the stairway/room/elevator. Our room had no form of heating in the brutal cold of Manhattan. The bathroom door did not lock, \\\"great\\\". The bed was FILTHY!! STAINS! STAINS! HAIR ON THE BED! My goodness... there is no standards for this dump. The doors have stains... i don't know what it is? Mold? Feces? Basically, the room we had checked in online for about half a week was canceled the first hour we were there and the whole hour we were there was trying to book another hotel.\",\"date\":\"2014-05-11 12:16:46 +0300\",\"ratings\":{\"Cleanliness\":1.0,\"Location\":1.0,\"Overall\":1.0,\"Rooms\":1.0,\"Service\":1.0,\"Sleep Quality\":1.0,\"Value\":1.0}},{\"author\":\"Aidan Kuhlman\",\"content\":\"Wow, the reviews are so bad, I feel like I need to stand up for this place. Look, it's not the Four Seasons, but for the price, it's really a decent place. We were close to everything, from sightseeing to shopping to dinning to the broadway shows. Rooms were small, but clean. The front desk agents there are super friendly and having wifi helped. So my friends and I had a good time and saved a bunch, so it was all good.\",\"date\":\"2015-02-24 13:52:39 +0300\",\"ratings\":{\"Cleanliness\":5.0,\"Location\":5.0,\"Overall\":4.0,\"Rooms\":4.0,\"Service\":5.0,\"Sleep Quality\":4.0,\"Value\":5.0}},{\"author\":\"Manuel Hudson V\",\"content\":\"better to sleep on the street you do not have a lobby and extra charges for everything if been there once you will never come back there\",\"date\":\"2013-12-20 11:20:06 +0300\",\"ratings\":{\"Cleanliness\":1.0,\"Location\":4.0,\"Overall\":1.0,\"Rooms\":1.0,\"Service\":2.0,\"Sleep Quality\":1.0,\"Value\":1.0}},{\"author\":\"Camden Durgan\",\"content\":\"I booked this hotel to be next to the place my girlfriend was interviewing at. We walked into the room and wanted to vomit. There were worn spots and stains on the sheets and urine staining (clearly from decades of men missing the toilet) on the bathroom floor, and a spongelike mold growing out of the \\\"drain\\\" of the \\\"jet\\\" tub. It was absolutely disgusting. AND...even though we walked in and walked right back out.....they would NOT refund our money. It was worth it to call hotels.com and find a great place at Broadway Plaza Hotel for only $10.00 more a night. I would stay very very far away. Bed bugs, urine, and who knows what other things lurk here. I've stayed in placed with cockroaches and ants crawling the walls that were better than this place.....\",\"date\":\"2014-11-07 00:05:13 +0300\",\"ratings\":{\"Cleanliness\":1.0,\"Location\":3.0,\"Overall\":1.0,\"Rooms\":1.0,\"Service\":2.0,\"Value\":1.0}},{\"author\":\"Dr. Kay Bednar\",\"content\":\"Finally I found somewhere I could write a review about this place to save others our pain. I see now on their website they have renovated somewhat. WE were NOT told at the time of our booking they were in the middle of renovations. Courtesy would at least grant that and give us the choice. Hopefully they have changed their ways but after reading latest reviews perhaps not. Towels were dirty, bathroom floor was dirty and room was dirty. I had to clean the bath before I could use it. Bed was hard, bedding disgusting. Glad it was a brief trip. They tried to put us in a room that had just been painted and the window didn't open at first. Then we asked for another room which had patches of carpet on the floor. Forget this hotel if you are light sleeper, tile floors line the hallways and suitcases rolling on the floors are noisy as is anyone walking by. We were on a tight budget and had to be in NYC that day. For around $170 at the time what a rip off!!!! I will go without food and save money to stay in a decent place and thankfully we have since found other hotels better quality for a cheaper price. Oh and yes there is no elevator and if they didn't have my credit card number I would have left on arrival after seeing the foyer!\",\"date\":\"2015-09-27 11:56:53 +0300\",\"ratings\":{\"Cleanliness\":1.0,\"Location\":1.0,\"Overall\":1.0,\"Rooms\":1.0,\"Service\":1.0,\"Value\":1.0}},{\"author\":\"Rita Jacobi\",\"content\":\"The other reviews scared me, but I already booked this place before I read them. I don't know about all the other rooms, but our room was pretty nice (not huge), but was very comfortable. I requested a room with two queen beds and not only got 2 queens, but two singles as well! Really cool! The T.V. was small and not very many channels, but hey, we weren't there to watch T.V.! Great location. Nice folks working there. If you go there, request room 309. That was ours. Not bad at all.\",\"date\":\"2014-07-16 09:14:07 +0300\",\"ratings\":{\"Business service (e.g., internet access)\":4.0,\"Check in / front desk\":4.0,\"Cleanliness\":3.0,\"Location\":4.0,\"Overall\":3.0,\"Rooms\":3.0,\"Value\":3.0}},{\"author\":\"Dejuan Feil\",\"content\":\"Was expecting hotel to be poor if not terrible after reading reviews on trip advisor. Was not prepared for what we discovered. Nobody even heard of the hotel, bugs in the rooms, rooms not cleaned, leaking toilet, very noisy etc and the receptionist advised us we were getting the best room in the hotel. A joke ! Don`t know how they are even allowes keep this place opened. Awful !!!! We spent very little time in the hotel but still would not dream of reccomending it what so ever. Worst hotel I have ever come accross !!!!!!!!!!!! Don`t book it !!!\",\"date\":\"2013-04-07 10:29:26 +0300\",\"ratings\":{\"Check in / front desk\":1.0,\"Cleanliness\":1.0,\"Location\":5.0,\"Overall\":1.0,\"Rooms\":1.0,\"Service\":1.0,\"Value\":1.0}},{\"author\":\"Rosemary Hessel\",\"content\":\"Our recent stay to this hotel was like going camping. Someone else booked this room for us. First of all we got there in the evening. We were not sure at first if we were in the right place because when the cab driver dropped us off we thought we were walking through the back door of a restaurant. We checked in took the elevator, which only held 3 small people to our room. The hall itself was so narrow two people had to take turns walking down them. Our room had no air on upon arrival, had to open the window to plug in the AC. In the room we had to take turns walking around because it was so small. We found smashed roaches on the wall, no soap, toilet lid, shampoo, no place to put toiletries in bathroom, had to ask for towels, looks to be like they had water leaks down the walls, had a dressing table but could not use it because the stool was between the table \\u0026 bed and you could not pull out the stool. Make sure if you book here that your clothes are pressed unless you like ironing out in the hallway on attached to wall iron \\u0026 board. NIGHTMARE!\",\"date\":\"2015-01-22 03:14:03 +0300\",\"ratings\":{\"Business service (e.g., internet access)\":1.0,\"Check in / front desk\":1.0,\"Cleanliness\":1.0,\"Location\":1.0,\"Overall\":1.0,\"Rooms\":1.0,\"Service\":1.0,\"Value\":1.0}},{\"author\":\"Jesse Kessler\",\"content\":\"This hotel was the worst hotel I ever stayed in. The room was dull and cramped. The sheets were dirty and the walls stained. The staff entered our room while we were out shopping and moved us to another room. The packed our belongings in bags and moved us from two to one claiming there was a plumming problem but I demanded to see our old room to discover it was already let to new people. We had to call the police to sort the problem out he said it was a bad hotel and we should not have been there. Then on our last night I was confronted by a huge mouse in the lobby!!! The hotel manager was abusive and hung up the phone when we complained. Don't stay here. Lisa\",\"date\":\"2015-12-24 06:27:31 +0300\",\"ratings\":{\"Overall\":1.0}}],\"state\":null,\"title\":\"Swansea\",\"tollfree\":null,\"type\":\"hotel\",\"url\":\"http://www.walescottagebreaks.co.uk\",\"vacancy\":false}"},"bucket":{"string":"travel-sample"},"vBucketUuid":{"long":174881350705221}}
```

Verifying topic `landmark`

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic landmark --from-beginning --max-messages 1
```

```json
{"event":"mutation","partition":0,"key":"landmark_16320","cas":1574783860755267584,"bySeqno":1,"revSeqno":1,"expiration":{"int":0},"flags":{"int":33554432},"lockTime":{"int":0},"content":{"bytes":"{\"activity\":\"buy\",\"address\":null,\"alt\":null,\"city\":\"London\",\"content\":\"An eclectic mix of shops and restaurants, the design shops at Gabriel's Wharf are exclusively run by small businesses who design and manufacture their own products, the majority of work available will have been made by the person selling it to you. If you can't find exactly what you are looking for it is possible to commission many of the designers directly. Shops to look out for include Bicha, Game of Graces and Anne Kyyro Quinn.\",\"country\":\"United Kingdom\",\"directions\":null,\"email\":null,\"geo\":{\"accuracy\":\"APPROXIMATE\",\"lat\":51.5078,\"lon\":-0.1101},\"hours\":null,\"id\":16320,\"image\":null,\"name\":\"Gabriel's Wharf\",\"phone\":null,\"price\":null,\"state\":null,\"title\":\"London/South Bank\",\"tollfree\":null,\"type\":\"landmark\",\"url\":\"http://www.coinstreet.org/\"}"},"bucket":{"string":"travel-sample"},"vBucketUuid":{"long":80399272134877}}
```

Verifying topic `route`

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic route --from-beginning --max-messages 1
```

```
{"event":"mutation","partition":0,"key":"route_11840","cas":1574783866620674048,"bySeqno":5,"revSeqno":1,"expiration":{"int":0},"flags":{"int":33554432},"lockTime":{"int":0},"content":{"bytes":"{\"airline\":\"AS\",\"airlineid\":\"airline_439\",\"destinationairport\":\"RNO\",\"distance\":715.5809123214926,\"equipment\":\"DH4\",\"id\":11840,\"schedule\":[{\"day\":0,\"flight\":\"AS081\",\"utc\":\"12:33:00\"},{\"day\":0,\"flight\":\"AS905\",\"utc\":\"13:39:00\"},{\"day\":0,\"flight\":\"AS687\",\"utc\":\"02:40:00\"},{\"day\":1,\"flight\":\"AS059\",\"utc\":\"19:59:00\"},{\"day\":1,\"flight\":\"AS685\",\"utc\":\"18:34:00\"},{\"day\":2,\"flight\":\"AS551\",\"utc\":\"07:46:00\"},{\"day\":2,\"flight\":\"AS433\",\"utc\":\"21:09:00\"},{\"day\":2,\"flight\":\"AS187\",\"utc\":\"17:59:00\"},{\"day\":3,\"flight\":\"AS053\",\"utc\":\"10:14:00\"},{\"day\":3,\"flight\":\"AS198\",\"utc\":\"21:06:00\"},{\"day\":3,\"flight\":\"AS242\",\"utc\":\"17:14:00\"},{\"day\":3,\"flight\":\"AS431\",\"utc\":\"00:16:00\"},{\"day\":4,\"flight\":\"AS407\",\"utc\":\"16:57:00\"},{\"day\":5,\"flight\":\"AS744\",\"utc\":\"10:59:00\"},{\"day\":5,\"flight\":\"AS694\",\"utc\":\"08:54:00\"},{\"day\":6,\"flight\":\"AS588\",\"utc\":\"17:11:00\"},{\"day\":6,\"flight\":\"AS473\",\"utc\":\"21:16:00\"},{\"day\":6,\"flight\":\"AS738\",\"utc\":\"12:20:00\"},{\"day\":6,\"flight\":\"AS370\",\"utc\":\"00:37:00\"},{\"day\":6,\"flight\":\"AS881\",\"utc\":\"10:16:00\"}],\"sourceairport\":\"PDX\",\"stops\":0,\"type\":\"route\"}"},"bucket":{"string":"travel-sample"},"vBucketUuid":{"long":80399272134877}}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
