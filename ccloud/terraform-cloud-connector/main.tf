provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# Use existing environment (or create new one based on variable)
variable "use_existing_environment" {
  description = "Whether to use an existing environment"
  type        = bool
  default     = false
}

variable "environment_id" {
  description = "ID of existing environment (required if use_existing_environment = true)"
  type        = string
  default     = ""
}

# Data source for existing environment
data "confluent_environment" "existing" {
  count = var.use_existing_environment ? 1 : 0
  id    = var.environment_id
}

# Create new environment
resource "confluent_environment" "playground_env" {
  count        = var.use_existing_environment ? 0 : 1
  display_name = var.environment_name

  stream_governance {
    package = var.stream_governance_package
  }
}

# Local variable to get the environment ID
locals {
  environment_id = var.use_existing_environment ? data.confluent_environment.existing[0].id : confluent_environment.playground_env[0].id
}

# Kafka Cluster
resource "confluent_kafka_cluster" "playground_cluster" {
  display_name = var.cluster_name
  availability = var.cluster_availability
  cloud        = var.cloud_provider
  region       = var.cloud_region

  basic {}

  environment {
    id = local.environment_id
  }
}

# Service Account for admin operations (ACL management)
resource "confluent_service_account" "admin_service_account" {
  display_name = "${var.cluster_name}-admin-sa"
  description  = "Service account for managing ACLs"
}

# Admin API Key with full cluster access
resource "confluent_api_key" "admin_api_key" {
  display_name = "${var.cluster_name}-admin-api-key"
  description  = "API Key for admin operations"
  owner {
    id          = confluent_service_account.admin_service_account.id
    api_version = confluent_service_account.admin_service_account.api_version
    kind        = confluent_service_account.admin_service_account.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.playground_cluster.id
    api_version = confluent_kafka_cluster.playground_cluster.api_version
    kind        = confluent_kafka_cluster.playground_cluster.kind

    environment {
      id = local.environment_id
    }
  }
}

# Grant admin service account cluster admin rights via RBAC
resource "confluent_role_binding" "admin_cluster_admin" {
  principal   = "User:${confluent_service_account.admin_service_account.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.playground_cluster.rbac_crn
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
      id = local.environment_id
    }
  }

  depends_on = [
    confluent_role_binding.admin_cluster_admin
  ]
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
    key    = confluent_api_key.admin_api_key.id
    secret = confluent_api_key.admin_api_key.secret
  }

  depends_on = [
    confluent_role_binding.admin_cluster_admin
  ]
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
    key    = confluent_api_key.admin_api_key.id
    secret = confluent_api_key.admin_api_key.secret
  }

  depends_on = [
    confluent_role_binding.admin_cluster_admin
  ]
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
    key    = confluent_api_key.admin_api_key.id
    secret = confluent_api_key.admin_api_key.secret
  }

  depends_on = [
    confluent_role_binding.admin_cluster_admin
  ]
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
    key    = confluent_api_key.admin_api_key.id
    secret = confluent_api_key.admin_api_key.secret
  }

  depends_on = [
    confluent_role_binding.admin_cluster_admin
  ]
}
