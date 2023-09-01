package com.github.vdesabou;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient;
import io.confluent.kafka.schemaregistry.json.*;
import io.confluent.kafka.serializers.json.KafkaJsonSchemaSerializer;
import io.confluent.connect.json.*;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;
import com.github.javafaker.Faker;

public class SchemaValidator {

    private static final String KAFKA_ENV_PREFIX = "KAFKA_";
    private final Logger logger = LoggerFactory.getLogger(SchemaValidator.class);
    private final Map<String, String> properties;
    private final String topicName;
    private final Long messageBackOff;
    private Long nbMessages;

    public static void main(String[] args) throws InterruptedException, ExecutionException {
        SchemaValidator schemaValidator = new SchemaValidator();
        schemaValidator.start();
    }

    public SchemaValidator() throws ExecutionException, InterruptedException {
        properties = buildProperties(defaultProps, System.getenv(), KAFKA_ENV_PREFIX);
        topicName = System.getenv().getOrDefault("TOPIC", "sample");
        messageBackOff = Long.valueOf(System.getenv().getOrDefault("MESSAGE_BACKOFF", "100"));
    }

    private void start() throws InterruptedException {
        logger.info("creating schema validator with props: {}", properties);
        Faker faker = new Faker();

        try {
            JsonNode rawSchemaJson = readJsonNode("/tmp/schema.json");
            ObjectMapper mapper = new ObjectMapper();

            String randomName = faker.name().firstName();
            File from = new File("/tmp/message.json");
            JsonNode masterJSON = mapper.readTree(from);

            CachedSchemaRegistryClient schemaRegistryClient = new CachedSchemaRegistryClient("http://schema-registry:8081",1000);
             schemaRegistryClient.register(randomName+"-value", new JsonSchema(rawSchemaJson));

            KafkaJsonSchemaSerializer serializer = new KafkaJsonSchemaSerializer(schemaRegistryClient);

            byte[] serializedRecord1 = serializer.serialize(randomName,
                    JsonSchemaUtils.envelope(rawSchemaJson, masterJSON)
            );
            JsonSchemaConverter converter = new JsonSchemaConverter();
            converter.configure(properties, false);
            converter.toConnectData(randomName, serializedRecord1);
        } catch(Exception e) {
            logger.error("Exception: ", e);
        }
    }

    private JsonNode readJsonNode(String relPath) throws IOException {
        try (InputStream stream = getStream(relPath)) {
            return new ObjectMapper().readTree(stream);
        }
    }

    private InputStream getStream(String relPath) throws IOException {
        String absPath = relPath;
        File initialFile = new File(absPath);
        InputStream inputStream = new FileInputStream(initialFile);
        return inputStream;
    }

    private Map<String, String> defaultProps = Map.of(
            "schema.registry.url", "http://schema-registry:8081");

    private Map<String, String> buildProperties(Map<String, String> baseProps, Map<String, String> envProps, String prefix) {
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

        // Merge the maps
        Map<String, String> mergedMap = new HashMap<>(baseProps);
        mergedMap.putAll(systemProperties);
        return mergedMap;
    }
}