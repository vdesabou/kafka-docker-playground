# KafkaJS (kafkajs, pure JavaScript) with the Avro serializer of @kafkajs/confluent-schema-registry, on Node.js 24 (LTS).
FROM node:24-trixie-slim
WORKDIR /app
COPY package.json package-lock.json ./
# CLIENT_VERSION (optional): another kafkajs version than the one of package.json, e.g. 2.1.0
# (@kafkajs/confluent-schema-registry stays on the version of package-lock.json)
ARG CLIENT_VERSION=""
RUN npm ci --omit=dev \
    && if [ -n "$CLIENT_VERSION" ]; then npm install --omit=dev "kafkajs@$CLIENT_VERSION"; fi
COPY client.js .
# kafkajs passes a negative delay to setTimeout (its request timeouts), which Node.js 23+ reports on every client
# with "TimeoutNegativeWarning: -1793882821993 is a negative number." (Node.js uses 1 ms instead): hide only that warning,
# kafkajs is not maintained anymore
ENV NODE_OPTIONS=--disable-warning=TimeoutNegativeWarning
CMD ["sleep", "infinity"]
