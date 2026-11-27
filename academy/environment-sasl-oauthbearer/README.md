# Academy: exercises on the sasl-oauthbearer environment

Reproduction models of the [🧑‍🎓 Playground Academy](https://kafka-docker-playground.io/#/academy) that need
SASL/OAUTHBEARER with Keycloak (`playground start-environment --environment sasl-oauthbearer`):

| Model | Mistake | Exercise |
| --- | --- | --- |
| `oauth-repro-000032-sink-cannot-get-token-rotated-secret.sh` | a connector with its own OAuth client (`consumer.override.sasl.jaas.config`) and the secret of before a rotation | [the connector cannot get its token after a secret rotation](https://kafka-docker-playground.io/#/academy?id=oauth-the-connector-cannot-get-its-token-after-a-secret-rotation) |

The lab `other/deep-dive-labs/academy-areas.sh` replays it and its fix every night.
