#!/bin/sh

echo 'Altering CUSTOMERS table with an optional column'

docker exec -i oracle bash -c "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe && /u01/app/oracle/product/11.2.0/xe/bin/sqlplus MYUSER/password@//localhost:1521/XE" << EOF
  alter table CUSTOMERS add (
    country VARCHAR(50)
  );
  exit;
EOF
