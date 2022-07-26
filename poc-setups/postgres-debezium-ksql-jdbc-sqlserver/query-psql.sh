#!/bin/bash
set -e
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM CUSTOMERS'"