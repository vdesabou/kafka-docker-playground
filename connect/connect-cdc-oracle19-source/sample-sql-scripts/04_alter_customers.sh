#!/bin/sh

# Update Oracle 19c to not include ALTER TABLE ADD #1109
# https://github.com/vdesabou/kafka-docker-playground/issues/1109
# FIXTHIS

echo 'DDL is not fully supported for now'
exit 0

echo 'Altering CUSTOMERS table with an optional column'

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/$1 << EOF
  alter table CUSTOMERS add (
    country VARCHAR(50)
  );
  exit;
EOF
