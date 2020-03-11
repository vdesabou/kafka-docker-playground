package io.confluent.developer.helper;

import com.jasongoodwin.monads.Try;
import com.typesafe.config.Config;
import com.typesafe.config.ConfigFactory;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.CreateTopicsResult;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.errors.TopicExistsException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.HashMap;
import java.util.Optional;
import java.util.Properties;
import java.util.concurrent.ExecutionException;

public class TopicCreation {

    private static final Logger logger = LoggerFactory.getLogger(TopicCreation.class);

    public static void main(String[] args) {

        Config config = ConfigFactory.load();

        Properties properties = new Properties();

        properties.put("bootstrap.servers", config.getString("bootstrap.servers"));

        AdminClient client = AdminClient.create(properties);

        HashMap<String, NewTopic> topics = new HashMap<>();

        topics.put(
                config.getString("input.topic.name"),
                new NewTopic(
                        config.getString("input.topic.name"),
                        config.getNumber("input.topic.partitions").intValue(),
                        config.getNumber("input.topic.replication.factor").shortValue())
        );

        topics.put(
                config.getString("output.topic.name"),
                new NewTopic(
                        config.getString("output.topic.name"),
                        config.getNumber("output.topic.partitions").intValue(),
                        config.getNumber("output.topic.replication.factor").shortValue())
        );

        try {
            logger.info("Starting the topics creation");

            CreateTopicsResult result = client.createTopics(topics.values());

            result.values().forEach((topicName, future) -> {
                NewTopic topic = topics.get(topicName);
                future.whenComplete((aVoid, maybeError) ->
                        Optional
                                .ofNullable(maybeError)
                                .map(Try::<Void>failure)
                                .orElse(Try.successful(null))

                                .onFailure(throwable -> logger.error("Topic creation didn't complete:", throwable))
                                .onSuccess((anOtherVoid) -> logger.info(
                                        String.format(
                                                "Topic %s, has been successfully created " +
                                                        "with %s partitions and replicated %s times",
                                                topic.name(),
                                                topic.numPartitions(),
                                                topic.replicationFactor() - 1
                                        )
                                )));
            });

            result.all().get();
        } catch (InterruptedException | ExecutionException e) {
            if (!(e.getCause() instanceof TopicExistsException)) e.printStackTrace();
        } finally {
            client.close();
        }
    }
}