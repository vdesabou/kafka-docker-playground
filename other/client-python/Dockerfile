# Confluent Python client (confluent-kafka, on librdkafka) with the Avro serializer for Schema Registry.
# The manylinux wheel bundles librdkafka: no compiler needed.
FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY client.py .
CMD ["sleep", "infinity"]
