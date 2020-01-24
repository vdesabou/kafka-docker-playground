ARG TAG
ARG CP_BASE_IMAGE
ARG KAFKA_CLIENT_TAG

FROM maven:3.6.1-jdk-8 as mavenBuild
COPY pom.xml pom.xml
COPY src src
ARG TAG
ARG CP_BASE_IMAGE
ARG KAFKA_CLIENT_TAG
ENV TAG=${TAG}
ENV KAFKA_CLIENT_TAG=${KAFKA_CLIENT_TAG}
RUN ["mvn", "install", "-q"]

ARG TAG
ARG CP_BASE_IMAGE
FROM confluentinc/${CP_BASE_IMAGE}:${TAG}
COPY --from=mavenBuild ./target/*.jar ./
ENV JAVA_OPTS ""
CMD [ "bash", "-c", "cub sr-ready schema-registry 8085 120 && java ${JAVA_OPTS} -jar *-jar-with-dependencies.jar" ]