#!/bin/sh

echo 'Altering CUSTOMERS table with an optional column'

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/$1 << EOF
  alter table CUSTOMERS add (
    country VARCHAR(50)
  );
  exit;
EOF
