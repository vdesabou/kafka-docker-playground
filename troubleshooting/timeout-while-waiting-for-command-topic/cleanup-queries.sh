#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# https://rmoff.net/2019/03/25/terminate-all-ksql-queries/
log "TERMINATE all queries, if applicable"
curl -s -X "POST" "http://localhost:8088/ksql" \
         -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
         -d '{"ksql": "SHOW QUERIES;"}' | \
  jq '.[].queries[].id' | \
  xargs -Ifoo curl -s -X "POST" "http://localhost:8088/ksql" \
           -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
           -d '{"ksql": "TERMINATE 'foo';"}' | jq . > /tmp/out.txt 2>&1

if [[ $(cat /tmp/out.txt) =~ "statement_error" ]]
then
    logerror "Cannot terminate all queries, check the errors below:"
    cat /tmp/out.txt
    exit 1
fi
log "DROP all streams, if applicable"
curl -s -X "POST" "http://localhost:8088/ksql" \
           -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
           -d '{"ksql": "SHOW STREAMS;"}' | \
    jq '.[].streams[].name' | \
    xargs -Ifoo curl -s -X "POST" "http://localhost:8088/ksql" \
             -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
             -d '{"ksql": "DROP STREAM 'foo';"}' | jq . > /tmp/out.txt 2>&1
if [[ $(cat /tmp/out.txt) =~ "statement_error" ]]
then
    logerror "Cannot drop all streams, check the errors below:"
    cat /tmp/out.txt
    exit 1
fi
log "DROP all tables, if applicable"
curl -s -X "POST" "http://localhost:8088/ksql" \
             -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
             -d '{"ksql": "SHOW TABLES;"}' | \
      jq '.[].tables[].name' | \
      xargs -Ifoo curl -s -X "POST" "http://localhost:8088/ksql" \
               -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
               -d '{"ksql": "DROP TABLE 'foo';"}' | jq . > /tmp/out.txt 2>&1
if [[ $(cat /tmp/out.txt) =~ "statement_error" ]]
then
    logerror "Cannot drop all tables, check the errors below:"
    cat /tmp/out.txt
    exit 1
fi
