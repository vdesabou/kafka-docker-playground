#!/bin/bash
# run by mtls-principal-mapping.sh in the connect image, like 'playground tools cert create':
#   /ca  = environment/2way-ssl/security (the CA of the environment, read only)
#   /out = other/mtls-principal-mapping/security
# creates /out/kafka.<name>.keystore.jks (password confluent): a key pair for the distinguished name $2, signed by
# the CA of the environment, so that the broker trusts it
set -e
set -o pipefail

name="$1"
dname="$2"
maybe_provider=""
if openssl version | grep -q "OpenSSL 3"
then
    maybe_provider="-provider base"
fi

rm -f "/out/kafka.${name}.keystore.jks" "/out/${name}.csr" "/out/${name}-ca1-signed.crt"

keytool -genkey -noprompt -alias "${name}" -dname "${dname}" -keystore "/out/kafka.${name}.keystore.jks" \
    -keyalg RSA -keysize 2048 -storepass confluent -keypass confluent -storetype pkcs12
keytool -keystore "/out/kafka.${name}.keystore.jks" -alias "${name}" -certreq -file "/out/${name}.csr" \
    -storepass confluent -keypass confluent
# the CA key stays in /ca: openssl writes its serial file next to the certificate it signs
openssl x509 -req -CA /ca/snakeoil-ca-1.crt -CAkey /ca/snakeoil-ca-1.key -in "/out/${name}.csr" \
    -out "/out/${name}-ca1-signed.crt" -days 365 -CAcreateserial -CAserial /out/ca.srl -passin pass:confluent $maybe_provider
keytool -noprompt -keystore "/out/kafka.${name}.keystore.jks" -alias CARoot -import -file /ca/snakeoil-ca-1.crt \
    -storepass confluent -keypass confluent
keytool -noprompt -keystore "/out/kafka.${name}.keystore.jks" -alias "${name}" -import -file "/out/${name}-ca1-signed.crt" \
    -storepass confluent -keypass confluent
rm -f "/out/${name}.csr" /out/ca.srl
