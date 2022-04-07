#!/bin/sh

echo 'Deleting CUSTOMERS with email=fkafka@confluent.io'

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/$1 << EOF
  delete from CUSTOMERS where email = 'fkafka@confluent.io';
  exit;
EOF
