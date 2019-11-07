FROM alpine:3.10

RUN apk add --no-cache curl

ENV VERSION 0.12.0
ENV JAR jmx_prometheus_javaagent-$VERSION.jar

RUN mkdir -p /usr/share/jmx_exporter/
RUN curl -L https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/$VERSION/$JAR -o /usr/share/jmx_exporter/$JAR

ADD configs /usr/share/jmx_exporter/

CMD /bin/sh
