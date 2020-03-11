ARG TAG
ARG CP_BASE_IMAGE

FROM gradle:6.0.1-jdk8 as gradleBuild
COPY build.gradle build.gradle
COPY settings.gradle settings.gradle
COPY src src
RUN gradle wrapper && ./gradlew build && ./gradlew shadowJar

ARG TAG
ARG CP_BASE_IMAGE
FROM confluentinc/${CP_BASE_IMAGE}:${TAG}
COPY --from=gradleBuild /home/gradle/build/libs/kstreams-standalone*.jar ./
ENV JAVA_OPTS ""
CMD [ "bash", "-c", "cub sr-ready schema-registry 8081 120 && java ${JAVA_OPTS} -cp *.jar io.confluent.developer.helper.TopicCreation && java ${JAVA_OPTS} -cp *.jar io.confluent.developer.helper.SchemaPublication && java ${JAVA_OPTS} -jar *.jar" ]