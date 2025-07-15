# Datadog Logs Sink connector


## Objective

Quickly test [Datadog Logs Sink](https://www.confluent.io/hub/datadog/kafka-connect-logs) connector.

## Prerequisites

Register for a [Datadog trial](https://app.datadoghq.com) if you don't already have an account (you can convert it to *Free plan* after the trial expires).

Create an API key (`DD_API_KEY`) and an Application key (`DD_APP_KEY`):

![Datadog API Key](api_key_dd.png)
![Datadog APP Key](app_key_dd.png)

## How to run

Export DataDog Environment variables

Example :
```
$ export DD_API_KEY="4a**********0"
$ export DD_APP_KEY="c43**************67"
$ export DD_SITE="us5.datadoghq.com"
```

Simply run:

```
$ just use <playground run> command and search for datadog-logs-sink-sink<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> in this folder

```
