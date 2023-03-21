#!/bin/sh

echo 'Populating CUSTOMERS table after altering the structure'

docker exec -i oracle bash -c "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe && /u01/app/oracle/product/11.2.0/xe/bin/sqlplus MYUSER/password@//localhost:1521/XE" << EOF
  update CUSTOMERS set club_status = 'gold' where email = 'gsamsa@confluent.io';
  update CUSTOMERS set club_status = 'gold' where email = 'jk@confluent.io';
  commit;
  exit;
EOF
