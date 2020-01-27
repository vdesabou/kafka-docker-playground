ARG TAG
ARG CP_BASE_IMAGE
FROM confluentinc/${CP_BASE_IMAGE}:${TAG}
COPY ./target/*.jar ./
ENV JAVA_OPTS ""
CMD sleep infinity