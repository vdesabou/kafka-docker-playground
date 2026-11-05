# Apache Kafka Java client (kafka-clients) with the Confluent Avro serializer for Schema Registry, on Java 21
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY pom.xml .
RUN mvn -q -B dependency:go-offline
COPY src src
RUN mvn -q -B package -DskipTests

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /src/target/client-java.jar .
CMD ["sleep", "infinity"]
