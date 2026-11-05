# Confluent JavaScript client (@confluentinc/kafka-javascript, on librdkafka: prebuilt binaries for linux glibc
# x64/arm64, hence a Debian image and not Alpine) with the Avro serializer of @confluentinc/schemaregistry, on Node.js 24 (LTS)
FROM node:24-trixie-slim
# the prebuilt librdkafka verifies the broker certificates (SASL_SSL, Confluent Cloud) with the system CA store, empty in the slim image
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package.json package-lock.json ./
# CLIENT_VERSION (optional): another @confluentinc/kafka-javascript version than the one of package.json, e.g. 1.4.0
# (@confluentinc/schemaregistry stays on the version of package-lock.json)
ARG CLIENT_VERSION=""
RUN npm ci --omit=dev \
    && if [ -n "$CLIENT_VERSION" ]; then npm install --omit=dev "@confluentinc/kafka-javascript@$CLIENT_VERSION"; fi
COPY client.js .
CMD ["sleep", "infinity"]
