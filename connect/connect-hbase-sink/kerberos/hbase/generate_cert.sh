#!/bin/bash

ALIAS=$(hostname -f)
PASS=bigdata

keytool -genkey \
	-keyalg RSA \
	-alias $ALIAS \
	-keystore keystore.jks \
	-storepass $PASS \
	-keypass $PASS \
	-validity 3600 \
	-dname "CN=${PASS},OU=hackolade,O=hackolade,L=Lviv,C=US"
