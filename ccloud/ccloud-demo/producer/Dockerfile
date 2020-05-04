FROM adoptopenjdk/openjdk11:alpine
RUN apk add bash
COPY ./target/*.jar ./
ENV JAVA_OPTS ""
CMD [ "bash", "-c", "sleep 240 && java ${JAVA_OPTS} -jar *-jar-with-dependencies.jar" ]