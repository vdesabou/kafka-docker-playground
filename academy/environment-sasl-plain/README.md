# Academy: exercises on the sasl-plain environment

Reproduction models of the [🧑‍🎓 Playground Academy](https://kafka-docker-playground.io/#/academy) that need SASL/PLAIN
on every listener (`playground start-environment --environment sasl-plain`):

| Model | Mistake | Exercise |
| --- | --- | --- |
| `sasl-plain-repro-000028-sink-fails-authentication-old-password.sh` | a connector with its own credentials (`consumer.override.sasl.jaas.config`) and the password of before a rotation | [the sink connector is refused after a password rotation](https://kafka-docker-playground.io/#/academy?id=sasl-the-sink-connector-is-refused-after-a-password-rotation) |
| `python-repro-000030-python-producer-cannot-connect.sh` | a Python (librdkafka) client without its SASL properties (`client-python-000030/client.properties`, mounted as a folder: edit it, run the client again) | [the producer cannot connect, and says almost nothing](https://kafka-docker-playground.io/#/academy?id=python-client-the-producer-cannot-connect-and-says-almost-nothing) |

The lab `other/deep-dive-labs/academy-areas.sh` replays them and their fixes every night.
