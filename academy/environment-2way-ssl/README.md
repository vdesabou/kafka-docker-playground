# Academy: exercises on the 2way-ssl environment

Reproduction models of the [🧑‍🎓 Playground Academy](https://kafka-docker-playground.io/#/academy) that need mutual TLS
on every listener (`playground start-environment --environment 2way-ssl`):

| Model | Mistake | Exercise |
| --- | --- | --- |
| `2way-ssl-repro-000029-sink-fails-tls-broker-by-ip-address.sh` | a connector that reaches the broker by its IP address, which is not in the subject alternative names of its certificate | [the connector fails when it uses the IP address of the broker](https://kafka-docker-playground.io/#/academy?id=tls-the-connector-fails-when-it-uses-the-ip-address-of-the-broker) |
| `2way-ssl-repro-000037-connect-worker-down-clock-behind-certificate-not-yet-valid.sh` | the clock of the Connect worker two days behind (`playground debug clock --at`): the certificate of the broker is not valid yet for it | [the Connect worker does not come back after a hardware swap](https://kafka-docker-playground.io/#/academy?id=tls-the-connect-worker-does-not-come-back-after-a-hardware-swap) |

The lab `other/deep-dive-labs/academy-areas.sh` replays them and their fixes every night.
