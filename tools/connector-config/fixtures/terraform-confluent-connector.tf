resource "confluent_connector" "sink" {
  environment {
    id = confluent_environment.staging.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  config_sensitive = {
    "aws.secret.access.key" = var.aws_secret
  }
  config_nonsensitive = {
    "topics"                   = confluent_kafka_topic.orders.topic_name
    "input.data.format"        = "JSON"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-connector.id
    "s3.bucket.name"           = "${var.prefix}-bucket"
    "connector.class"          = "S3_SINK"
    "name"                     = "S3_SINKConnector_0"
    "tasks.max"                = "1"
    "flush.size"               = 1000
  }
  depends_on = [confluent_kafka_acl.app-connector-describe-on-cluster]
}
