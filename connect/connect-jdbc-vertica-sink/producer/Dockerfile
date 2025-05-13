ARG CP_CONNECT_TAG
ARG CP_CONNECT_IMAGE
FROM ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}
COPY ./target/*.jar ./
ENV JAVA_OPTS ""
CMD [ "bash", "-c", "cub sr-ready schema-registry 8081 120 && java ${JAVA_OPTS} -jar *-jar-with-dependencies.jar" ]