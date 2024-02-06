FROM eclipse-temurin:11-jdk
COPY ./target/*.jar ./
ENV JAVA_OPTS ""
CMD [ "bash", "-c", "sleep 240 && java ${JAVA_OPTS} -jar *-jar-with-dependencies.jar" ]