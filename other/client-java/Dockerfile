# Apache Kafka Java client (kafka-clients) with the Confluent Avro serializer for Schema Registry, on Java 21
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY pom.xml .
# CLIENT_VERSION (optional): another kafka-clients version than the kafka.version of pom.xml, e.g. 3.9.1.
# kafka-avro-serializer follows it with the Confluent Platform release of that Apache Kafka version (4.x: confluent.version
# of pom.xml, 3.N: 7.N.0, 2.6-2.8: 6.0-6.2.0, 2.0-2.5: 5.0-5.5.0): 8.x needs kafka-clients 4.x (NoClassDefFoundError
# org/apache/kafka/common/metrics/Monitorable otherwise)
ARG CLIENT_VERSION=""
RUN echo "" > /tmp/mvn-args \
    && if [ -n "$CLIENT_VERSION" ]; then \
        major=$(echo "$CLIENT_VERSION" | cut -d. -f1); minor=$(echo "$CLIENT_VERSION" | cut -d. -f2); \
        case "$major" in \
            4) confluent="" ;; \
            3) confluent="7.$minor.0" ;; \
            2) if [ "$minor" -ge 6 ]; then confluent="6.$((minor - 6)).0"; else confluent="5.$minor.0"; fi ;; \
            *) echo "CLIENT_VERSION $CLIENT_VERSION: only kafka-clients 2.x, 3.x and 4.x are supported" >&2; exit 1 ;; \
        esac; \
        echo "-Dkafka.version=$CLIENT_VERSION${confluent:+ -Dconfluent.version=$confluent}" > /tmp/mvn-args; \
        echo "kafka-clients $CLIENT_VERSION, kafka-avro-serializer ${confluent:-of pom.xml}"; \
    fi \
    && mvn -q -B dependency:go-offline $(cat /tmp/mvn-args)
COPY src src
RUN mvn -q -B package -DskipTests $(cat /tmp/mvn-args)

# lab target (docker-compose.plaintext.lab.yml, start-lab.sh): a JDK to run the single-file programs of labs/ with
# java X.java, the client jars of the build (same CLIENT_VERSION) in /usr/share/java/kafka like in the Confluent
# Platform images, and procps (pkill, ps). Not built by default: the default target is the last stage.
# Logging goes through log4j2 like in the Confluent Platform 8 images (slf4j-simple of the fat jar left out, log4j-slf4j2-impl
# for the slf4j-api 2.x of pom.xml), so a -Dlog4j2.configurationFile=<file> of the java command takes effect
FROM build AS lab-jars
ARG LOG4J_VERSION=2.26.1
RUN mvn -q -B dependency:copy-dependencies -DincludeScope=runtime -DexcludeArtifactIds=slf4j-simple -DoutputDirectory=/jars $(cat /tmp/mvn-args) \
    && for artifact in log4j-api log4j-core log4j-slf4j2-impl; do \
        mvn -q -B dependency:copy -Dartifact=org.apache.logging.log4j:$artifact:$LOG4J_VERSION -DoutputDirectory=/jars; \
    done

FROM eclipse-temurin:21-jdk AS lab
RUN apt-get update \
    && apt-get install -y --no-install-recommends procps \
    && rm -rf /var/lib/apt/lists/*
COPY --from=lab-jars /jars /usr/share/java/kafka
ENV CONFLUENT_HOME=/usr
WORKDIR /app/labs
CMD ["sleep", "infinity"]

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /src/target/client-java.jar .
CMD ["sleep", "infinity"]
