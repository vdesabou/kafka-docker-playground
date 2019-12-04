FROM gradle:6.0.1-jdk8 as gradleBuild
COPY build.gradle build.gradle
COPY src src
RUN gradle wrapper && ./gradlew build && ./gradlew shadowJar

FROM confluentinc/cp-base:5.3.1
COPY --from=gradleBuild /home/gradle/build/libs/kstreams-transform-standalone*.jar ./
COPY configuration configuration
ENV JAVA_OPTS ""
CMD [ "bash", "-c", "cub sr-ready schema-registry 8081 120 && java ${JAVA_OPTS} -jar *.jar configuration/dev.properties" ]