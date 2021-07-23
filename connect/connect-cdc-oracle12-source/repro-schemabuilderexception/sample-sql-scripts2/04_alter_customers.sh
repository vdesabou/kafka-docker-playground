#!/bin/sh

echo 'Altering CUSTOMERS2 table with an optional column'

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/$1 << EOF
  alter table CUSTOMERS2 add (
    country VARCHAR(50)
  );
  exit;
EOF
