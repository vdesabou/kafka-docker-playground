FROM maven:3.6.1-jdk-8 as mavenBuild
COPY pom.xml pom.xml
COPY src src
RUN ["mvn", "install"]

FROM confluentinc/cp-base:5.3.2
COPY --from=mavenBuild ./target/*.jar ./
ENV JAVA_OPTS ""
CMD [ "bash", "-c", "cub sr-ready schema-registry 8085 120 && java ${JAVA_OPTS} -jar *.jar" ]