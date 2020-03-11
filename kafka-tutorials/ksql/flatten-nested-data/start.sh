#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../../scripts/utils.sh
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d

log "Create the input topic with a stream"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

CREATE STREAM ORDERS (
    id VARCHAR,
    timestamp VARCHAR,
    amount DOUBLE,
    customer STRUCT<firstName VARCHAR,
                    lastName VARCHAR,
                    phoneNumber VARCHAR,
                    address STRUCT<street VARCHAR,
                                   number VARCHAR,
                                   zipcode VARCHAR,
                                   city VARCHAR,
                                   state VARCHAR>>,
    product STRUCT<sku VARCHAR,
                   name VARCHAR,
                   vendor STRUCT<vendorName VARCHAR,
                                 country VARCHAR>>)
    WITH (KAFKA_TOPIC = 'ORDERS',
          VALUE_FORMAT = 'JSON',
          TIMESTAMP = 'TIMESTAMP',
          TIMESTAMP_FORMAT = 'yyyy-MM-dd HH:mm:ss',
          PARTITIONS = 1, REPLICAS = 1);

EOF

log "Produce events to the input topic"
docker exec -i broker /usr/bin/kafka-console-producer --topic ORDERS --broker-list broker:9092 << EOF
{"id": "1", "timestamp": "2020-01-18 01:12:05", "amount": 84.02, "customer": {"firstName": "Ricardo", "lastName": "Ferreira", "phoneNumber": "1234567899", "address": {"street": "Street SDF", "number": "8602", "zipcode": "27640", "city": "Raleigh", "state": "NC"}}, "product": {"sku": "P12345", "name": "Highly Durable Glue", "vendor": {"vendorName": "Acme Corp", "country": "US"}}}
{"id": "2", "timestamp": "2020-01-18 01:35:12", "amount": 84.02, "customer": {"firstName": "Tim", "lastName": "Berglund", "phoneNumber": "9987654321", "address": {"street": "Street UOI", "number": "1124", "zipcode": "85756", "city": "Littletown", "state": "CO"}}, "product": {"sku": "P12345", "name": "Highly Durable Glue", "vendor": {"vendorName": "Acme Corp", "country": "US"}}}
{"id": "3", "timestamp": "2020-01-18 01:58:55", "amount": 84.02, "customer": {"firstName": "Robin", "lastName": "Moffatt", "phoneNumber": "4412356789", "address": {"street": "Street YUP", "number": "9066", "zipcode": "BD111NE", "city": "Leeds", "state": "YS"}}, "product": {"sku": "P12345", "name": "Highly Durable Glue", "vendor": {"vendorName": "Acme Corp", "country": "US"}}}
{"id": "4", "timestamp": "2020-01-18 02:31:43", "amount": 84.02, "customer": {"firstName": "Viktor", "lastName": "Gamov", "phoneNumber": "9874563210", "address": {"street": "Street SHT", "number": "12450", "zipcode": "07003", "city": "New Jersey", "state": "NJ"}}, "product": {"sku": "P12345", "name": "Highly Durable Glue", "vendor": {"vendorName": "Acme Corp", "country": "US"}}}
EOF


log "Invoke manual steps"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

SELECT
    ID AS ORDER_ID,
    TIMESTAMP AS ORDER_TS,
    AMOUNT AS ORDER_AMOUNT,
    CUSTOMER->FIRSTNAME AS CUST_FIRST_NAME,
    CUSTOMER->LASTNAME AS CUST_LAST_NAME,
    CUSTOMER->PHONENUMBER AS CUST_PHONE_NUMBER,
    CUSTOMER->ADDRESS->STREET AS CUST_ADDR_STREET,
    CUSTOMER->ADDRESS->NUMBER AS CUST_ADDR_NUMBER,
    CUSTOMER->ADDRESS->ZIPCODE AS CUST_ADDR_ZIPCODE,
    CUSTOMER->ADDRESS->CITY AS CUST_ADDR_CITY,
    CUSTOMER->ADDRESS->STATE AS CUST_ADDR_STATE,
    PRODUCT->SKU AS PROD_SKU,
    PRODUCT->NAME AS PROD_NAME,
    PRODUCT->VENDOR->VENDORNAME AS PROD_VENDOR_NAME,
    PRODUCT->VENDOR->COUNTRY AS PROD_VENDOR_COUNTRY
FROM
    ORDERS
EMIT CHANGES
LIMIT 4;


CREATE STREAM FLATTENED_ORDERS AS
    SELECT
        ID AS ORDER_ID,
        TIMESTAMP AS ORDER_TS,
        AMOUNT AS ORDER_AMOUNT,
        CUSTOMER->FIRSTNAME AS CUST_FIRST_NAME,
        CUSTOMER->LASTNAME AS CUST_LAST_NAME,
        CUSTOMER->PHONENUMBER AS CUST_PHONE_NUMBER,
        CUSTOMER->ADDRESS->STREET AS CUST_ADDR_STREET,
        CUSTOMER->ADDRESS->NUMBER AS CUST_ADDR_NUMBER,
        CUSTOMER->ADDRESS->ZIPCODE AS CUST_ADDR_ZIPCODE,
        CUSTOMER->ADDRESS->CITY AS CUST_ADDR_CITY,
        CUSTOMER->ADDRESS->STATE AS CUST_ADDR_STATE,
        PRODUCT->SKU AS PROD_SKU,
        PRODUCT->NAME AS PROD_NAME,
        PRODUCT->VENDOR->VENDORNAME AS PROD_VENDOR_NAME,
        PRODUCT->VENDOR->COUNTRY AS PROD_VENDOR_COUNTRY
    FROM
        ORDERS
    PARTITION BY ID;

SELECT
    ORDER_ID,
    ORDER_TS,
    ORDER_AMOUNT,
    CUST_FIRST_NAME,
    CUST_LAST_NAME,
    CUST_PHONE_NUMBER,
    CUST_ADDR_STREET,
    CUST_ADDR_NUMBER,
    CUST_ADDR_ZIPCODE,
    CUST_ADDR_CITY,
    CUST_ADDR_STATE,
    PROD_SKU,
    PROD_NAME,
    PROD_VENDOR_NAME,
    PROD_VENDOR_COUNTRY
FROM FLATTENED_ORDERS
EMIT CHANGES
LIMIT 4;

PRINT FLATTENED_ORDERS FROM BEGINNING LIMIT 4;
EOF


log "Invoke the tests"
docker exec ksqldb-cli ksql-test-runner -i /opt/app/test/input.json -s opt/app/src/statements.sql -o /opt/app/test/output.json | grep "Test passed!"