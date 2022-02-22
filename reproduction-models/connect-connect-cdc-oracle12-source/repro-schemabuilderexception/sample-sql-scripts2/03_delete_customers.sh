#!/bin/sh

echo 'Deleting CUSTOMERS2 with email=fkafka@confluent.io'

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/$1 << EOF
  delete from CUSTOMERS2 where email = 'fkafka@confluent.io';
  exit;
EOF
