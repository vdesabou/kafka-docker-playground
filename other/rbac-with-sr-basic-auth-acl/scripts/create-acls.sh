#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

echo "Current ACLs:"
echo "*************"
sr-acl-cli --config /etc/schema-registry/schema-registry.properties --list