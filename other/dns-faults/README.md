# DNS faults: a hostname that no longer resolves

## Objective

Showcase [`playground debug dns`](https://kafka-docker-playground.io/#/playground%20debug%20dns): fake the DNS answers of one hostname, seen from one container, without restarting anything. Here an HTTP sink connector loses the name of its HTTP server (`UnknownHostException`): its task fails at once and needs a restart once the DNS is back (the HTTP sink does not retry it, `max.retries` is for the HTTP errors: seen with 1.7.15).

🍪 Deep dive: [network traffic](https://kafka-docker-playground.io/#/deep-dive-network-traffic)

## How to run

```bash
playground run -f dns-faults<tab>
```

## What the script does

It starts the plaintext environment with the `httpserver` of the HTTP sink examples, then:

1. creates an HTTP sink connector and checks that 10 records reach `httpserver`: `tools http-server requests --min-expected-requests 10`
2. makes `httpserver` not exist for connect: `debug dns --container connect --host httpserver --nxdomain`. It waits 35 seconds, because the JVM keeps a resolved name for 30 seconds (`networkaddress.cache.ttl`), then produces 10 more records: the task fails at once with `java.net.UnknownHostException: httpserver: Name or service not known` ("Task is being killed and will not recover until manually restarted"): `connector wait --state FAILED`. `debug dns --container connect --host httpserver` shows the fault and how the name resolves now
3. goes back to the real DNS (`debug dns --container connect --reset`): the task stays FAILED. After 15 seconds (a failed lookup is cached 10 seconds, `networkaddress.cache.negative.ttl`), `connector restart` and the 10 records are delivered, 20 requests in total

## Use it in a repro

```bash
# the name does not exist, or the resolver fails
playground debug dns --container connect --host <hostname> --nxdomain
playground debug dns --container connect --host <hostname> --servfail

# the ip of a broker (or a database) changed: the clients that resolve it again go elsewhere
playground debug dns --container connect --host broker --resolve-to 10.1.2.3

# a slow resolver: from 10s on, every lookup of glibc fails (timeout:5, attempts:2)
playground debug dns --container connect --host <hostname> --delay 3s

# what is faked, how the name resolves now
playground debug dns --container connect --host <hostname>

# back to the real DNS
playground debug dns --container connect --reset
```

❕ A JVM caches the lookups (`networkaddress.cache.ttl`, 30 seconds by default, 10 seconds for a failure), and a Kafka client only resolves a broker name when it opens a connection: an established connection keeps working.
