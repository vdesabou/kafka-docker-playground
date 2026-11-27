#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# ksqlDB server and cli (same as playground run --enable-ksqldb)
export ENABLE_KSQLDB=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

log "The orders of the day, already in the topic"
playground topic produce -t orders --nb-messages 6 --forced-value '{"id": %g, "product": "product-%g", "amount": 10.5}'

log "The sales table of the dashboard"
playground ksqldb sql << 'EOF'
CREATE STREAM orders (id INT, product VARCHAR, amount DOUBLE) WITH (KAFKA_TOPIC='orders', VALUE_FORMAT='JSON');
CREATE TABLE sales AS SELECT product, SUM(amount) AS total FROM orders GROUP BY product EMIT CHANGES;
EOF

sleep 20

log "What the dashboard reads"
playground ksqldb sql << 'EOF'
SELECT * FROM sales;
EOF
