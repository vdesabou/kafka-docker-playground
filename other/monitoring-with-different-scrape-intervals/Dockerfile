FROM adoptopenjdk/openjdk11:slim
WORKDIR /app

COPY ./jmx_prometheus_httpserver-0.16.1-jar-with-dependencies.jar /app/jmx_prometheus_httpserver-0.16.1-jar-with-dependencies.jar

ENV JAVA_OPTS=""
ENV JMX_EXPORTER_PORT="1234"
ENV JMX_EXPORTER_CONFIG_FILE="no-file"

ENTRYPOINT java ${JAVA_OPTS} -jar /app/jmx_prometheus_httpserver-0.16.1-jar-with-dependencies.jar ${JMX_EXPORTER_PORT} ${JMX_EXPORTER_CONFIG_FILE}
