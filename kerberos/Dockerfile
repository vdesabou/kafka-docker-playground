FROM confluentinc/cp-kafka-connect-base:5.3.1

RUN   confluent-hub install --no-prompt confluentinc/kafka-connect-ibmmq:latest \
		&& confluent-hub install --no-prompt confluentinc/kafka-connect-http:latest \
		&& confluent-hub install --no-prompt debezium/debezium-connector-mysql:latest \
		&& confluent-hub install --no-prompt confluentinc/kafka-connect-elasticsearch:latest \
		&& confluent-hub install --no-prompt wepay/kafka-connect-bigquery:latest \
		&& confluent-hub install --no-prompt confluentinc/kafka-connect-gcs:latest \
		&& confluent-hub install --no-prompt confluentinc/kafka-connect-hdfs:latest \
		&& confluent-hub install --no-prompt confluentinc/kafka-connect-jdbc:latest \
		&& confluent-hub install --no-prompt confluentinc/kafka-connect-kinesis:latest \
		&& confluent-hub install --no-prompt confluentinc/kafka-connect-s3:latest \
		&& confluent-hub install --no-prompt confluentinc/kafka-connect-s3-source:latest \
		&& confluent-hub install --no-prompt confluentinc/kafka-connect-sqs:latest \