#!/bin/sh

# Update Oracle 19c to not include ALTER TABLE ADD #1109
# https://github.com/vdesabou/kafka-docker-playground/issues/1109

echo 'Altering CUSTOMERS table with an optional column'

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/$1 << EOF
  EXECUTE DBMS_LOGMNR_D.BUILD(OPTIONS=>DBMS_LOGMNR_D.STORE_IN_REDO_LOGS);
  alter table CUSTOMERS add (
    country VARCHAR(50)
  );
  EXECUTE DBMS_LOGMNR_D.BUILD(OPTIONS=>DBMS_LOGMNR_D.STORE_IN_REDO_LOGS);
  exit;
EOF
