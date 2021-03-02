package com.github.vdesabou;

import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.KafkaAdminClient;
import java.util.Properties;
import java.util.concurrent.ExecutionException;
import org.apache.kafka.common.KafkaFuture;
import org.apache.kafka.clients.producer.ProducerConfig;

public class MyAdminClient {

    public static void main(String[] args) throws InterruptedException {

        Properties props = new Properties();

        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "broker1:9092,broker2:9092,broker3:9092");
        AdminClient adminClient = KafkaAdminClient.create(props);

        try {
            KafkaFuture<String> clusterIdFuture = adminClient.describeCluster().clusterId();
            if (clusterIdFuture == null) {
                System.out.printf("Kafka cluster version is too old to return cluster ID");
                return;
            }
            String kafkaClusterId = clusterIdFuture.get();
            System.out.printf("Kafka cluster ID:" + kafkaClusterId);
            return;
        } catch (InterruptedException e) {
            System.out.printf("Unexpectedly interrupted when looking up Kafka cluster info" + e);
        } catch (ExecutionException e) {
            System.out.printf("Failed to connect to and describe Kafka cluster" + e);
        }
    }
}

