# Salesforce PushTopics Source connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-salesforce-pushtopics-source/asciinema.gif?raw=true)

## Objective

Quickly test [Salesforce PushTopics Source](https://docs.confluent.io/current/connect/kafka-connect-salesforce/pushtopics/salesforce_pushtopic_source_connector_quickstart.html#example-configure-salesforce-pushtopic-source-connector) connector.



## Register a test account

Go to [Salesforce developer portal](https://developer.salesforce.com/signup/) and register an account.

## Follow instructions to create a Connected App

[Link](https://docs.confluent.io/current/connect/kafka-connect-salesforce/pushtopics/salesforce_pushtopic_source_connector_quickstart.html#salesforce-account)

## Add a Lead to Salesforce

[Link](https://docs.confluent.io/current/connect/kafka-connect-salesforce/pushtopics/salesforce_pushtopic_source_connector_quickstart.html#add-a-lead-to-salesforce)

## How to run

Simply run:

```
$ ./salesforce-pushtopic-source.sh <SALESFORCE_USERNAME> <SALESFORCE_PASSWORD> <CONSUMER_KEY> <CONSUMER_PASSWORD> <SECURITY_TOKEN>
```

Note: you can also export these values as environment variable

## Details of what the script is doing



N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
