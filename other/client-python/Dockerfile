# Confluent Python client (confluent-kafka, on librdkafka) with the Avro serializer for Schema Registry.
# The manylinux wheel bundles librdkafka: no compiler needed.
FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
# CLIENT_VERSION (optional): another confluent-kafka version than the one of requirements.txt, e.g. 2.3.0
ARG CLIENT_VERSION=""
RUN if [ -n "$CLIENT_VERSION" ]; then \
        pip install --no-cache-dir "confluent-kafka[avro,schemaregistry]==$CLIENT_VERSION"; \
    else \
        pip install --no-cache-dir -r requirements.txt; \
    fi
COPY client.py .
CMD ["sleep", "infinity"]
