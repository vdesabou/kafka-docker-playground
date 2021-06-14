# Create Topic Policy

## Objective

Quickly test [KIP-108](https://cwiki.apache.org/confluence/display/KAFKA/KIP-108%3A+Create+Topic+Policy) Create Topic Policy.

Configuration setup:

```yml
  broker:
      environment:
        KAFKA_CREATE_TOPIC_POLICY_CLASS_NAME : "com.github.vdesabou.MyTopicPolicy"
        CLASSPATH: /tmp/mytopicpolicy-1.0.0-jar-with-dependencies.jar
      volumes:
        - ../../other/create-topic-policy/create-topic-policy/target/mytopicpolicy-1.0.0-jar-with-dependencies.jar:/tmp/mytopicpolicy-1.0.0-jar-with-dependencies.jar
```

With `mytopicpolicy-1.0.0-jar-with-dependencies.jar` built with Java code:

```java
package com.github.vdesabou;

import org.apache.kafka.common.errors.PolicyViolationException;
import org.apache.kafka.server.policy.CreateTopicPolicy;

import java.util.Map;

public class MyTopicPolicy implements CreateTopicPolicy {
    @Override
    public void validate(RequestMetadata requestMetadata) throws PolicyViolationException {
        if (requestMetadata.topic() != null && ! requestMetadata.topic().startsWith("_") && ! requestMetadata.topic().startsWith("connect-")) {
            if (! requestMetadata.topic().startsWith("kafka-docker-playground")) {
                throw new PolicyViolationException("Topic name should start with kafka-docker-playground, received:" + requestMetadata.topic());
            }
        }
    }

    @Override
    public void close() throws Exception {

    }

    @Override
    public void configure(Map<String, ?> configs) {

    }
}
```

Results:

Trying to create a topic with name that does not start with kafka-docker-playground, it should FAIL

```bash
$ docker exec connect kafka-topics --create --topic mytopic --bootstrap-server broker:9092
```

```
Error while executing topic command : Topic name should start with kafka-docker-playground, received:mytopic
[2021-06-14 12:25:26,534] ERROR org.apache.kafka.common.errors.PolicyViolationException: Topic name should start with kafka-docker-playground, received:mytopic
 (kafka.admin.TopicCommand$)
```

Trying to create a topic with name that starts with kafka-docker-playground, it should WORK

```bash
$ docker exec connect kafka-topics --create --topic kafka-docker-playground2 --bootstrap-server broker:9092
```