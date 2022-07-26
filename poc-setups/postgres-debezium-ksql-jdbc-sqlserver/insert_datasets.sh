#!/bin/bash
set -e

for i in $(seq 21 30); do
  docker exec postgres psql -U myuser -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments) values ($i, 'Test', 'Testman', 'ttestman@test.io', 'Male', 'Blablablabla $i');"
done
