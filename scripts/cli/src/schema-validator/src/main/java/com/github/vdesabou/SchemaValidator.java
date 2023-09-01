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
import io.confluent.kafka.schemaregistry.avro.*;
import io.confluent.kafka.schemaregistry.json.*;
import io.confluent.kafka.serializers.json.KafkaJsonSchemaSerializer;
import io.confluent.kafka.serializers.KafkaAvroSerializer;
import io.confluent.connect.avro.*;
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
    private final String schemaType;

    public static void main(String[] args) throws InterruptedException, ExecutionException {
        SchemaValidator schemaValidator = new SchemaValidator();
        schemaValidator.start();
    }

    public SchemaValidator() throws ExecutionException, InterruptedException {
        properties = buildProperties(defaultProps, System.getenv(), KAFKA_ENV_PREFIX);
        schemaType = System.getenv().getOrDefault("SCHEMA_TYPE", "");
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

            if (schemaType.equals("json-schema")) {
                CachedSchemaRegistryClient schemaRegistryClient = new CachedSchemaRegistryClient("http://schema-registry:8081",1000);
                schemaRegistryClient.register(randomName+"-value", new JsonSchema(rawSchemaJson));
                KafkaJsonSchemaSerializer serializer = new KafkaJsonSchemaSerializer(schemaRegistryClient);
                JsonSchemaConverter converter = new JsonSchemaConverter();
                byte[] serializedRecord1 = serializer.serialize(randomName,
                JsonSchemaUtils.envelope(rawSchemaJson, masterJSON));

                converter.configure(properties, false);
                converter.toConnectData(randomName, serializedRecord1);
            } else if (schemaType.equals("avro")) {
                CachedSchemaRegistryClient schemaRegistryClient = new CachedSchemaRegistryClient("http://schema-registry:8081",1000);


// [ERROR] Failed to execute goal org.apache.maven.plugins:maven-compiler-plugin:3.7.0:compile (default-compile) on project schema-validator: Compilation failure
// [ERROR] /usr/src/mymaven/src/main/java/com/github/vdesabou/SchemaValidator.java:[73,68] no suitable constructor found for AvroSchema(com.fasterxml.jackson.databind.JsonNode)
// [ERROR]     constructor io.confluent.kafka.schemaregistry.avro.AvroSchema.AvroSchema(java.lang.String) is not applicable
// [ERROR]       (argument mismatch; com.fasterxml.jackson.databind.JsonNode cannot be converted to java.lang.String)
// [ERROR]     constructor io.confluent.kafka.schemaregistry.avro.AvroSchema.AvroSchema(org.apache.avro.Schema) is not applicable
// [ERROR]       (argument mismatch; com.fasterxml.jackson.databind.JsonNode cannot be converted to org.apache.avro.Schema)
                schemaRegistryClient.register(randomName+"-value", new AvroSchema(rawSchemaJson));
                KafkaAvroSerializer serializer = new KafkaAvroSerializer(schemaRegistryClient);
                AvroConverter converter = new AvroConverter();
                byte[] serializedRecord1 = serializer.serialize(randomName,
                JsonSchemaUtils.envelope(rawSchemaJson, masterJSON));

                converter.configure(properties, false);
                converter.toConnectData(randomName, serializedRecord1);
            } 

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