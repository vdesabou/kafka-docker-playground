import io.confluent.kafka.schemaregistry.ParsedSchema;
import io.confluent.kafka.schemaregistry.avro.AvroSchema;
import io.confluent.kafka.schemaregistry.client.SchemaMetadata;
import io.confluent.kafka.schemaregistry.client.SchemaRegistryClient;
import io.confluent.kafka.schemaregistry.client.rest.entities.SchemaReference;
import io.confluent.kafka.schemaregistry.client.rest.exceptions.RestClientException;
import io.confluent.kafka.serializers.KafkaAvroDeserializer;
import io.confluent.kafka.serializers.KafkaAvroSerializer;
import io.confluent.kafka.serializers.KafkaAvroSerializerConfig;
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericData;
import org.apache.avro.generic.GenericRecord;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.errors.SerializationException;
import org.apache.kafka.common.serialization.ByteArrayDeserializer;
import org.apache.kafka.common.serialization.IntegerDeserializer;
import org.apache.kafka.common.serialization.IntegerSerializer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.KafkaContainer;
import org.testcontainers.containers.Network;
import org.testcontainers.utility.DockerImageName;

import java.io.IOException;
import java.time.Duration;
import java.util.*;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;
import static org.junit.Assert.fail;

public class CustomSchemaRegistryClientUsingLocalSchemasTest {

    Logger logger = LoggerFactory.getLogger(CustomSchemaRegistryClientUsingLocalSchemasTest.class);

    public static final String TOPIC = "ORDERS";
    public static final String ORDER_SCHEMA = "{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"product\",\"type\":\"string\"},{\"name\":\"quantity\",\"type\":\"int\"},{\"name\":\"price\",\"type\":\"float\"}]}";

    Network network = Network.newNetwork();
    KafkaContainer kafka = new KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.3.0"))
            .withNetworkAliases("kafka")
            .withNetwork(network);

    GenericContainer<?> schemaRegistry = new GenericContainer<>(DockerImageName.parse("confluentinc/cp-schema-registry:7.3.0"))
            .withNetwork(network)
            .withExposedPorts(8081)
            .withNetworkAliases("schema-registry")
            .withEnv("SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS", "PLAINTEXT://kafka:9092")
            .withEnv("SCHEMA_REGISTRY_HOST_NAME", "schema-registry")
            .withEnv("SCHEMA_REGISTRY_LISTENERS", "http://0.0.0.0:8081");

    ConsumerRecord<Integer, byte[]> loadedRecord;

    @BeforeEach
    public void beforeEach() {
        kafka.start();
        schemaRegistry.start();

        // Produce record which will record the schema into the Schema Registry
        Map<String, Object> producerConfig = Map.of(
                ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, kafka.getBootstrapServers(),
                ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, IntegerSerializer.class.getName(),
                ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, KafkaAvroSerializer.class.getName(),
                KafkaAvroSerializerConfig.SCHEMA_REGISTRY_URL_CONFIG, "http://localhost:" + schemaRegistry.getMappedPort(8081)
        );

        try (KafkaProducer<Integer, GenericRecord> producer = new KafkaProducer<>(producerConfig)) {
            Schema schema = new Schema.Parser().parse(ORDER_SCHEMA);
            GenericRecord record = new GenericData.Record(schema);
            record.put("id", 1);
            record.put("product", "foo");
            record.put("quantity", 100);
            record.put("price", 50.0);

            producer.send(new ProducerRecord<>(TOPIC, (Integer) record.get("id"), record), (metadata, exception) -> {
                if (exception != null) {
                    exception.printStackTrace();
                } else {
                    logger.info("Sent message to topic: {}, partition: {}, offset: {}", metadata.topic(), metadata.partition(), metadata.offset());
                }
            });
        }

        // Consume the unique record
        Map<String, Object> consumerConfig = Map.of(
                ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, kafka.getBootstrapServers(),
                ConsumerConfig.GROUP_ID_CONFIG, CustomSchemaRegistryClientUsingLocalSchemasTest.class.getName() + System.currentTimeMillis(),
                ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, IntegerDeserializer.class.getName(),
                ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, ByteArrayDeserializer.class.getName(),
                ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest"
        );

        List<ConsumerRecord<Integer, byte[]>> loadedRecords = new ArrayList<>();

        try (KafkaConsumer<Integer, byte[]> consumer = new KafkaConsumer<>(consumerConfig)) {
            consumer.subscribe(Collections.singleton(TOPIC));
            await().atMost(org.awaitility.Duration.TEN_SECONDS).untilAsserted(() -> {
                ConsumerRecords<Integer, byte[]> records = consumer.poll(Duration.ofMillis(100));
                records.forEach(record -> {
                    loadedRecords.add(record);
                });
                assertThat(loadedRecords.size()).isEqualTo(1);
            });
            loadedRecord = loadedRecords.get(0);
        }
    }

    @AfterEach
    public void afterEach() {
        kafka.stop();
        schemaRegistry.stop();
    }

    @Test
    public void testRecoverAccidentalDelete() {
        MySchemaRegistryClient mySchemaRegistryClient = new MySchemaRegistryClient(ORDER_SCHEMA);
        KafkaAvroDeserializer kafkaAvroDeserializer = new KafkaAvroDeserializer(mySchemaRegistryClient);

        // The data is deserialized correctly using the custom schema Registry
        GenericRecord result = (GenericRecord) kafkaAvroDeserializer.deserialize(TOPIC, loadedRecord.value());
        assertThat(result.hasField("id")).isTrue();
        assertThat(result.hasField("quantity")).isTrue();
        assertThat(result.hasField("price")).isTrue();
    }

    @Test
    public void testRecoverAccidentalDeleteWithSchemaHavingLessFieldsThanTheIncomingRecord() {
        String ORDER_SCHEMA_WITHOUT_PRICE = "{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"product\",\"type\":\"string\"},{\"name\":\"quantity\",\"type\":\"int\"}]}";
        MySchemaRegistryClient mySchemaRegistryClient = new MySchemaRegistryClient(ORDER_SCHEMA_WITHOUT_PRICE);
        KafkaAvroDeserializer kafkaAvroDeserializer = new KafkaAvroDeserializer(mySchemaRegistryClient);

        // The data is deserialized without loaded the price field since not present in the schema
        GenericRecord result = (GenericRecord) kafkaAvroDeserializer.deserialize(TOPIC, loadedRecord.value());
        assertThat(result.hasField("id")).isTrue();
        assertThat(result.hasField("quantity")).isTrue();
        assertThat(result.hasField("price")).isFalse();
    }

    @Test
    public void testRecoverAccidentalDeleteWithSchemaHavingMoreFieldsThanTheIncomingRecord() {
        String ORDER_SCHEMA_WITH_ADDITIONAL_COUNTRY_FIELD = "{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"product\",\"type\":\"string\"},{\"name\":\"quantity\",\"type\":\"int\"},{\"name\":\"price\",\"type\":\"float\"},{\"name\":\"country\",\"type\":\"string\"}]}";
        MySchemaRegistryClient mySchemaRegistryClient = new MySchemaRegistryClient(ORDER_SCHEMA_WITH_ADDITIONAL_COUNTRY_FIELD);
        KafkaAvroDeserializer kafkaAvroDeserializer = new KafkaAvroDeserializer(mySchemaRegistryClient);

        //Deserialization will fail since the schema has a field that is not present in the record
        //This behavior is similar to providing the wrong schema to deserialize the record
        try {
            kafkaAvroDeserializer.deserialize(TOPIC, loadedRecord.value());
            fail("Should have thrown an exception");
        } catch (Exception e) {
            assertThat(e.getClass()).isEqualTo(SerializationException.class);
            assertThat(e.getMessage()).isEqualTo("Error deserializing Avro message for id 1");
        }
    }

    public static class MySchemaRegistryClient implements SchemaRegistryClient {

        private final ParsedSchema schema;

        public MySchemaRegistryClient(String schema) {
            this.schema = new AvroSchema(schema);
        }

        @Override
        public ParsedSchema getSchemaBySubjectAndId(String s, int i) throws IOException, RestClientException {
            return schema;
        }

        // Others methods are not Used for deserialization
        @Override
        public Optional<ParsedSchema> parseSchema(String s, String s1, List<SchemaReference> list) {
            return Optional.empty();
        }

        @Override
        public int register(String s, ParsedSchema parsedSchema) throws IOException, RestClientException {
            return 0;
        }

        @Override
        public int register(String s, ParsedSchema parsedSchema, int i, int i1) throws IOException, RestClientException {
            return 0;
        }

        @Override
        public ParsedSchema getSchemaById(int i) throws IOException, RestClientException {
            return null;
        }

        @Override
        public Collection<String> getAllSubjectsById(int i) throws IOException, RestClientException {
            return null;
        }

        @Override
        public SchemaMetadata getLatestSchemaMetadata(String s) throws IOException, RestClientException {
            return null;
        }

        @Override
        public SchemaMetadata getSchemaMetadata(String s, int i) throws IOException, RestClientException {
            return null;
        }

        @Override
        public int getVersion(String s, ParsedSchema parsedSchema) throws IOException, RestClientException {
            return 0;
        }

        @Override
        public List<Integer> getAllVersions(String s) throws IOException, RestClientException {
            return null;
        }

        @Override
        public boolean testCompatibility(String s, ParsedSchema parsedSchema) throws IOException, RestClientException {
            return false;
        }

        @Override
        public String updateCompatibility(String s, String s1) throws IOException, RestClientException {
            return null;
        }

        @Override
        public String getCompatibility(String s) throws IOException, RestClientException {
            return null;
        }

        @Override
        public String setMode(String s) throws IOException, RestClientException {
            return null;
        }

        @Override
        public String setMode(String s, String s1) throws IOException, RestClientException {
            return null;
        }

        @Override
        public String getMode() throws IOException, RestClientException {
            return null;
        }

        @Override
        public String getMode(String s) throws IOException, RestClientException {
            return null;
        }

        @Override
        public Collection<String> getAllSubjects() throws IOException, RestClientException {
            return null;
        }

        @Override
        public int getId(String s, ParsedSchema parsedSchema) throws IOException, RestClientException {
            return 0;
        }

        @Override
        public void reset() {

        }
    }
}
