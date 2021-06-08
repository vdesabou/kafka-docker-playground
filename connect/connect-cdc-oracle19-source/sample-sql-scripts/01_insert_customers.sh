#!/bin/sh

echo "Populating CUSTOMERS table"

docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/$1 << EOF
  insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Frantz', 'Kafka', 'fkafka@confluent.io', 'Male', 'bronze', 'Evil is whatever distracts');
  insert into CUSTOMERS (first_name, last_name, email, gender, club_status, comments) values ('Gregor', 'Samsa', 'gsamsa@confluent.io', 'Male', 'platinium', 'How about if I sleep a little bit longer and forget all this nonsense');
  exit;
EOF