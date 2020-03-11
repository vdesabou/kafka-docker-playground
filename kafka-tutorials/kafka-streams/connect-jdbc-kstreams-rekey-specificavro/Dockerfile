ARG TAG
ARG CP_BASE_IMAGE

FROM gradle:6.0.1-jdk8 as gradleBuild
COPY build.gradle build.gradle
COPY src src
RUN gradle build && gradle shadowJar

ARG TAG
ARG CP_BASE_IMAGE
FROM confluentinc/${CP_BASE_IMAGE}:${TAG}
COPY --from=gradleBuild /home/gradle/build/libs/connect-jdbc-kstreams-rekey-specificavro-0.0.1-standalone.jar ./
COPY configuration configuration
ENV JAVA_OPTS ""
CMD [ "bash", "-c", "cub sr-ready schema-registry 8081 120 && java ${JAVA_OPTS} -jar *.jar configuration/dev.properties" ]