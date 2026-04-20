terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# Environment
resource "confluent_environment" "playground_env" {
  display_name = var.environment_name

  stream_governance {
    package = var.stream_governance_package
  }
}

# Kafka Cluster
resource "confluent_kafka_cluster" "playground_cluster" {
  display_name = var.cluster_name
  availability = var.cluster_availability
  cloud        = var.cloud_provider
  region       = var.cloud_region

  basic {}

  environment {
    id = confluent_environment.playground_env.id
  }
}

# Service Account for connectors
resource "confluent_service_account" "connector_service_account" {
  display_name = "${var.cluster_name}-connector-sa"
  description  = "Service account for Kafka Connect connectors"
}

# API Key for the service account
resource "confluent_api_key" "connector_api_key" {
  display_name = "${var.cluster_name}-connector-api-key"
  description  = "API Key for connector service account"
  owner {
    id          = confluent_service_account.connector_service_account.id
    api_version = confluent_service_account.connector_service_account.api_version
    kind        = confluent_service_account.connector_service_account.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.playground_cluster.id
    api_version = confluent_kafka_cluster.playground_cluster.api_version
    kind        = confluent_kafka_cluster.playground_cluster.kind

    environment {
      id = confluent_environment.playground_env.id
    }
  }
}

# ACL for connector service account
resource "confluent_kafka_acl" "connector_acl_read" {
  kafka_cluster {
    id = confluent_kafka_cluster.playground_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connector_service_account.id}"
  operation     = "READ"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.playground_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.connector_api_key.id
    secret = confluent_api_key.connector_api_key.secret
  }
}

resource "confluent_kafka_acl" "connector_acl_write" {
  kafka_cluster {
    id = confluent_kafka_cluster.playground_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connector_service_account.id}"
  operation     = "WRITE"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.playground_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.connector_api_key.id
    secret = confluent_api_key.connector_api_key.secret
  }
}

resource "confluent_kafka_acl" "connector_acl_create" {
  kafka_cluster {
    id = confluent_kafka_cluster.playground_cluster.id
  }
  resource_type = "TOPIC"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connector_service_account.id}"
  operation     = "CREATE"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.playground_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.connector_api_key.id
    secret = confluent_api_key.connector_api_key.secret
  }
}

resource "confluent_kafka_acl" "connector_acl_consumer_group" {
  kafka_cluster {
    id = confluent_kafka_cluster.playground_cluster.id
  }
  resource_type = "GROUP"
  resource_name = "*"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.connector_service_account.id}"
  operation     = "READ"
  permission    = "ALLOW"
  host          = "*"
  rest_endpoint = confluent_kafka_cluster.playground_cluster.rest_endpoint
  credentials {
    key    = confluent_api_key.connector_api_key.id
    secret = confluent_api_key.connector_api_key.secret
  }
}
