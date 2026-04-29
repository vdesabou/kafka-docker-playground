#!/bin/bash
set -e

#############################################
# ONE-LINER INSTALLER
# Copy-paste this into your terminal:
#
# curl -fsSL https://raw.githubusercontent.com/vdesabou/kafka-docker-playground/master/ccloud/terraform-cloud-connector/ONE_LINER_INSTALL.sh | bash
#
#############################################

echo "🚀 Terraform Cloud Connector - One-Liner Install"
echo ""

# Check if in the right directory
if [[ ! -f "bootstrap.sh" ]]; then
    echo "⚠️  Not in the terraform-cloud-connector directory."
    echo "Navigating there now..."

    if [[ -d "ccloud/terraform-cloud-connector" ]]; then
        cd ccloud/terraform-cloud-connector
    elif [[ -d "kafka-docker-playground/ccloud/terraform-cloud-connector" ]]; then
        cd kafka-docker-playground/ccloud/terraform-cloud-connector
    else
        echo "❌ Cannot find terraform-cloud-connector directory."
        echo "Please cd to the correct location and run again."
        exit 1
    fi
fi

# Make scripts executable
chmod +x *.sh 2>/dev/null || true

# Run bootstrap
./bootstrap.sh

echo ""
echo "✅ Installation complete!"
