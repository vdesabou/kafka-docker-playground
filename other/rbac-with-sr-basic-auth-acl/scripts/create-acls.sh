#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

echo "Creating ACLs..."
echo "*************"
sr-acl-cli --config /etc/schema-registry/schema-registry.properties --add --subject '*' --principal sr-admin --operation '*'


echo "Current ACLs:"
echo "*************"
sr-acl-cli --config /etc/schema-registry/schema-registry.properties --list