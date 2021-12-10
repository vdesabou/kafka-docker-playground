#!/bin/bash

set -o nounset \
    -o errexit \
    -o verbose

# See what is in each keystore and truststore
for i in zookeeper1 broker1 broker2 broker3 schema-registry rest-proxy connect control-center ksql-server
do
        echo "------------------------------- $i keystore -------------------------------"
        keytool -list -v -keystore /tmp/kafka.$i.keystore.jks -storepass confluent | grep -e Alias -e Entry
        echo "------------------------------- $i truststore -------------------------------"
        keytool -list -v -keystore /tmp/kafka.$i.truststore.jks -storepass confluent | grep -e Alias -e Entry
done
