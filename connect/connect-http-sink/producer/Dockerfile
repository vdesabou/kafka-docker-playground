FROM adoptopenjdk/openjdk11:alpine
RUN apk add bash
COPY ./target/*.jar ./
ENV JAVA_OPTS ""
CMD sleep infinity