# 🌐 Network

Break the network on purpose: block traffic, add latency or packet loss, cut TCP connections, or put an HTTPS proxy in the way. Part of the [🧰 Reproduction toolkit](/reusables.md).

> [!TIP]
> The [🍪 deep dive on network traffic](/deep-dive-network-traffic.md) explains how to capture and read what goes over the wire.

## 🚫 Blocking traffic

To reproduce what happens when a component cannot reach another one (a broker, Schema Registry, a database or an external API going down, a firewall dropping packets), a reproduction model can block the traffic between containers or to an external host, then unblock it to check how the connector or client recovers.

Just use [CLI](/playground%20debug%20block-traffic) `playground debug block-traffic`. It uses `iptables` (installed in the container if needed) to drop the traffic from one or more containers to a destination (container name, host name or IP address), optionally on a single `--port`. Run it again with `--action stop` to restore the traffic.

```bash
playground debug block-traffic --destination google.com --action start
playground debug block-traffic --container schema-registry --destination broker --port 9092 --action start
playground debug block-traffic -c connect -c ksqldb-server --destination schema-registry --action stop
```

<a id="🐌-add-latency-packet-loss-or-corruption"></a>

## 🐌 Degrade traffic - Add latency, packet loss or corruption

Some issues only happen on a slow or unreliable network: request timeouts, retries, rebalances, producer or consumer errors. A reproduction model, or you on a running environment, can simulate them by making the traffic of a container slow or lossy, then putting it back to normal to check how the connector or client recovers.

Just use [CLI](/playground%20debug%20degrade-traffic) `playground debug degrade-traffic`. It applies [`tc netem`](https://man7.org/linux/man-pages/man8/tc-netem.8.html) to the traffic from one or more containers, to a destination (container name, host name or IP address, optionally a single `--port`), or to all their traffic when there is no `--destination`. Several effects can be combined in one call:

| Flag | Effect | Example |
| --- | --- | --- |
| `--latency` | added latency | `100ms`, `1s` |
| `--jitter` | random variation of the latency (needs `--latency`) | `20ms` |
| `--loss` | packets dropped | `1%` |
| `--corruption` | packets corrupted | `1%` |
| `--duplicate` | packets duplicated | `1%` |
| `--rate` | bandwidth limit | `1mbit`, `500kbit` |

```bash
# 100ms (± 20ms) from connect to the broker
playground debug degrade-traffic --container connect --destination broker --latency 100ms --jitter 20ms --action start

# latency and packet loss, on two containers, only for the traffic to port 9092 of the broker
playground debug degrade-traffic -c connect -c ksqldb-server --destination broker --port 9092 --latency 50ms --loss 1% --action start

# a bandwidth limit on all the traffic of connect
playground debug degrade-traffic -c connect --rate 1mbit --action start

# what is applied, and the round trip measured from connect
playground debug degrade-traffic -c connect --destination broker --action status

# back to normal
playground debug degrade-traffic -c connect --action stop
```

After `start`, `stop` and `status`, the command measures the effect from the container: the average of 4 pings, or the time of a TCP connection when `--port` is set (only that TCP traffic is degraded, not ping):

```text
🐌 Applying 100ms ± 10ms latency on container connect to broker (172.27.0.2)
⏱️ round trip from connect to broker: 101.563 ms (average of 4 pings)
```

`tc` runs from the [`nicolaka/netshoot`](https://github.com/nicolaka/netshoot) image (pulled the first time) in the network namespace of the container, or in an ephemeral container of the pod with the `cfk` environment. Nothing is installed in the container, so this works with any image: connect, broker, Schema Registry, databases…

> [!NOTE]
> * `tc` only slows down the packets a container **sends**: with `--latency 100ms` from connect to the broker, the round trip between them grows by 100ms. To degrade the other direction as well, run the command on the destination too.
> * A new `--action start` replaces what was applied before on the container: to combine effects, pass them all in one call.
> * A restart of the container (e.g. `playground container restart`) removes the degradation.

> [!TIP]
> A complete example is available [here](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/monitoring-sink-latency/start.sh).

## 🏚 Simulate TCP connections problems

[emicklei/zazkia](https://github.com/emicklei/zazkia) is a nice tool to simulate a TCP connection issues (reset,delay,throttle,corrupt).

Just use [CLI](/playground%20tcp-proxy) `playground tcp-proxy`.

Main commands (see [CLI](/playground%20tcp-proxy) for the full list):

| Command | Description |
|---|---|
| [`start`](/playground%20tcp-proxy%20start) | 💗 Start the TCP proxy and automatically replace connector config with zazkia hostname and port 49998 |
| [`open-ui`](/playground%20tcp-proxy%20open-ui) | 🌐 Open the Zazkia UI |
| [`get-connections`](/playground%20tcp-proxy%20get-connections) | 🧲 Get Zazkia active TCP connections config and stats |
| [`delay`](/playground%20tcp-proxy%20delay) | ⏲️ Add milliseconds delay to service response |
| [`break`](/playground%20tcp-proxy%20break) | 💔 Break sending the response to the client |
| [`close-connection`](/playground%20tcp-proxy%20close-connection) | ❌ Close the Zazkia active TCP connections |
| [`close-all-connection-with-error`](/playground%20tcp-proxy%20close-all-connection-with-error) | 🧹 Close all Zazkia TCP connections which are in error state |
| [`toggle-accept-connections`](/playground%20tcp-proxy%20toggle-accept-connections) | 🙅‍♂️ Change whether new connections can be accepted |
| [`toggle-reads-client`](/playground%20tcp-proxy%20toggle-reads-client) / [`toggle-reads-service`](/playground%20tcp-proxy%20toggle-reads-service) | ✅ Change whether reading data from the client / service is enabled |
| [`toggle-writes-client`](/playground%20tcp-proxy%20toggle-writes-client) / [`toggle-writes-service`](/playground%20tcp-proxy%20toggle-writes-service) | ✅ Change whether writing data to the client / service is enabled |

## 🌐 Using HTTPS proxy

There are several connector examples which include HTTPS proxy (check for `also with 🌐 proxy` in the **[Content](/content.md)** section).

> [!TIP]
> A complete example is available [here](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-aws-s3-sink/s3-sink-proxy.sh). 

Here are the steps to follow:

1. Copy [`connect/connect-aws-s3-sink/nginx-proxy`](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-s3-sink/nginx-proxy) directory into your test directory.

2. Update [`connect/connect-aws-s3-sink/nginx-proxy/nginx_whitelist.conf`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-aws-s3-sink/nginx-proxy/nginx_whitelist.conf) with the domain name required for your needs.

*Example:*

```conf
        server_name  service-now.com;
        server_name  *.service-now.com;
```

> [!TIP]
> If you need a proxy to reach another docker container, as opposed to a domain, use following example, where `schema-registry` is the name of the container:

```nginx
http {
    access_log /var/log/nginx_access.log;
    error_log /var/log/nginx_errors.log;

    upstream docker-schema-registry {
        server schema-registry:8081;
    }

    server {
        listen       8888;
        location / {
            proxy_pass         http://docker-schema-registry;
            proxy_redirect     off;
            proxy_set_header   Host $host;
            proxy_set_header   X-Real-IP $remote_addr;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Host $server_name;
        }
    }
}
```

3. Add this in your `docker-compose` file:

```yml
  nginx-proxy:
    image: reiz/nginx_proxy:latest
    hostname: nginx-proxy
    container_name: nginx-proxy
    ports:
      - "8888:8888"
    volumes:
      - ../../connect/connect-aws-s3-sink/nginx-proxy/nginx_whitelist.conf:/usr/local/nginx/conf/nginx.conf
```

> [!WARNING]
> Make sure to update `../../connect/connect-aws-s3-sink` above with the right path.

4. [Optional] In order to make sure the proxy is used, you can set `dns: 0.0.0.0` in the connect instance, so that there is no internet connectivity.

```yml
  connect:
    <snip>
    environment:
      <snip>
    dns: 0.0.0.0
```

5. In your connector configuration, update the proxy configuration parameter with `http://nginx-proxy:8888`.

*Example:*

```json
"s3.proxy.url": "http://nginx-proxy:8888"
```

> [!NOTE]
> If your proxy requires HTTP2 support, there is a full example available in this example: [GCP Pub/Sub Source connector](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-gcp-pubsub-source/gcp-pubsub-source-nginx-proxy.sh)

### 🔐 Proxy with BASIC authentication

If you want to setup BASIC authentication, you can use [ubuntu/squid](https://hub.docker.com/r/ubuntu/squid) image.

> [!TIP]
> Some complete examples are available [here](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-aws-s3-sink/s3-sink-proxy-basic-auth.sh) and [there](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-salesforce-platform-events-sink/salesforce-platform-events-sink-proxy-basic-auth.sh)

* in your `docker-compose`, add `squid` as below:


```yml
  squid:
    image: ubuntu/squid
    hostname: squid
    container_name: squid
    ports:
      - "8888:8888"
    volumes:
      - ../../connect/connect-aws-s3-sink/squid/passwords:/etc/squid/passwords
      - ../../connect/connect-aws-s3-sink/squid/squid.conf:/etc/squid/squid.conf
```

Proxy details:

* container: squid
* port: 8888
* user: admin
* password: 1234

Example with S3 sink:

```json
  "s3.proxy.url": "http://squid:8888",
  "s3.proxy.user": "admin",
  "s3.proxy.password": "1234",
```

Example with Salesforce:

```json
  "http.proxy": "squid:8888",
  "http.proxy.auth.scheme": "BASIC",
  "http.proxy.user": "admin",
  "http.proxy.password": "1234",
```
