# Get the image 
FROM confluentinc/cp-server-connect-base:7.3.2

# Add connectors you need there, example with JDBC
RUN confluent-hub install --no-prompt debezium/debezium-connector-sqlserver:latest

COPY data /data
COPY worker.properties /tmp/worker.properties
COPY connector.properties /tmp/connector.properties
CMD ["bash", "-c", "/usr/bin/connect-standalone /tmp/worker.properties /tmp/connector.properties"]