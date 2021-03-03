#!/bin/bash
set -e

server=$1
serverKey=$2
[ $# -ne 2 ] && { echo "Usage: $0 fullchain_pem_file private_key"; exit 1; }

if [ -e /tmp/keystore.jks ];then
  rm /tmp/keystore.jks
fi
rm -rf /tmp/trustCAs
mkdir /tmp/trustCAs


echo "Check $server certificate"
openssl x509 -in $server -text -noout


openssl pkcs12 -export \
	-in ${server} \
	-inkey ${serverKey} \
	-out /tmp/pkcs.p12 \
	-name testService \
	-passout pass:mykeypassword

keytool -importkeystore \
	-deststorepass mystorepassword \
	-destkeypass mystorepassword \
	-destkeystore /tmp/keystore.jks \
	-deststoretype pkcs12 \
	-srckeystore /tmp/pkcs.p12 \
	-srcstoretype PKCS12 \
	-srcstorepass mykeypassword

echo "Validate Server Certificate from Keytool"
keytool -list -v -keystore /tmp/keystore.jks -storepass mystorepassword
echo -e "\n"
echo "ssl.keystore.location=/tmp/keystore.jks"
echo "ssl.keystore.password=mystorepassword"
echo "ssl.key.password=mykeypassword"
