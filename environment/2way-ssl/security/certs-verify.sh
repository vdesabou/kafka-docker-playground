#!/bin/bash

set -o nounset \
    -o errexit \
    -o verbose

# See what is in each keystore and truststore
for i in broker broker2 client schema-registry restproxy connect control-center clientrestproxy
do
        echo "------------------------------- $i keystore -------------------------------"
	docker run -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${TAG} keytool -list -v -keystore /tmp/kafka.$i.keystore.jks -storepass confluent | grep -e Alias -e Entry
        echo "------------------------------- $i truststore -------------------------------"
	docker run -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${TAG} keytool -list -v -keystore /tmp/kafka.$i.truststore.jks -storepass confluent | grep -e Alias -e Entry
done
