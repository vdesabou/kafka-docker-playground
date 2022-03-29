#!/bin/sh

echo 'Populating CUSTOMERS table'

sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB  <<- EOF

insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (1, 'Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', utl_raw.cast_to_raw('Universal optimal hierarchy'));

  exit;
EOF
