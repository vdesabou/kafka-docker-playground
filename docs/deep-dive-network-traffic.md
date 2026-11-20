# 🍪 Deep dive: `playground debug block-traffic`, `playground debug degrade-traffic` and `playground debug dns`

The commands that break the network on purpose, so you can reproduce timeouts, outages, slow links and names that
no longer resolve, without changing the example or restarting anything. Takes about 15 minutes to read and run.

> [!TIP]
> In a hurry? Watch the short video session [🐌 A slow or broken network, on purpose](/sessions?id=🐌-a-slow-or-broken-network-on-purpose)
> first. This page goes further: how the commands work under the hood, their gotchas, a hands-on lab and recipes for
> support repros.

| | `block-traffic` 🚫 | `degrade-traffic` 🐌 |
| --- | --- | --- |
| Simulates | an outage: a firewall dropping packets, a host you can't reach | a bad network: slow, lossy, corrupted or narrow link |
| Linux tool | `iptables -A OUTPUT … -j DROP` | `tc` + `netem` (+ `prio`/`sfq` when a destination is given) |
| Runs where | `docker exec --privileged --user root` **inside** the container (installs `iptables` with `yum`/`apt` if it's missing) | a throw-away `nicolaka/netshoot` container joined to the container's network namespace (`--network container:<c>`): nothing gets installed |
| `--destination` | **required** | optional (default: all the container's traffic) |
| `--port` | optional, TCP only | optional, TCP only, needs `--destination` |
| `--action` | `start` / `stop` | `start` / `stop` / `status` |
| Shows the result | prints `iptables-save` after each call | measures the round trip (ping, or TCP connect time when `--port` is set) |
| cfk | yes, through `kubectl debug` with a netshoot ephemeral container | yes, same way |

Both commands default to `--container connect`, and `-c` can be repeated to hit several containers at once.

They work on IP addresses. To break the **name resolution** of one hostname instead (`UnknownHostException`, a broker
IP that changed, a slow resolver), see [4. `debug dns`](/deep-dive-network-traffic?id=_4-debug-dns-break-the-name-resolution-of-one-hostname).

For a client that can't reach Confluent Cloud (PrivateLink, peering, private DNS: none of it can run locally), see
[7. Confluent Cloud connectivity: a client-side checklist](/deep-dive-network-traffic?id=_7-confluent-cloud-connectivity-a-client-side-checklist).

---

## 1. Mental model (the 3 things to remember)

1. **They only act on traffic the container sends** (egress). `block-traffic -c connect --destination broker`
   stops connect → broker, but broker → connect packets still flow. Since TCP needs both directions, the
   connection dies anyway. For `degrade-traffic`, though, it means that **`--latency 100ms` adds 100 ms to the
   round trip, not 200 ms**. For a symmetric delay, degrade both sides.
2. **`DROP`, not `REJECT`**: the client gets no error back. It hangs until its own timeout
   (`request.timeout.ms`, JDBC socket timeout, HTTP read timeout…). That's what a real firewall or a dead
   host does, and it's usually the customer's symptom ("stuck", "timeout after 30s"), not "connection refused".
3. **They're reversible, and restarting the container also wipes them**: rules and qdiscs live in the
   container's network namespace. Undo them with `--action stop`. A `playground container restart` /
   `recreate` also clears them, so apply them again after a restart.

How the destination is resolved (shared helper `resolve_traffic_destination_ips`):

- an IP → used as is
- a container name → `docker inspect` IP (pod IP or service ClusterIP with cfk)
- anything else (e.g. `login.salesforce.com`) → `nslookup`, **at the time of the call**. An external
  hostname behind DNS round robin / a CDN can resolve to other IPs later, so the block can "leak". For
  those, block every IP or use `degrade-traffic` without a destination.

---

## 2. `block-traffic` in 4 commands

```bash
# cut connect from the broker (all ports)
playground debug block-traffic -c connect --destination broker --action start

# cut only TCP 9092 from schema-registry to the broker
playground debug block-traffic -c schema-registry --destination broker --port 9092 --action start

# several containers at once
playground debug block-traffic -c connect -c ksqldb-server --destination schema-registry --action start

# restore: same flags, --action stop
playground debug block-traffic -c connect --destination broker --action stop
```

Gotchas:

- **`stop` deletes the matching rule (`iptables -D`)**, so pass the **same** `--destination` / `--port` as
  for `start`. Each `start` appends one rule, and `-D` deletes only one, so if you ran `start` twice, run
  `stop` twice. The `iptables-save` printed at the end shows what is left.
- There is no `status` action. Rerun a `stop`, or look at the `iptables-save` output.
- Existing connections are hit too: `DROP` on `OUTPUT` has no exception for established connections, so a
  long-lived Kafka connection stalls right away. It doesn't wait for a reconnect.
- Installing `iptables` in a container that lacks it needs package repositories reachable from that
  container.

Real-world use in the repo: the `*-proxy.sh` examples (`connect/connect-gcp-bigtable-sink/gcp-bigtable-sink-proxy.sh`,
Salesforce `*-proxy*.sh`…) **block the direct route to the SaaS endpoint, to prove the connector really goes
through the proxy**:

```bash
IP=$(dig +short bigtableadmin.googleapis.com)
log "Blocking bigtableadmin.googleapis.com IP $IP to make sure proxy is used"
playground debug block-traffic --container connect --destination $IP --action start
```

---

## 3. `degrade-traffic` in 6 commands

```bash
# +100 ms on connect -> broker
playground debug degrade-traffic -c connect --destination broker --latency 100ms --action start

# combine effects in one call: 100 ms ± 20 ms, and 1% loss
playground debug degrade-traffic -c connect --destination broker --latency 100ms --jitter 20ms --loss 1% --action start

# only TCP 9092, on two containers
playground debug degrade-traffic -c connect -c ksqldb-server --destination broker --port 9092 --loss 5% --action start

# narrow pipe for ALL the traffic of connect (no destination)
playground debug degrade-traffic -c connect --rate 1mbit --action start

# what is applied + measured round trip
playground debug degrade-traffic -c connect --destination broker --action status

# back to normal (clears every interface of the container)
playground debug degrade-traffic -c connect -c ksqldb-server --action stop
```

Flags and accepted formats (checked before anything runs):

| Flag | Format | Example | netem keyword |
| --- | --- | --- | --- |
| `--latency` | `<n>(us\|ms\|s)` | `100ms`, `1s` | `delay` |
| `--jitter` | same, **needs `--latency`** | `20ms` | `delay <lat> <jitter>` |
| `--loss` | `<n>%` | `1%`, `0.5%` | `loss` |
| `--corruption` | `<n>%` | `1%` | `corrupt` |
| `--duplicate` | `<n>%` | `1%` | `duplicate` |
| `--rate` | `<n>(bit\|kbit\|mbit\|gbit\|bps\|kbps\|mbps\|gbps)` | `1mbit`, `500kbit` | `rate` |

How it works:

- **No destination**: `netem` becomes the root qdisc of the interface of the default route, and every packet
  the container sends is degraded.
- **With a destination**: a `prio` qdisc with two bands. Band `1:1` (destination IP, plus port if given) goes
  through `netem`, and band `1:2` (everything else, ICMP included) goes through `sfq`, untouched. That's why,
  with `--port`, the measured value is a **TCP connect time** rather than a ping: ICMP isn't degraded.
- **`start` replaces**: it first deletes the existing root qdisc. To change from 100 ms to 300 ms, just rerun
  `start` with the new value. To keep loss *and* latency, pass both in the same call.

What each effect does to Kafka clients and connectors:

| Effect | What you'll see |
| --- | --- |
| `--latency` | lower throughput per connection (more so with `acks=all`, small `batch.size`/`linger.ms`, `max.in.flight=1`), slower `poll()`, rebalances if processing + latency go over `max.poll.interval.ms` |
| `--loss` low (1–5%) | TCP retransmits: latency spikes and lower throughput, usually no errors |
| `--loss` high (30%+) | request timeouts, `NetworkException`, disconnects, a connector task that fails or retries |
| `--corruption` | the TCP checksum drops the packet, so it acts like loss |
| `--duplicate` | TCP absorbs it, mostly invisible (handy to prove it's harmless) |
| `--rate` | slow large batches / big records, timeouts on large fetches or produces, slow snapshots |

---

## 4. `debug dns`: break the name resolution of one hostname

`block-traffic` cuts an IP. Some customer symptoms are about the **name**: an `UnknownHostException` storm, a broker
that got a new IP after a pod restart while a client kept the old one, a resolver so slow that the lookups time out.
`debug dns` fakes the DNS answers of one hostname, seen from one container (or several), and every other name
resolves as usual.

```bash
# the name does not exist (NXDOMAIN): UnknownHostException
playground debug dns --container connect --host httpserver --nxdomain
# the resolver fails (SERVFAIL): "Temporary failure in name resolution"
playground debug dns --container connect --host httpserver --servfail
# the name resolves to another ip (an A record)
playground debug dns --container connect --host schema-registry --resolve-to 10.1.2.3
# the real answer, late
playground debug dns --container connect --host broker --delay 3s
# what is faked, and how --host resolves now (getent, like a JVM: the resolver of the libc)
playground debug dns --container connect --host broker
# back to the real DNS: one hostname, or everything
playground debug dns --container connect --host broker --reset
playground debug dns --container connect --reset
```

How it works:

- A small DNS proxy (`tools/debug-dns/dns_proxy.py`, standard library only) runs in a sidecar container
  `playground-debug-dns-<container>` (`python:3-alpine`), joined to the network namespace of the container
  (`--network container:<c>`), and listens on `127.0.0.53:53` (UDP and TCP).
- `/etc/resolv.conf` of the container is rewritten to `nameserver 127.0.0.53` (in place: it is a bind mount), the
  original is kept in `/tmp/playground-debug-dns-resolv.conf` of the container. Nothing is installed in the
  container, nothing restarts.
- The proxy answers the hostname (and the hostname plus a search domain) with the fault, and forwards every other
  query to the original nameservers (`127.0.0.11`, the embedded DNS of docker).
- Several hostnames can be faked at once on a container: each call adds or replaces the rule of its `--host`.
- `playground stop` removes the proxies left behind (a fault not reset before the end of the example).

Gotchas:

| Gotcha | What it means for the repro |
| --- | --- |
| A JVM caches its lookups: `networkaddress.cache.ttl` (30s by default) and `networkaddress.cache.negative.ttl` (10s) | a fault shows up to 30 seconds later in a running JVM, and stays up to 10 seconds after `--reset` |
| A Kafka client resolves a broker name when it **opens** a connection | an established connection keeps working: `--resolve-to` or `--nxdomain` on `broker` only bite at the next reconnection (force one with `block-traffic … --action start`, then `stop`) |
| An HTTP client reuses its connections (keep-alive) | same thing: the fault shows up with the next new connection |
| glibc waits 5s, sends the query again, and **still accepts a late answer** to the first one (`options timeout:5 attempts:2`) | `--delay 6s`: the lookups succeed in 6s. `--delay 12s`: every lookup fails after 10s |
| `client.dns.lookup=use_all_dns_ips` (default since Kafka 2.6) | a client tries every IP of a name: `--resolve-to` gives only one |
| A restart of the container gives it back its original `/etc/resolv.conf` | the faults are gone, the next call of the command removes the leftover proxy |
| Docker only | not with cfk yet (the command exits with an error) |

Outputs, on a container whose `httpserver` is faked:

```bash
playground debug dns --container connect --host httpserver --nxdomain
# 🚀 starting the DNS proxy of connect (playground-debug-dns-connect)
# 🔤 from connect, httpserver does not exist (NXDOMAIN)
# 🔎 from connect, httpserver does not resolve (after 38 ms)
# ❗ 🗃️ a JVM caches its lookups: networkaddress.cache.ttl (30s by default) for a success, networkaddress.cache.negative.ttl (10s) for a failure
# 🧽 back to the real DNS: playground debug dns --container connect --reset

playground debug dns --container connect --host httpserver --delay 12s
# 🔎 from connect, httpserver does not resolve (after 10061 ms)
# ❗ ⏱️ a delay of 10s or more is longer than the glibc resolver waits (options timeout:5 attempts:2): every lookup fails after 10s (UnknownHostException), before the answer comes
```

The [DNS faults example](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/dns-faults) runs it
end to end: the task of an HTTP sink fails at once on `UnknownHostException` (it does not retry it), and only
delivers the records after a `connector restart`, once the DNS is back.

---

## 5. Hands-on lab (≈10 min)

Any running example works. Here's one with just plaintext:

```bash
playground start-environment --environment plaintext
playground topic produce -t lab --nb-messages 10 --value '{"f1":"x"}'   # any small payload is fine
```

**Step 1: baseline**

```bash
playground debug degrade-traffic -c connect --destination broker --action status
# ✅ no degradation applied on container connect
# ⏱️ round trip from connect to broker: ~0.1 ms (average of 4 pings)
```

**Step 2: one-way latency**

```bash
playground debug degrade-traffic -c connect --destination broker --latency 200ms --action start
# ⏱️ round trip from connect to broker: ~200 ms      <- one-way: +200, not +400
playground debug degrade-traffic -c broker --destination connect --latency 200ms --action start
playground debug degrade-traffic -c connect --destination broker --action status
# ⏱️ ~400 ms                                         <- now symmetric
playground debug degrade-traffic -c connect -c broker --action stop
```

**Step 3: port-scoped degradation**

```bash
playground debug degrade-traffic -c connect --destination broker --port 9092 --latency 300ms --action start
# ⏱️ tcp connection time from connect to broker:9092: ~300 ms (average of 4 connections)
playground debug degrade-traffic -c connect --destination broker --action status
# ping round trip stays ~0.1 ms: ICMP is in the untouched band
playground debug degrade-traffic -c connect --action stop
```

**Step 4: outage, then recovery**

```bash
playground debug block-traffic -c connect --destination broker --action start
playground container logs -c connect --errors --since 2m      # disconnect / timeout messages show up
playground connector status                                  # if a connector is running
playground debug block-traffic -c connect --destination broker --action stop
playground container logs -c connect --errors --since 1m      # does it recover by itself?
```

The question this lab answers is usually the one in the support case: **does the component recover on its
own once the network comes back, or does it need a restart?**

**Step 5: a name that no longer resolves**

```bash
playground debug dns -c connect --host broker
# ✅ no DNS fault on connect
# 🔎 from connect, broker resolves to 192.168.112.5 (in 42 ms)
playground debug dns -c connect --host broker --nxdomain
# 🔎 from connect, broker does not resolve (after 42 ms)
playground connector status                                  # still RUNNING: connections are already open
playground debug dns -c connect --host schema-registry --resolve-to 10.1.2.3
playground debug dns -c connect
# 🔤 DNS faults on connect:
#    broker does not exist (NXDOMAIN)
#    schema-registry resolves to 10.1.2.3
playground debug dns -c connect --host broker --reset         # only broker: schema-registry stays faked
playground debug dns -c connect --reset
# 🟢 connect uses the real DNS again
```

```bash
playground stop
```

---

## 6. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "JDBC sink hangs, then `SQLRecoverableException`" | `block-traffic -c connect --destination postgres --port 5432 --action start`, wait for the socket timeout, then `stop` and check whether the task recovers |
| "connector must go through the proxy" | `block-traffic -c connect --destination <SaaS IP> --action start` (pattern of the `*-proxy.sh` examples) |
| "workers rebalance / lose the group on a slow WAN" | `degrade-traffic -c connect --destination broker --latency 500ms --jitter 200ms --action start` |
| "producer `TimeoutException` / `Expiring N record(s)`" | `degrade-traffic -c connect --destination broker --loss 30% --action start` or `--rate 256kbit` |
| "schema registry unreachable → `SerializationException`" | `block-traffic -c connect --destination schema-registry --action start` |
| "slow link to Confluent Cloud" (IPs change, so no destination) | `degrade-traffic -c connect --latency 80ms --action start` |
| "controller / quorum lost" | `block-traffic -c broker --destination controller --action start` |
| "`UnknownHostException` / `DNS resolution failed for <host>`" | `debug dns -c connect --host <host> --nxdomain` (or `--servfail`), wait more than 30s (JVM cache), then `--reset` and check whether it recovers |
| "the broker got a new IP, the client still uses the old one" | `debug dns -c connect --host broker --resolve-to <old ip>`, then force a reconnection (`block-traffic … start` / `stop`) |
| "lookups are slow / time out in a customer network" | `debug dns -c connect --host <host> --delay 3s` (slow), `--delay 12s` (every lookup fails after 10s) |

In a repro model, wrap the degraded part between `start` and `stop`, and wait with
`playground connector wait --connector <c> --state FAILED --max-wait 120` (or `RUNNING` after `stop`) instead
of `sleep`:

```bash
playground debug block-traffic -c connect --destination postgres --action start
playground connector wait --connector jdbc-sink --state FAILED --max-wait 180
playground debug block-traffic -c connect --destination postgres --action stop
playground connector restart --connector jdbc-sink   # or check that it doesn't need it
playground connector wait --connector jdbc-sink --state RUNNING --max-wait 120
```

---

## 7. Confluent Cloud connectivity: a client-side checklist

PrivateLink, VPC peering, Transit Gateway and private DNS zones can't be recreated on a laptop. Most "the client
can't reach Confluent Cloud" cases can still be narrowed down from the client side, in five checks, always in this
order: each one only makes sense once the previous one passes.

Three things to keep in mind:

1. **The bootstrap is only the first connection.** The client then connects to every broker named in the metadata,
   under its own hostname. A working bootstrap proves nothing about the brokers: DNS, routes and firewall rules must
   cover all of them.
2. **Everything is TLS, routed by SNI**: the Kafka endpoints on port 9092, and Schema Registry, the REST APIs and
   the other HTTPS endpoints on 443. The endpoint picks the cluster from the name the client sends in the TLS
   handshake. A client connecting to an IP address, or a proxy or load balancer that doesn't forward SNI (or
   terminates TLS), can't work.
3. **With private networking, names must resolve to the private endpoints of the customer's network.** If a name
   resolves to a public address, or doesn't resolve at all, the client is using the wrong DNS zone.

| # | Check | On the client host | Passes when | When it fails, the client logs |
| --- | --- | --- | --- | --- |
| 1 | DNS of the bootstrap | `nslookup <bootstrap host>` | it resolves; with private networking, to private addresses | `No resolvable bootstrap urls given in bootstrap.servers`, `java.net.UnknownHostException` |
| 2 | DNS of **every** broker | `kafka-broker-api-versions --bootstrap-server <bootstrap>:9092 --command-config client.properties` lists the broker hostnames (or `kcat -L`), then `nslookup` each one | every broker hostname resolves like the bootstrap | the bootstrap works, then `Connection to node <id> (<broker host>/…:9092) could not be established. Node may not be available.` (`Broker may not be available` in older clients) for some or all brokers. An AdminClient: `Timed out waiting for a node assignment`. Only *some* brokers failing usually means a private DNS zone with missing records |
| 3 | TCP to every host | `nc -vz <host> 9092` for the bootstrap and each broker, `nc -vz <host> 443` for Schema Registry and REST | the connection opens (`succeeded`, `open` or `Connected`, depending on the `nc` version) | the same `could not be established` warnings, repeated. In a capture: a SYN with no answer (a firewall or security group drops it) or a reset |
| 4 | TLS and SNI | `openssl s_client -connect <host>:9092 -servername <host> -showcerts < /dev/null` | `Verify return code: 0 (ok)`, with a certificate for the cluster's domain | `SslAuthenticationException: SSL handshake failed`. With `PKIX path building failed`: the client's truststore doesn't hold the CA. Either `ssl.truststore.location` points to a truststore without the public CAs, or a TLS-inspecting proxy replaced the certificate (the issuer in `openssl s_client` is the company CA, not a public one) |
| 5 | Authentication | the client config: `security.protocol=SASL_SSL`, `sasl.mechanism=PLAIN`, API key and secret | the client gets past `ApiVersions` | `SaslAuthenticationException: Authentication failed`: wrong secret, a deleted key, or a key of another cluster |

`ssl.endpoint.identification.algorithm` must stay `https` (the default): disabling it hides a hostname problem
instead of fixing it.

### What the playground adds to the checklist

| Situation | Command |
| --- | --- |
| The customer sent a capture of a failing start (`tcpdump -i any -w ccloud.pcap port 9092 or port 443 or port 53`) | `playground analyze tcp-dump -f ccloud.pcap --output-dir /tmp/ccloud-pcap`: SYN with no answer, refused and reset connections, the SNI of each TLS handshake, TLS alerts with their likely cause, DNS errors. The Kafka requests are encrypted, so they don't show up: this is a TCP, TLS and DNS view |
| Is it the truststore, the chain or the hostname? | `playground tools cert inspect --server <bootstrap host>:9092 --truststore <their truststore> --truststore-password <password>` from a machine that reaches the endpoint (public networking). With private networking, ask for the `openssl s_client -showcerts` output, save the certificates as a PEM file and use `--file <pem> --truststore …` |
| Reproduce with a real cluster: a slow or lossy link | any `ccloud/` example, then `playground debug degrade-traffic -c connect --latency 80ms --action start` (no `--destination`: the addresses of Confluent Cloud endpoints change) |
| A client behind an SNI proxy, no direct route | [ccloud/haproxy](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/haproxy): `iptables` blocks the direct route, HAProxy forwards 9092 and 443 based on the SNI |

`playground analyze tcp-dump` on the capture shipped with the playground shows what these findings look like:

```bash
playground analyze tcp-dump --sample kafka_and_network_errors --output-dir /tmp/tcp-dump-sample
# 🟠 HIGH: 1 connection attempt(s) to sample-firewalled:8080 got no answer (SYN without SYN/ACK): the host is down or unreachable, a firewall drops the packets, or the address is wrong.
# 🟠 HIGH: TLS fatal alert certificate_unknown sent by sample-client to sample-tls-server (1x). Likely: the certificate was rejected (often the CA is not in the truststore, or the hostname does not match).
# 🟡 MEDIUM: DNS NXDOMAIN for schema-registry.does-not-exist.invalid (2x): the name does not resolve from this container.
# 🔐 TLS
#    1 handshake(s) (no SNI) → sample-tls-server
```

### What to ask the customer for

1. The output of the five checks above, run **on the client host** (not from a laptop), for the bootstrap and
   every broker hostname.
2. The client configuration, with the secrets masked, and the client version.
3. The client logs from its start, including the first failed connection (`org.apache.kafka.clients.NetworkClient`
   at `DEBUG` shows each connection attempt and the address it resolved).
4. A capture of a failing start, for `playground analyze tcp-dump`: DNS (port 53) included, otherwise the
   resolution step can't be checked.

---

## 8. Cheat sheet

```bash
playground debug block-traffic   -c <c> [-c <c2>] --destination <ip|container|host> [--port N] --action start|stop
playground debug degrade-traffic -c <c> [-c <c2>] [--destination <d> [--port N]] \
  [--latency 100ms [--jitter 20ms]] [--loss 1%] [--corruption 1%] [--duplicate 1%] [--rate 1mbit] \
  --action start|stop|status
playground debug dns -c <c> [-c <c2>] [--host <hostname>] [--nxdomain | --servfail | --resolve-to <ip> | --delay 3s | --reset]
```

- Egress only: one-way latency adds once to the round trip.
- `block-traffic stop` = same flags as `start`. `degrade-traffic stop` = everything removed.
- `degrade-traffic start` replaces the previous degradation. Combine effects in one call.
- A container restart wipes both.
- `debug dns`: by name, not by IP. A JVM caches the lookups (30s), clients resolve when they connect. `--reset` without
  `--host` removes everything.
- Sources: [`debug/block-traffic.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/debug/block-traffic.sh),
  [`debug/degrade-traffic.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/debug/degrade-traffic.sh),
  [`debug/dns.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/debug/dns.sh)
  and its proxy [`tools/debug-dns/dns_proxy.py`](https://github.com/vdesabou/kafka-docker-playground/blob/master/tools/debug-dns/dns_proxy.py),
  helpers `run_in_network_namespace` / `resolve_traffic_destination_ips` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh).

---

**Links**

- 🎬 Video session: [🐌 A slow or broken network, on purpose](/sessions?id=🐌-a-slow-or-broken-network-on-purpose)
- 📖 [Blocking traffic](/toolkit-network?id=🚫-blocking-traffic) and [Degrade traffic](/toolkit-network?id=🐌-degrade-traffic-add-latency-packet-loss-or-corruption)
  in the Reproduction toolkit
- 🍪 Deep dive: [`playground tcp-proxy` (Zazkia)](/deep-dive-tcp-proxy.md) to act on one TCP connection of a connector
  (delay, break, close, cut one direction) instead of the whole container's network
- 🦈 [playground analyze tcp-dump](/playground%20analyze%20tcp-dump) and [playground tools cert inspect](/playground%20tools%20cert%20inspect), the two commands of the Confluent Cloud checklist
- 🧠 CLI reference: [playground debug degrade-traffic](/playground%20debug%20degrade-traffic),
  [playground debug block-traffic](/playground%20debug%20block-traffic), [playground debug dns](/playground%20debug%20dns), [playground connector wait](/playground%20connector%20wait)
