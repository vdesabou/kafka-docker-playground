# FileStream Source connector

## Objective

Quickly test the [FileStream Source](https://docs.confluent.io/platform/current/connect/filestream_connector.html) connector.

## How to run

```bash
playground run -f filestream-source.sh
```

| Script | Description |
| --- | --- |
| `filestream-source.sh` | Read lines of a JSON file in the `connect` container into a topic |

## What the script does

1. Downloads 10 sample JSON records from Mockaroo into `/tmp/kafka-connect/examples/file.json` in the `connect` container.
2. Creates the `filestream-source` connector reading that file and writing to topic `filestream`.
3. Verifies topic `filestream` with `playground topic consume`.

Example of record (each line is sent as a string):

```json
"{\"id\":1,\"first_name\":\"Rikki\",\"last_name\":\"Wedgwood\",\"email\":\"rwedgwood0@ebay.com\",\"gender\":\"Polygender\",\"ip_address\":\"247.229.211.141\",\"last_login\":\"2014-06-26T11:29:16Z\",\"account_balance\":18953.38,\"country\":\"BR\",\"favorite_color\":\"#9c2037\"}"
```
