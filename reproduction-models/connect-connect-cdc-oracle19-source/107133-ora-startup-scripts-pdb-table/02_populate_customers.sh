#!/bin/sh

echo 'Populating CUSTOMERS table'

sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1  <<- EOF

insert into CUSTOMERS (RECID, XMLRECORD) values ('1',XMLType('<Warehouse whNo="1"> <Building>Owned</Building></Warehouse>'));
insert into CUSTOMERS (RECID, XMLRECORD) values ('2',XMLType('<Warehouse whNo="2"> <Building>Owned</Building></Warehouse>'));

  exit;
EOF
