# File Pulse Source connector

## Objective

Quickly test the [File Pulse Source](https://github.com/streamthoughts/kafka-connect-file-pulse) connector.

The connector zip is downloaded from the GitHub releases (default: the latest GitHub release, falling back to `2.15.0` if GitHub cannot be reached; override with `--connector-tag`). Connector versions 2.x and later require CP 6.0 or later (JDK 11), the script exits with code 111 otherwise.

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

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) writes CSV files of musics to the `fs.listing.directory.path` of the connector of `csv.sh`, in the connect container, for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark): the columns of the dataset of the example (`title;album;duration;release;artist;type`, with a header line), and `U2` as the artist, since the `Drop` filter of the example keeps only those. The files are copied next to the folder and then moved into it, so the connector never reads a file being written. `json.sh` and `xml.sh` read one record per file or XML documents, and are refused. Once `csv.sh` is running:

```bash
# drain of 100000 records in files of 10000 records
playground connector benchmark --nb-records 100000

# throughput during 2 minutes while files of 20000 records are written
playground connector benchmark --mode steady --duration 2m --nb-records 20000
```

| Option | Load |
| --- | --- |
| `--shape bulk` (default) | files of `BENCHMARK_FILE_RECORDS` records (default `10000`) |
| `--shape small-txn` | one record per file: the cost of listing, opening and moving each file (drain only) |
| `--mode steady` | one file of `--nb-records` records per batch |
The connector lists the folder every `fs.listing.interval.ms` (`10000` in the example): a drain starts after the next listing.