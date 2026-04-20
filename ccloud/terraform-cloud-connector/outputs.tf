output "environment_id" {
  description = "Confluent Cloud Environment ID"
  value       = confluent_environment.playground_env.id
}

output "cluster_id" {
  description = "Kafka Cluster ID (lkc-*)"
  value       = confluent_kafka_cluster.playground_cluster.id
}

output "cluster_bootstrap_endpoint" {
  description = "Kafka Cluster Bootstrap Endpoint"
  value       = confluent_kafka_cluster.playground_cluster.bootstrap_endpoint
}

output "cluster_rest_endpoint" {
  description = "Kafka Cluster REST Endpoint"
  value       = confluent_kafka_cluster.playground_cluster.rest_endpoint
}

output "service_account_id" {
  description = "Service Account ID for connectors"
  value       = confluent_service_account.connector_service_account.id
}

output "api_key_id" {
  description = "API Key ID for connector authentication"
  value       = confluent_api_key.connector_api_key.id
  sensitive   = true
}

output "api_key_secret" {
  description = "API Key Secret for connector authentication"
  value       = confluent_api_key.connector_api_key.secret
  sensitive   = true
}

output "connector_details" {
  description = "Details for running connectors"
  value = {
    cluster_id         = confluent_kafka_cluster.playground_cluster.id
    environment_id     = confluent_environment.playground_env.id
    service_account_id = confluent_service_account.connector_service_account.id
    bootstrap_endpoint = confluent_kafka_cluster.playground_cluster.bootstrap_endpoint
    rest_endpoint      = confluent_kafka_cluster.playground_cluster.rest_endpoint
  }
}
