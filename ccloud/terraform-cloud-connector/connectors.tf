# Connector resource - conditionally created based on connector_configs variable
# This file supports dynamic connector creation via terraform.tfvars

variable "connector_configs" {
  description = "List of connector configurations"
  type = list(object({
    name           = string
    connector_class = string
    kafka_api_key  = string
    kafka_api_secret = string
    config         = map(string)
  }))
  default = []
}

resource "confluent_connector" "cloud_connectors" {
  for_each = { for idx, connector in var.connector_configs : connector.name => connector }

  environment {
    id = confluent_environment.playground_env.id
  }

  kafka_cluster {
    id = confluent_kafka_cluster.playground_cluster.id
  }

  config_sensitive = merge(
    {
      "connector.class"    = each.value.connector_class
      "name"               = each.value.name
      "kafka.auth.mode"    = "KAFKA_API_KEY"
      "kafka.api.key"      = confluent_api_key.connector_api_key.id
      "kafka.api.secret"   = confluent_api_key.connector_api_key.secret
    },
    each.value.config
  )

  depends_on = [
    confluent_kafka_acl.connector_acl_read,
    confluent_kafka_acl.connector_acl_write,
    confluent_kafka_acl.connector_acl_create,
    confluent_kafka_acl.connector_acl_consumer_group,
  ]
}

output "connector_ids" {
  description = "IDs of created connectors (lcc-*)"
  value       = { for k, v in confluent_connector.cloud_connectors : k => v.id }
}

output "connector_status" {
  description = "Status of created connectors"
  value       = { for k, v in confluent_connector.cloud_connectors : k => v.status }
}
