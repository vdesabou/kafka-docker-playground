# File Pulse Source connector

## Objective

Quickly test [File Pulse Source](https://github.com/streamthoughts/kafka-connect-file-pulse) connector.


## How to run

Simply run:

```
$ playground run -f csv<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

or

```
$ playground run -f xml<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

or

```
$ playground run -f json<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

With AWS S3:

```
$ playground run -f s3-csv<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

or

```
$ playground run -f s3-json<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Details of what the script is doing

### CSV Example


Generating data

```bash
$ docker exec -i connect bash -c "mkdir -p /tmp/kafka-connect/examples/ && curl -sSL -k https://raw.githubusercontent.com/streamthoughts/kafka-connect-file-pulse/master/datasets/quickstart-musics-dataset.csv -o /tmp/kafka-connect/examples/quickstart-musics-dataset.csv"
```

Creating CSV FilePulse Source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data @connect-file-pulse-quickstart-csv-2x.json \
     http://localhost:8083/connectors/filepulse-source-csv/config | jq .
```

Verify we have received the data in `connect-file-pulse-quickstart-csv` topic

```bash
playground topic consume --topic connect-file-pulse-quickstart-csv --min-expected-messages 10 --timeout 60
```

Results:

```json
{"title":{"string":"40"},"album":{"string":"War"},"duration":{"string":"02:38"},"release":{"string":"1983"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"Acrobat"},"album":{"string":"Achtung Baby"},"duration":{"string":"04:30"},"release":{"string":"1991"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"Bullet the Blue Sky"},"album":{"string":"The Joshua Tree"},"duration":{"string":"04:31"},"release":{"string":"1987"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"Drowning Man"},"album":{"string":"War"},"duration":{"string":"04:14"},"release":{"string":"1983"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"Even Better Than the Real Thing"},"album":{"string":"Achtung Baby"},"duration":{"string":"03:41"},"release":{"string":"1991"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"Exit"},"album":{"string":"The Joshua Tree"},"duration":{"string":"04:13"},"release":{"string":"1987"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"In God's Country"},"album":{"string":"The Joshua Tree"},"duration":{"string":"02:56"},"release":{"string":"1987"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"I Still Haven't Found What I'm Looking For"},"album":{"string":"The Joshua Tree"},"duration":{"string":"04:37"},"release":{"string":"1987"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"Like a Song..."},"album":{"string":"War"},"duration":{"string":"04:47"},"release":{"string":"1983"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
{"title":{"string":"Love is Blindness"},"album":{"string":"Achtung Baby"},"duration":{"string":"04:23"},"release":{"string":"1991"},"artist":{"string":"U2"},"type":{"string":"Rock"}}
```
### XML Example

Generating data

```bash
$ docker exec -i connect bash << EOFCONNECT
mkdir -p /tmp/kafka-connect/examples/
cat <<EOF > /tmp/kafka-connect/examples/playlists.xml
<?xml version="1.0" encoding="UTF-8"?>
<playlists>
    <playlist name="BestOfStarWars">
        <track>
            <title>Duel of the Fates</title>
            <artist>John Williams, London Symphony Orchestra</artist>
            <album>Star Wars: The Phantom Menace (Original Motion Picture Soundtrack)</album>
            <duration>4:14</duration>
        </track>
        <track>
            <title>Star Wars (Main Theme)</title>
            <artist>John Williams, London Symphony Orchestra</artist>
            <album>Star Wars: The Empire Strikes Back (Original Motion Picture Soundtrack)</album>
            <duration>10:52</duration>
        </track>
    </playlist>
</playlists>
EOF
EOFCONNECT
```

Creating CSV FilePulse Source connector

```bash
$ curl -X PUT \
        -H "Content-Type: application/json" \
        --data '{
            "connector.class":"io.streamthoughts.kafka.connect.filepulse.source.FilePulseSourceConnector",
            "fs.cleanup.policy.class": "io.streamthoughts.kafka.connect.filepulse.fs.clean.LogCleanupPolicy",
            "fs.listing.class": "io.streamthoughts.kafka.connect.filepulse.fs.LocalFSDirectoryListing",
            "fs.listing.directory.path": "/tmp/kafka-connect/examples/",
            "fs.listing.filters":"io.streamthoughts.kafka.connect.filepulse.fs.filter.RegexFileListFilter",
            "fs.listing.interval.ms": "10000",
            "file.filter.regex.pattern":".*\\.xml$",
            "tasks.reader.class": "io.streamthoughts.kafka.connect.filepulse.fs.reader.LocalXMLFileInputReader",
            "offset.strategy":"name",
            "topic":"playlists-filepulse-xml-00",
            "internal.kafka.reporter.bootstrap.servers": "broker:9092",
            "internal.kafka.reporter.topic":"connect-file-pulse-status",
            "tasks.file.status.storage.class": "io.streamthoughts.kafka.connect.filepulse.state.KafkaFileObjectStateBackingStore",
            "tasks.file.status.storage.bootstrap.servers": "broker:9092",
            "tasks.file.status.storage.topic": "connect-file-pulse-status",
            "tasks.file.status.storage.topic.partitions": 10,
            "tasks.file.status.storage.topic.replication.factor": 1,
            "tasks.max": 1
            }' \
        http://localhost:8083/connectors/filepulse-source-xml/config | jq .
```

Verify we have received the data in `playlists-filepulse-xml-00` topic

```bash
playground topic consume --topic playlists-filepulse-xml-00 --min-expected-messages 2 --timeout 60
```

Results:

```json
{"playlists":{"Playlists":{"playlist":{"io.confluent.connect.avro.Playlist":{"name":{"string":"BestOfStarWars"},"track":{"array":[{"io.confluent.connect.avro.Track":{"title":{"string":"Duel of the Fates"},"artist":{"string":"John Williams, London Symphony Orchestra"},"album":{"string":"Star Wars: The Phantom Menace (Original Motion Picture Soundtrack)"},"duration":{"string":"4:14"}}},{"io.confluent.connect.avro.Track":{"title":{"string":"Star Wars (Main Theme)"},"artist":{"string":"John Williams, London Symphony Orchestra"},"album":{"string":"Star Wars: The Empire Strikes Back (Original Motion Picture Soundtrack)"},"duration":{"string":"10:52"}}}]}}}}}}
```

### JSON Example

Generating data

```bash
$ docker exec -i connect bash << EOFCONNECT
mkdir -p /tmp/kafka-connect/examples/
cat <<EOF > /tmp/kafka-connect/examples/track.json
{
  "track": {
     "title":"Star Wars (Main Theme)",
     "artist":"John Williams, London Symphony Orchestra",
     "album":"Star Wars",
     "duration":"10:52"
  }
}
EOF
EOFCONNECT
```

Creating JSON FilePulse Source connector

```bash
$   curl -X PUT \
      -H "Content-Type: application/json" \
      --data '{
              "connector.class":"io.streamthoughts.kafka.connect.filepulse.source.FilePulseSourceConnector",
              "fs.cleanup.policy.class": "io.streamthoughts.kafka.connect.filepulse.fs.clean.DeleteCleanupPolicy",
              "fs.listing.class": "io.streamthoughts.kafka.connect.filepulse.fs.LocalFSDirectoryListing",
              "fs.listing.directory.path": "/tmp/kafka-connect/examples/",
              "fs.listing.filters":"io.streamthoughts.kafka.connect.filepulse.fs.filter.RegexFileListFilter",
              "fs.listing.interval.ms": "10000",
              "file.filter.regex.pattern":".*\\.json$",
              "tasks.reader.class": "io.streamthoughts.kafka.connect.filepulse.fs.reader.LocalBytesArrayInputReader",
              "offset.strategy":"name",
              "topic":"tracks-filepulse-json-00",
              "internal.kafka.reporter.bootstrap.servers": "broker:9092",
              "internal.kafka.reporter.topic":"connect-file-pulse-status",
              "filters": "ParseJSON",
              "filters.ParseJSON.type":"io.streamthoughts.kafka.connect.filepulse.filter.JSONFilter",
              "filters.ParseJSON.source":"message",
              "filters.ParseJSON.merge":"true",
              "tasks.file.status.storage.class": "io.streamthoughts.kafka.connect.filepulse.state.KafkaFileObjectStateBackingStore",
              "tasks.file.status.storage.bootstrap.servers": "broker:9092",
              "tasks.file.status.storage.topic": "connect-file-pulse-status",
              "tasks.file.status.storage.topic.partitions": 10,
              "tasks.file.status.storage.topic.replication.factor": 1,
              "tasks.max": 1
            }' \
      http://localhost:8083/connectors/filepulse-source-json/config | jq .
```

Verify we have received the data in `tracks-filepulse-json-00` topic

```bash
playground topic consume --topic tracks-filepulse-json-00 --min-expected-messages 1 --timeout 60
```

Results:

```json
{"message":{"bytes":"{\n  \"track\": {\n     \"title\":\"Star Wars (Main Theme)\",\n     \"artist\":\"John Williams, London Symphony Orchestra\",\n     \"album\":\"Star Wars\",\n     \"duration\":\"10:52\"\n  }\n}\n"},"track":{"Track":{"title":{"string":"Star Wars (Main Theme)"},"artist":{"string":"John Williams, London Symphony Orchestra"},"album":{"string":"Star Wars"},"duration":{"string":"10:52"}}}}
```

### JSON Example with AWS S3

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.streamthoughts.kafka.connect.filepulse.source.FilePulseSourceConnector",
          "aws.access.key.id": "${file:/data:aws.access.key.id}",
          "aws.secret.access.key": "${file:/data:aws.secret.key.id}",
          "aws.s3.bucket.name": "$AWS_BUCKET_NAME",
          "aws.s3.region": "$AWS_REGION",
          "fs.listing.class": "io.streamthoughts.kafka.connect.filepulse.fs.AmazonS3FileSystemListing",
          "fs.listing.filters":"io.streamthoughts.kafka.connect.filepulse.fs.filter.RegexFileListFilter",
          "fs.listing.interval.ms": "10000",
          "file.filter.regex.pattern":".*\\.json$",
          "offset.attributes.string": "uri",
          "tasks.reader.class": "io.streamthoughts.kafka.connect.filepulse.fs.reader.AmazonS3BytesFileInputReader",
          "offset.strategy":"name",
          "topic":"tracks-filepulse-json-00",
          "internal.kafka.reporter.bootstrap.servers": "broker:9092",
          "internal.kafka.reporter.topic":"connect-file-pulse-status",
          "fs.cleanup.policy.class": "io.streamthoughts.kafka.connect.filepulse.fs.clean.LogCleanupPolicy",
          "filters": "ParseLine",
          "filters.ParseJSON.type":"io.streamthoughts.kafka.connect.filepulse.filter.DelimitedRowFilter",
          "filters.ParseLine.extractColumnName":"headers",
          "filters.ParseLine.trimColumn":"true",
          "filters.ParseLine.separator":";",
          "tasks.file.status.storage.class": "io.streamthoughts.kafka.connect.filepulse.state.KafkaFileObjectStateBackingStore",
          "tasks.file.status.storage.bootstrap.servers": "broker:9092",
          "tasks.file.status.storage.topic": "connect-file-pulse-status",
          "tasks.file.status.storage.topic.partitions": 10,
          "tasks.file.status.storage.topic.replication.factor": 1,
          "tasks.max": 1
          }' \
     http://localhost:8083/connectors/filepulse-source-s3-json/config | jq .
```

### CSV Example with AWS S3

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.streamthoughts.kafka.connect.filepulse.source.FilePulseSourceConnector",
          "aws.access.key.id": "${file:/data:aws.access.key.id}",
          "aws.secret.access.key": "${file:/data:aws.secret.key.id}",
          "aws.s3.bucket.name": "$AWS_BUCKET_NAME",
          "aws.s3.region": "$AWS_REGION",
          "fs.listing.class": "io.streamthoughts.kafka.connect.filepulse.fs.AmazonS3FileSystemListing",
          "fs.listing.filters":"io.streamthoughts.kafka.connect.filepulse.fs.filter.RegexFileListFilter",
          "fs.listing.interval.ms": "10000",
          "file.filter.regex.pattern":".*\\.csv$",
          "skip.headers" : 1,
          "offset.attributes.string": "uri",
          "tasks.reader.class": "io.streamthoughts.kafka.connect.filepulse.fs.reader.AmazonS3RowFileInputReader",
          "topic":"connect-filepulse-csv-data-records",
          "internal.kafka.reporter.bootstrap.servers": "broker:9092",
          "internal.kafka.reporter.topic":"connect-file-pulse-status",
          "fs.cleanup.policy.class": "io.streamthoughts.kafka.connect.filepulse.fs.clean.LogCleanupPolicy",
          "filters": "ParseLine",
          "filters.ParseLine.type":"io.streamthoughts.kafka.connect.filepulse.filter.DelimitedRowFilter",
          "filters.ParseLine.extractColumnName":"headers",
          "filters.ParseLine.trimColumn":"true",
          "filters.ParseLine.separator":";",
          "tasks.file.status.storage.class": "io.streamthoughts.kafka.connect.filepulse.state.KafkaFileObjectStateBackingStore",
          "tasks.file.status.storage.bootstrap.servers": "broker:9092",
          "tasks.file.status.storage.topic": "connect-file-pulse-status",
          "tasks.file.status.storage.topic.partitions": 10,
          "tasks.file.status.storage.topic.replication.factor": 1,
          "tasks.max": 1
          }' \
     http://localhost:8083/connectors/filepulse-source-s3-csv/config | jq .
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
