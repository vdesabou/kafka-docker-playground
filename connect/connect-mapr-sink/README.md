# Mapr Sink connector



## Objective

Quickly test [Mapr Sink](https://docs.confluent.io/current/connect/kafka-connect-maprdb/index.html#mapr-db-sink-connector-for-cp) connector.

## Prerequisites

You need to follow these steps to get `HPE_MAPR_EMAIL` and `HPE_MAPR_TOKEN`

1/ You need to have an [HPE Account](https://docs.ezmeral.hpe.com/datafabric-customer-managed/74/AdvancedInstallation/Obtaining_an_HPE_Account.html)
❗Make sure to set an Organization and use a work email address, otherwise you won't have access to https://package.ezmeral.hpe.com/releases/

2/ [Obtain a token](https://docs.ezmeral.hpe.com/datafabric-customer-managed/74/AdvancedInstallation/Obtaining_a_Token.html) for your HPE account

## How to run

**WARNING**: It only works with UBI 8 image, make sure to set environment variable `TAG`:

```bash
export TAG=6.0.0-1-ubi8
```

Simply run:

```
$ playground run -f mapr-sink<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path> <HPE_MAPR_EMAIL> <HPE_MAPR_TOKEN>
```

Note: you can also export these values as environment variable


Mapper UI MCS is running at [https://127.0.0.1:8443](https://127.0.0.1:8443) (`mapr/map`)

