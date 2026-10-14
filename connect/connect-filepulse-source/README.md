# File Pulse Source connector

## Objective

Quickly test the [File Pulse Source](https://github.com/streamthoughts/kafka-connect-file-pulse) connector.

The connector zip is downloaded from the GitHub releases (default version `2.15.0`, override with `--connector-tag`). Connector versions 2.x and later require CP 6.0 or later (JDK 11), the script exits with code 111 otherwise.

## Prerequisites

For the S3 examples only (connector version 2.0 or later):

- AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`.
- A bucket named `pgbucket<user>` is created if required (derived from `$USER`).

## How to run

```bash
playground run -f csv.sh
```

| Script | Description |
| --- | --- |
| `csv.sh` | Reads a CSV file from the local filesystem of the `connect` container |
| `json.sh` | Reads a JSON file from the local filesystem, parsed with the `JSONFilter` |
| `xml.sh` | Reads an XML file from the local filesystem with `LocalXMLFileInputReader` |
| `s3-csv.sh` | Reads a CSV file from an AWS S3 bucket with `AmazonS3RowFileInputReader` |
| `s3-json.sh` | Reads a JSON file from an AWS S3 bucket with `AmazonS3BytesArrayInputReader` |

## What the script does

Local examples (`csv.sh`, `json.sh`, `xml.sh`):

1. Downloads the connector zip and starts the environment.
2. Writes the input file in `/tmp/kafka-connect/examples/` in the `connect` container (the quickstart musics CSV dataset, a `playlists.xml` or a `track.json`).
3. Creates the FilePulse connector (`filepulse-source-csv`, `filepulse-source-xml` or `filepulse-source-json`); the CSV config comes from `connect-file-pulse-quickstart-csv-2x.json`.
4. Verifies the data with `playground topic consume` on `connect-file-pulse-quickstart-csv` (10 records), `playlists-filepulse-xml-00` or `tracks-filepulse-json-00`.

S3 examples (`s3-csv.sh`, `s3-json.sh`):

1. Creates the S3 bucket if required and uploads the CSV or JSON file.
2. Writes the AWS credentials in a `data` file mounted in the `connect` container, referenced in the connector config with the `FileConfigProvider` (`${file:/data:aws.access.key.id}`).
3. Creates the `filepulse-source-s3-csv` or `filepulse-source-s3-json` connector.
4. Verifies the data in `connect-filepulse-csv-data-records` or `tracks-filepulse-json-00` with `playground topic consume`.
