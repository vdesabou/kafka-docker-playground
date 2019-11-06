#!/bin/bash

set -e

#!/bin/bash

CONFIG_FILE=~/.ccloud/config

set -eu

./ccloud-generate-env-vars.sh $CONFIG_FILE
source delta_configs/env.delta

# Delete topic in Confluent Cloud
echo "Delete topic customer-avro"
kafka-topics --bootstrap-server `grep "^\s*bootstrap.server" $CONFIG_FILE | tail -1` --command-config $CONFIG_FILE --topic customer-avro --delete 2>/dev/null || true

echo "Delete topic mysql-application"
kafka-topics --bootstrap-server `grep "^\s*bootstrap.server" $CONFIG_FILE | tail -1` --command-config $CONFIG_FILE --topic mysql-application --delete 2>/dev/null || true

docker-compose down -v