#!/bin/sh

echo 'Populating CUSTOMERS table'

sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB  <<- EOF

insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments, TATXA1, TAITM, TAEFDJ) values ('Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy', 'TATXA1', 2, 3);

  exit;
EOF
