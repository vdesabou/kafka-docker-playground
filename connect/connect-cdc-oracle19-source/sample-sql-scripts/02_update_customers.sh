#!/bin/sh

echo 'Upate CUSTOMERS with email=fkafka@confluent.io'

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/$1 << EOF
  update CUSTOMERS set club_status = 'gold' where email = 'fkafka@confluent.io';
  exit;
EOF
