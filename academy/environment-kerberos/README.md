# Academy: exercises on the kerberos environment

Reproduction models of the [🧑‍🎓 Playground Academy](https://kafka-docker-playground.io/#/academy) that need Kerberos
(SASL/GSSAPI, MIT KDC: `playground start-environment --environment kerberos`):

| Model | Mistake | Exercise |
| --- | --- | --- |
| `kerberos-repro-000033-sink-fails-after-key-rotation-old-keytab.sh` | a connector with its own principal and keytab, whose key is rotated on the KDC without a new keytab | [the connector fails after a restart, Checksum failed](https://kafka-docker-playground.io/#/academy?id=kerberos-the-connector-fails-after-a-restart-checksum-failed) |

The lab `other/deep-dive-labs/academy-areas.sh` replays it and its fix every night.
