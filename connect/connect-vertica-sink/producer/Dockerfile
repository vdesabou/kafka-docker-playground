ARG TAG

FROM maven:3.6.1-jdk-8 as mavenBuild
COPY pom.xml pom.xml
COPY src src
RUN ["mvn", "install", "-q"]

ARG TAG
FROM confluentinc/cp-base:${TAG}
COPY --from=mavenBuild ./target/*.jar ./
ENV JAVA_OPTS ""
CMD [ "bash", "-c", "cub sr-ready schema-registry 8081 120 && java ${JAVA_OPTS} -jar *.jar" ]