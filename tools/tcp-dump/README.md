# tcp-dump

Network capture analyzer behind `playground analyze tcp-dump`, also run at the end of `playground debug tcp-dump`.

- `extract.sh` runs in the `nicolaka/netshoot` image (`tshark`, `capinfos`): it exports the fields of each packet as
  TSV files (TCP, TLS, DNS, Kafka, HTTP with the first 1000 bytes of each body). The CLI copies the capture in and the files out with `docker cp`, so nothing has to
  be installed on the host and any folder works.
- `tcp_dump_analyzer.py` reads them with the host `python3` (3.9+, standard library only), prints the text digest (or
  JSON) and writes a self-contained HTML report (inline SVG charts, works offline).

## What it reports

| Section | Content |
| --- | --- |
| Findings | refused connections (SYN answered with a reset), connections without answer, resets of established connections, retransmissions (5+ and 1%+ of the segments), zero windows, TLS alerts with their likely cause, DNS errors and slow answers, Kafka error codes (authorization ones high, the usual consumer group ones informational), slow Kafka responses, HTTP 5xx / 401 / 403 (high), 429 and other 4xx (medium) with the response body, slow HTTP endpoints, HTTP requests without response, truncated packets, encrypted traffic |
| TCP conversations | client and server (the side of the SYN, or the listening port), status, frames, bytes, handshake time (SYN → SYN/ACK), retransmissions, SYN retries |
| TLS | Client Hello per server (SNI), alerts per direction |
| DNS | errors (NXDOMAIN, SERVFAIL, REFUSED…) and answers slower than 1 s |
| Kafka | requests per API, response time p50 / p95 / max (response − request, as seen from the capture), error codes, client ids |
| HTTP | requests per server and endpoint (method + path), status codes, response time p50 / p95 / max, requests without response; each error response (per endpoint and status) with its URL and an excerpt of the request and response bodies; a sample successful exchange (what the client sends) |
| Charts | packets per second, resets and retransmissions per second, top conversations by bytes |

Kafka is decoded on 9092 (tshark default), 9093 (KRaft controller) and the host listeners of the playground
brokers (29092, 29292, 29392); `--kafka-port` adds others. HTTP is decoded on the defaults of tshark (80, 8080, 8088…)
and the usual ports of the playground (8081 to 8083, 8088, 9006 for the `httpserver` of the examples, 9021);
`--http-port` adds others. Only plain HTTP: HTTPS shows as TLS. A hosts file (`<ip> <name>` per line, the `.hosts` written
by `playground debug tcp-dump` next to each capture) shows container names instead of ip addresses.

Exit codes: `0` analysis done, `2` no packet in the capture, `1` usage or read error.

## Usage

Always go through the playground CLI:

```bash
playground analyze tcp-dump --sample kafka_and_network_errors       # try it on the samples below
playground analyze tcp-dump --sample http_errors
playground analyze tcp-dump -f customer.pcapng --kafka-port 9094     # a capture a customer sent
playground analyze tcp-dump -c connect -c broker --port 9092 --duration 1m
playground debug tcp-dump -c connect --action start                  # then --action stop: captured and analyzed
```

## Samples

| Sample | Content |
| --- | --- |
| `http_errors` | captured on an HTTP client (`playground debug tcp-dump`, 7 s, 373 packets) posting JSON records like the HTTP sink to a server on port 9006: `200` (12 requests), `429` with `Retry-After` (3), `500` (2), `401` (1), `404` (1), a 1.5 s endpoint (3) and a request that never gets a response |
| `kafka_and_network_errors` | captured on a client container (`playground debug tcp-dump`, 16 s, 180 packets): a Kafka client creating a topic, producing and consuming 200 records in a consumer group, a connection refused (`sample-broker:9999`), a connection without answer (iptables `DROP` on `sample-firewalled:8080`), a TLS 1.2 handshake rejected by a Kafka client that does not trust a self-signed certificate (`certificate_unknown`) and a DNS `NXDOMAIN` |
