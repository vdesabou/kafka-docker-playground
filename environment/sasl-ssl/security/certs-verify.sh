#!/bin/bash

set -o nounset \
    -o errexit \
    -o verbose

# See what is in each keystore and truststore
for i in broker broker2 client schema-registry restproxy connect control-center clientrestproxy
do
        log "------------------------------- $i keystore -------------------------------"
	keytool -list -v -keystore kafka.$i.keystore.jks -storepass confluent | grep -e Alias -e Entry
        log "------------------------------- $i truststore -------------------------------"
	keytool -list -v -keystore kafka.$i.truststore.jks -storepass confluent | grep -e Alias -e Entry
done
