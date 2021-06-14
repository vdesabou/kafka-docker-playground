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