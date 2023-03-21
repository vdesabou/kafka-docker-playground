#!/bin/sh

echo 'Deleting CUSTOMERS with email=fkafka@confluent.io'

docker exec -i oracle bash -c "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe && /u01/app/oracle/product/11.2.0/xe/bin/sqlplus MYUSER/password@//localhost:1521/XE" << EOF
  delete from CUSTOMERS where email = 'fkafka@confluent.io';
  exit;
EOF
