variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key"
  type        = string
  sensitive   = true
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

variable "environment_name" {
  description = "Name of the Confluent Cloud environment"
  type        = string
  default     = "playground-terraform-env"
}

variable "cluster_name" {
  description = "Name of the Kafka cluster"
  type        = string
  default     = "playground-terraform-cluster"
}

variable "cloud_provider" {
  description = "Cloud provider (AWS, GCP, or AZURE)"
  type        = string
  default     = "AWS"

  validation {
    condition     = contains(["AWS", "GCP", "AZURE"], var.cloud_provider)
    error_message = "Cloud provider must be AWS, GCP, or AZURE."
  }
}

variable "cloud_region" {
  description = "Cloud region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_availability" {
  description = "Cluster availability (SINGLE_ZONE or MULTI_ZONE)"
  type        = string
  default     = "SINGLE_ZONE"

  validation {
    condition     = contains(["SINGLE_ZONE", "MULTI_ZONE"], var.cluster_availability)
    error_message = "Cluster availability must be SINGLE_ZONE or MULTI_ZONE."
  }
}

variable "stream_governance_package" {
  description = "Stream Governance package (ESSENTIALS or ADVANCED)"
  type        = string
  default     = "ESSENTIALS"

  validation {
    condition     = contains(["ESSENTIALS", "ADVANCED"], var.stream_governance_package)
    error_message = "Stream Governance package must be ESSENTIALS or ADVANCED."
  }
}

variable "connector_config_file" {
  description = "Path to connector configuration JSON file"
  type        = string
  default     = ""
}

variable "existing_cluster_id" {
  description = "ID of existing Kafka cluster (for connector-only deployments)"
  type        = string
  default     = ""
}
