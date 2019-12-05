FROM gradle:6.0.1-jdk8 as gradleBuild
COPY build.gradle build.gradle
COPY src src
RUN gradle wrapper && ./gradlew build
CMD sleep infinity