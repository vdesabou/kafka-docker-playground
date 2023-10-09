# Write connect logs to topic


To run:

```
$ playground run -f start-plaintext<tab>
```

Example using `docker-compose` on how to write logs to files by providing custom `log4j.properties` files.

```yml
  connect:
    volumes:
      - ../../other/write-logs-to-topic/log4j.properties:/tmp/connect/log4j.properties
    environment:
      KAFKA_LOG4J_OPTS: "-Dlog4j.configuration=file:/tmp/connect/log4j.properties"
```

The path of the log4j properties file is done by using environment variable, for zookeeper it is `KAFKA_LOG4J_OPTS`


log4j configuration is using:

```
# Send the logs to a kafka topic
# there will be no key for the kafka records by default
log4j.logger.org.apache.kafka.connect=INFO, kafka_appender
log4j.appender.kafka_appender=org.apache.kafka.log4jappender.KafkaLog4jAppender
log4j.appender.kafka_appender.layout=org.apache.log4j.PatternLayout
log4j.appender.kafka_appender.layout.ConversionPattern=[%d] %p %X{connector.context}%m (%c:%L)%n
log4j.appender.kafka_appender.BrokerList=broker:9092
log4j.appender.kafka_appender.Topic=connect-logs
log4j.logger.processing=INFO, kafka_appender
```

That will send the connect logs to topic `connect-logs`