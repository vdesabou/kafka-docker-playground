# Fully Managed MQTT Source connector

## Objective

Quickly test the [MQTT Source](https://docs.confluent.io/cloud/current/connectors/cc-mqtt-source.html) fully managed connector, against a local Mosquitto broker exposed through ngrok.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | [ngrok](https://ngrok.com) auth token, used to expose the local container to the fully managed connector. Sign up at https://dashboard.ngrok.com/signup, the token is on https://dashboard.ngrok.com/get-started/your-authtoken |

## Exposing Docker containers over the internet

> [!WARNING]
> Running this example on your personal machine exposes a TCP port to the internet through [ngrok](https://ngrok.com), which is a security risk. Prefer an AWS EC2 instance, and allow only the [Confluent Cloud static egress IP addresses](https://docs.confluent.io/cloud/current/networking/static-egress-ip-addresses.html#use-static-egress-ip-addresses-with-ccloud) (public endpoints on AWS only) in the EC2 security group.

Example to open port 1883 to the Confluent static egress IP addresses:

```bash
group=$(aws ec2 describe-instances --instance-id <ec2-instance-id> --output=json | jq -r '.Reservations[] | .Instances[] | .SecurityGroups[] | .GroupName')
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 1883 --cidr 13.36.88.88/32
aws ec2 authorize-security-group-ingress --group-name $group --protocol tcp --port 1883 --cidr 13.36.88.89/32
# etc. for every static egress IP address of your region
```

The ngrok web interface is available at http://localhost:4040.

## How to run

```bash
playground run -f fully-managed-mqtt-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-mqtt-source.sh` | `tcp://` connection with username/password |
| `fully-managed-mqtt-source-mtls.sh` | `ssl://` connection with mutual TLS (keystore and truststore generated with `playground tools certs-create`) |

## What the script does

1. Bootstraps the Confluent Cloud environment and deletes topic `mqtt-source-1`.
2. Starts Mosquitto and ngrok locally (the mTLS variant first generates certificates in `security/`).
3. Creates the fully managed `MqttSource` connector reading MQTT topic `my-mqtt-topic` into Kafka topic `mqtt-source-1` (Avro).
4. Publishes a message to `my-mqtt-topic` with `mosquitto_pub`.
5. Verifies the record with `playground topic consume --topic mqtt-source-1`.
6. Asks whether to delete the connector.

## Known issues

The mTLS variant fails validation because the generated certificate does not contain the ngrok hostname:

```text
mqtt.server.uri: MqttException (0) - javax.net.ssl.SSLHandshakeException: No subject alternative DNS name matching 4.tcp.eu.ngrok.io found.
```

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) is the load of the self-managed example [`connect-mqtt-source`](../../connect/connect-mqtt-source/README.md#benchmark): it loads messages on the MQTT topic (steady mode only: the broker does not keep a backlog) for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Run the example, answer `n` when it asks to delete the connector, then:

```bash
# throughput during 2 minutes while batches of 1000 messages are published continuously
playground connector benchmark --mode steady --duration 2m --nb-records 1000
```

The connector runs in Confluent Cloud, so there is no JMX: the benchmark counts the records from the end offsets of the topics of the connector (`--topic` to choose them) and a drain starts measuring at the first records seen after the resume (Confluent Cloud takes a few seconds to restart the tasks), and the throughput includes the network between this machine and Confluent Cloud (ngrok tunnel). Compare runs made from the same machine.
