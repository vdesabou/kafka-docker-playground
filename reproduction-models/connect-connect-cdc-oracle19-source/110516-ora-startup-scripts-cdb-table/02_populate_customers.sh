#!/bin/sh

echo 'Populating CUSTOMERS table'

sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB  <<- EOF

insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, mydate) values (1, 'Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy', TO_DATE('2022-06-18
02:21:18', 'YYYY-MM-DD HH24:MI:SS'));
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, mydate) values (2, 'Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface', TO_DATE('2022-06-18
02:21:18', 'YYYY-MM-DD HH24:MI:SS'));
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, mydate) values (3, 'Mariejeanne', 'Cocci', 'mcocci2@techcrunch.com', 'Female', 'bronze', 'Multi-tiered bandwidth-monitored capability', TO_DATE('2022-06-18
02:21:18', 'YYYY-MM-DD HH24:MI:SS'));
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, mydate) values (4, 'Hashim', 'Rumke', 'hrumke3@sohu.com', 'Male', 'platinum', 'Self-enabling 24/7 firmware', TO_DATE('2022-06-18
02:21:18', 'YYYY-MM-DD HH24:MI:SS'));
insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, mydate) values (5, 'Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach', TO_DATE('2022-06-18
02:21:18', 'YYYY-MM-DD HH24:MI:SS'));

  exit;
EOF
