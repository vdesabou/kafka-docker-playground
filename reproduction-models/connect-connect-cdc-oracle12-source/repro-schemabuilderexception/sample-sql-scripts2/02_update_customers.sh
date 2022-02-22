#!/bin/sh

echo 'Upate CUSTOMERS2 with email=fkafka@confluent.io'

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/$1 << EOF
  update CUSTOMERS2 set club_status = 'gold' where email = 'fkafka@confluent.io';
  exit;
EOF
