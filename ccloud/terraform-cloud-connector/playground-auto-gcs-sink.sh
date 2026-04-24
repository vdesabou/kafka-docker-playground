#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# Run universal connector script with this connector type
bash "$DIR/playground-auto-connector.sh" --connector GCS_SINK "$@"
