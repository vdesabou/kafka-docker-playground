package com.github.vdesabou;

import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.CreateTopicsResult;
import org.apache.kafka.clients.admin.KafkaAdminClient;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.Producer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.apache.kafka.common.config.TopicConfig;
import org.apache.kafka.common.errors.TopicExistsException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;
import com.github.vdesabou.Customer;

import uk.co.jemos.podam.api.PodamFactoryImpl;
import uk.co.jemos.podam.api.PodamFactory;
import org.jeasy.random.EasyRandom;
import org.jeasy.random.EasyRandomParameters;
import com.github.javafaker.Faker;

public class SimpleProducer {

    private static final String KAFKA_ENV_PREFIX = "KAFKA_";
    private final Logger logger = LoggerFactory.getLogger(SimpleProducer.class);
    private final Properties properties;
    private final String topicName;
    private final Long messageBackOff;
    private Long nbMessages;

    public static void main(String[] args) throws InterruptedException, ExecutionException {
        SimpleProducer simpleProducer = new SimpleProducer();
        simpleProducer.start();
    }

    public SimpleProducer() throws ExecutionException, InterruptedException {
        properties = buildProperties(defaultProps, System.getenv(), KAFKA_ENV_PREFIX);
        topicName = System.getenv().getOrDefault("TOPIC", "sample");
        messageBackOff = Long.valueOf(System.getenv().getOrDefault("MESSAGE_BACKOFF", "100"));

        final Integer numberOfPartitions = Integer.valueOf(System.getenv().getOrDefault("NUMBER_OF_PARTITIONS", "2"));
        final Short replicationFactor = Short.valueOf(System.getenv().getOrDefault("REPLICATION_FACTOR", "3"));
        nbMessages = Long.valueOf(System.getenv().getOrDefault("NB_MESSAGES", "10"));
        if(nbMessages == -1) {
            nbMessages = Long.MAX_VALUE;
        }

        AdminClient adminClient = KafkaAdminClient.create(properties);
        createTopic(adminClient, topicName, numberOfPartitions, replicationFactor);
    }

    private void start() throws InterruptedException {
        logger.info("creating producer with props: {}", properties);

        logger.info("Sending data to `{}` topic", topicName);

        // PodamFactory factory = new PodamFactoryImpl();
        EasyRandomParameters parameters = new EasyRandomParameters()
                // .seed(123L)
                .objectPoolSize(10)
                .randomizationDepth(10)
                .stringLengthRange(1, 15)
                .collectionSizeRange(1, 1)
                .scanClasspathForConcreteTypes(true)
                .overrideDefaultInitialization(false)
                .ignoreRandomizationErrors(false);
        EasyRandom generator = new EasyRandom(parameters);

        try (Producer<Long, Customer> producer = new KafkaProducer<>(properties)) {
            long id = 0;
            while (id < nbMessages) {

                // This will use constructor with minimum arguments and
                // then setters to populate POJO
                // Customer customer = factory.manufacturePojo(Customer.class);

                // Customer customer = Customer.newBuilder()
                //         .setCount(id)
                //         .setFirstName(faker.name().firstName())
                //         .setLastName(faker.name().lastName())
                //         .setAddress(faker.address().streetAddress())
                //         .build();

                Customer customer = generator.nextObject(Customer.class);

                ProducerRecord<Long, Customer> record = new ProducerRecord<>(topicName, id, customer);
                logger.info("Sending Key = {}, Value = {}", record.key(), record.value());
                producer.send(record, (recordMetadata, exception) -> sendCallback(record, recordMetadata, exception));
                id++;
                TimeUnit.MILLISECONDS.sleep(messageBackOff);
            }
        }
    }

    private void sendCallback(ProducerRecord<Long, Customer> record, RecordMetadata recordMetadata, Exception e) {
        if (e == null) {
            logger.debug("succeeded sending. offset: {}", recordMetadata.offset());
        } else {
            logger.error("failed sending key: {}" + record.key(), e);
        }
    }

    private Map<String, String> defaultProps = Map.of(
            ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "broker:9092",
            ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.LongSerializer",
            ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, "io.confluent.kafka.serializers.KafkaAvroSerializer");

    private Properties buildProperties(Map<String, String> baseProps, Map<String, String> envProps, String prefix) {
        Map<String, String> systemProperties = envProps.entrySet()
                .stream()
                .filter(e -> e.getKey().startsWith(prefix))
                .filter(e -> !e.getValue().isEmpty())
                .collect(Collectors.toMap(
                        e -> e.getKey()
                                .replace(prefix, "")
                                .toLowerCase()
                                .replace("_", "."),
                        e -> e.getValue()));

        Properties props = new Properties();
        props.putAll(baseProps);
        props.putAll(systemProperties);
        return props;
    }

    private void createTopic(AdminClient adminClient, String topicName, Integer numberOfPartitions,
            Short replicationFactor) throws InterruptedException, ExecutionException {
        if (!adminClient.listTopics().names().get().contains(topicName)) {
            logger.info("Creating topic {}", topicName);

            final Map<String, String> configs = replicationFactor < 3
                    ? Map.of(TopicConfig.MIN_IN_SYNC_REPLICAS_CONFIG, "1")
                    : Map.of();

            final NewTopic newTopic = new NewTopic(topicName, numberOfPartitions, replicationFactor);
            newTopic.configs(configs);
            try {
                CreateTopicsResult topicsCreationResult = adminClient.createTopics(Collections.singleton(newTopic));
                topicsCreationResult.all().get();
            } catch (ExecutionException e) {
                // silent ignore if topic already exists
            }
        }
    }
}
