#!/bin/sh

# Update Oracle 19c to not include ALTER TABLE ADD #1109
# https://github.com/vdesabou/kafka-docker-playground/issues/1109
# FIXTHIS

echo 'DDL is not fully supported for now'
exit 0


echo 'Populating CUSTOMERS table after altering the structure'

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/$1 << EOF
  insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments, country) values ('Josef', 'K', 'jk@confluent.io', 'Male', 'bronze', 'How is it even possible for someone to be guilty', 'Poland');
  update CUSTOMERS set club_status = 'silver' where email = 'gsamsa@confluent.io';
  exit;
EOF
