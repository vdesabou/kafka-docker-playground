#!/bin/bash

SSL_PASSWORD="1a2b3c"
KEYSTORE_FILE=keystore.jks
TRUSTTORE_FILE=truststore.jks
ALIASNAME="$(hostname -f)"

mkdir -p ./certs/
rm -f ./certs/*
cd ./certs

keytool -genkey -noprompt \
	-alias $ALIASNAME \
	-dname "CN=$ALIASNAME, OU=, O=lenchv, L=, S=, C=" \
	-keyalg RSA \
	-keystore $KEYSTORE_FILE \
	-keysize 2048 \
	-storepass $SSL_PASSWORD \
 	-keypass $SSL_PASSWORD
keytool -export -alias $ALIASNAME -file ssl.crt -keystore $KEYSTORE_FILE -storepass $SSL_PASSWORD -noprompt;
keytool -import -trustcacerts -alias $ALIASNAME -file ssl.crt -keystore $TRUSTTORE_FILE -storepass $SSL_PASSWORD -noprompt;

keytool -importkeystore \
	-srckeystore $KEYSTORE_FILE \
	-destkeystore ${ALIASNAME}.p12 \
	-srcalias $ALIASNAME \
	-srcstoretype jks \
	-deststoretype pkcs12 \
	-srcstorepass $SSL_PASSWORD \
	-deststorepass $SSL_PASSWORD;

keytool -importkeystore \
	-srckeystore $TRUSTTORE_FILE \
	-destkeystore ${ALIASNAME}_trust.p12 \
	-srcalias $ALIASNAME \
	-srcstoretype jks \
	-deststoretype pkcs12 \
	-srcstorepass $SSL_PASSWORD \
	-deststorepass $SSL_PASSWORD;

openssl pkcs12 -in ${ALIASNAME}.p12 -nokeys -out cert.pem -passin pass:$SSL_PASSWORD;
openssl pkcs12 -in ${ALIASNAME}_trust.p12 -nokeys -out ca.pem -passin pass:$SSL_PASSWORD;
openssl pkcs12 -in ${ALIASNAME}.p12 -nodes -nocerts -out key.key -passin pass:$SSL_PASSWORD;

mv ./ca.pem ./certs/
mv ./ssl.crt ./certs/
mv ./truststore.jks ./certs/
mv ./cert.pem ./certs/
mv ./key.key ./certs/
mv ./${ALIASNAME}.p12 ./certs/
mv ./keystore.jks ./certs/
mv ./${ALIASNAME}_trust.p12 ./certs/

