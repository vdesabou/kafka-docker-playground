#!/bin/bash

set -o nounset \
    -o errexit \
    -o verbose

# See what is in each keystore and truststore
for i in kafka client schema-registry restproxy connect control-center
do
        echo -e "\033[0;33m------------------------------- $i keystore -------------------------------\033[0m"
	keytool -list -v -keystore kafka.$i.keystore.jks -storepass confluent | grep -e Alias -e Entry
        echo -e "\033[0;33m------------------------------- $i truststore -------------------------------\033[0m"
	keytool -list -v -keystore kafka.$i.truststore.jks -storepass confluent | grep -e Alias -e Entry
done
