# Fully Managed ServiceNow Source connector



## Objective

Quickly test [Fully Managed ServiceNow Source](https://docs.confluent.io/cloud/current/connectors/cc-servicenow-source.html) connector.



## Register a test account

Go to [ServiceNow developer portal](https://developer.servicenow.com) and register an account.
Click on `Manage`->`Instance` and register for a Vancouver instance. After some time (about one hour in my case) on the waiting list, you should receive an email with details of your test instance.


## How to run

Simply run:

```
$ just use <playground run>
```


## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)