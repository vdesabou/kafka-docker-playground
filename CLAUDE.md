# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **kafka-docker-playground**, a comprehensive testing framework for Apache Kafka and Confluent Platform. It provides:
- 170+ self-managed connector examples (`connect/` directory)
- 100+ Confluent Cloud fully-managed connector examples (`ccloud/` directory)
- Reproduction models for testing and debugging (`reproduction-models/` - private submodule)
- Multiple secured environments (SASL, RBAC, SSL, Kerberos, etc. in `environment/`)
- A powerful CLI tool (`scripts/cli/playground`)

Documentation: https://kafka-docker-playground.io/

## Common Commands

### Running Examples

```bash
# Run an example interactively (recommended)
playground run

# Run a specific example
cd connect/connect-aws-s3-sink
./s3-sink.sh

# Re-run the last example
playground re-run

# Stop currently running example
playground stop

# View run history and rerun
playground history
```

### Environment Management

```bash
# Start a specific environment (called from within example scripts)
playground start-environment --environment plaintext
playground start-environment --environment sasl-plain
playground start-environment --environment 2way-ssl

# Specify Confluent Platform version
playground run --tag 7.5.0

# Update versions of running components
playground update-version --tag 7.6.0
```

### Connector Operations

```bash
# Create or update a connector (used in example scripts)
playground connector create-or-update --connector <name> << EOF
{
  "connector.class": "...",
  ...
}
EOF

# List running connectors
playground connector status

# Show connector config
playground connector show-config --connector <name>

# Delete a connector
playground connector delete --connector <name>
```

### Schema Registry

```bash
# Get all schema versions for a subject
playground schema get --subject <subject-name>

# Register a schema
playground schema register --subject <subject> --schema-file <file>

# Get/set compatibility level
playground schema get-compatibility --subject <subject>
playground schema set-compatibility --subject <subject> --compatibility BACKWARD
```

### Debugging

```bash
# Enable remote debugging on a container
playground debug enable-remote-debugging --container connect

# Take thread dump
playground debug thread-dump --container connect

# Take heap dump
playground debug heap-dump --container connect

# Analyze heap dump
playground debug heap-analyze --heap-dump-file-path <path>

# TCP dump (network sniffing)
playground debug tcp-dump --container connect

# Generate diagnostics bundle
playground debug generate-diagnostics
```

### Container Operations

```bash
# Get container logs
playground container logs --container <name>

# Execute command in container
playground container exec --container <name> --command "<command>"

# Get JMX metrics
playground get-jmx-metrics --container <name>
```

## Architecture

### Example Structure

Each connector example follows this pattern:

1. **Source `scripts/utils.sh`**: Loads core utility functions and sets default environment variables (TAG, CP versions, etc.)

2. **Start Environment**: Uses `playground start-environment --environment <type>` with optional docker-compose overrides

3. **Configure Resources**: Creates topics, schemas, external resources (S3 buckets, databases, etc.)

4. **Create Connector**: Uses `playground connector create-or-update` to deploy the connector

5. **Verify**: Produces/consumes data to verify functionality

Example script structure:
```bash
#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Start environment
playground start-environment --environment plaintext

# Setup resources
# ... create topics, external resources, etc ...

# Create connector
playground connector create-or-update --connector my-connector << EOF
{
  "connector.class": "io.confluent.connect.SomeConnector",
  ...
}
EOF
```

### Directory Organization

- **`connect/connect-<name>/`**: Self-managed connector examples
  - Multiple `.sh` files for different scenarios
  - `docker-compose.plaintext*.yml` for environment-specific overrides
  - Optional subdirectories for custom code/configs
  
- **`ccloud/fm-<name>/`**: Confluent Cloud fully-managed connector examples

- **`reproduction-models/`**: Git submodule with private reproduction models
  - Organized by connector/feature
  - Each contains standalone reproduction scenarios

- **`environment/<type>/`**: Base Kafka environments
  - `plaintext/`: No authentication
  - `sasl-plain/`, `sasl-ssl/`, `2way-ssl/`, `kerberos/`: Secured environments
  - `rbac-sasl-plain/`: RBAC enabled
  - `mdc-*/`: Multi-datacenter configurations

- **`scripts/utils.sh`**: Core utility functions
  - Version handling (CP versions, connector versions)
  - Logging functions (`log`, `logwarn`, `logerror`)
  - AWS/Azure/GCP credential handling
  - Connector installation utilities

- **`scripts/cli/`**: Playground CLI implementation
  - `src/commands/`: Individual CLI commands
  - `src/lib/`: Shared libraries

### Environment Variables

Key environment variables (set in `scripts/utils.sh`):

- **`TAG`**: Confluent Platform version (default: 8.2.1)
- **`CONNECTOR_TAG`**: Specific connector version
- **`PLAYGROUND_ENVIRONMENT`**: Environment type (plaintext, sasl-plain, etc.)
- **`CP_*_IMAGE`**: Docker image names (CP_KAFKA_IMAGE, CP_CONNECT_IMAGE, etc.)
- **Cloud credentials**: AWS_*, AZURE_*, GCP_* for cloud connector examples

### Docker Compose Structure

Base environments are in `environment/<type>/docker-compose.yml`. Examples can override with:
```bash
playground start-environment \
  --environment plaintext \
  --docker-compose-override-file "${PWD}/docker-compose.plaintext.override.yml"
```

Override files typically add:
- Connector-specific dependencies (databases, message queues, etc.)
- Custom volumes for connector plugins
- Additional environment variables
- Network configurations

## Building Reproduction Models

### Bootstrap a New Reproduction Model

```bash
playground repro bootstrap
```

This creates a new reproduction model in `reproduction-models/` with:
- Template script
- Docker compose override
- README placeholder

### Export/Import Reproduction Models

```bash
# Export uncommitted reproduction models
playground repro export --all

# Import a shared reproduction model
playground repro import --file playground_repro_export.tgz
```

### Reproduction Model Guidelines

- Keep reproduction models minimal and focused on the specific issue
- Do NOT include customer-sensitive information
- Include case number in filename (e.g., `fully-managed-s3-sink-repro-12345-description.sh`)
- Document expected vs actual behavior in comments

## Testing

### Running Tests Locally

```bash
# Run all tests
scripts/run-tests.sh ALL

# Run specific tests
scripts/run-tests.sh "connect/connect-aws-s3-sink connect/connect-jdbc-postgresql-sink"

# Run with specific version
scripts/run-tests.sh ALL 7.5.0

# Run with specific environment
scripts/run-tests.sh ALL 7.5.0 sasl-plain
```

### CI/CD

Tests run automatically via GitHub Actions (`.github/workflows/ci.yml`). Each example is tested independently with multiple CP versions.

## Working with Confluent Cloud

The repository includes MCP Confluent Server configuration (`config.yaml`) for:
- Kafka cluster operations
- Schema Registry
- Connector management
- Billing/cost tracking

Confluent Cloud examples in `ccloud/` use:
- Service accounts for authentication
- API keys stored in environment variables
- `playground switch-ccloud` to toggle between local and cloud

## Key Utilities

### Logging Functions

```bash
log "Info message"           # Standard output
logwarn "Warning message"    # Yellow warning
logerror "Error message"     # Red error
```

### Version Checking

```bash
# Check if CP version is greater than X
if connect_cp_version_greater_than_8; then
  # CP 8.0+ specific logic
fi

# Check connector version
if version_gt $CONNECTOR_TAG "10.5.0"; then
  # Version-specific logic
fi
```

## Common Patterns

### Handling Cloud Credentials

```bash
# AWS
handle_aws_credentials  # Loads from ~/.aws or env vars

# Azure
handle_azure_credentials

# GCP
handle_gcp_credentials
```

### Creating Connectors with Environment Variable Interpolation

```bash
playground connector create-or-update --connector my-sink << EOF
{
  "connector.class": "io.confluent.connect.s3.S3SinkConnector",
  "s3.bucket.name": "$AWS_BUCKET_NAME",
  "s3.region": "$AWS_REGION",
  "aws.access.key.id": "$AWS_ACCESS_KEY_ID",
  "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY"
}
EOF
```

### Conditional Logic Based on Environment

```bash
if [ "$PLAYGROUND_ENVIRONMENT" == "plaintext" ]; then
  # Plaintext-specific setup
elif [ "$PLAYGROUND_ENVIRONMENT" == "sasl-plain" ]; then
  # SASL-specific setup
fi
```

## Important Notes

- **Never commit secrets**: Use environment variables or `secrets.properties` (gitignored)
- **The `reproduction-models/` directory is a private git submodule**: Use `git clone --recursive` or `git submodule update --remote` to access
- **Examples are meant to be basic**: Focus is on automated testing and quick reproduction, not production-ready configurations
- **Each example should be self-contained**: Include all necessary setup and teardown
- **Use `playground` CLI**: Direct docker-compose commands may not work correctly due to the framework's state management
