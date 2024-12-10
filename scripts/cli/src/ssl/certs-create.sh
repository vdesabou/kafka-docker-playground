#!/bin/bash

# Split the argument into an array
IFS=' ' read -r -a containers <<< "$1"
new_open_ssl=$2

if [[ $new_open_ssl -eq 1 ]]
then
    maybe_provider="-provider base"
    maybe_nomacver="-nomacver"
    maybe_nomac="--nomac"
else
    maybe_provider=""
    maybe_nomacver=""
    maybe_nomac=""
fi

# Cleanup files
rm -f /tmp/*.crt /tmp/*.csr /tmp/*_creds /tmp/*.jks /tmp/*.srl /tmp/*.key /tmp/*.pem /tmp/*.der /tmp/*.p12 /tmp/extfile

# Generate CA key
openssl req -new -x509 -keyout /tmp/snakeoil-ca-1.key -out /tmp/snakeoil-ca-1.crt -days 365 -subj '/CN=ca1.test.confluent.io/OU=TEST/O=CONFLUENT/L=PaloAlto/ST=Ca/C=US' -passin pass:confluent -passout pass:confluent $maybe_provider

for container in "${containers[@]}"
do
    # Create host keystore
    keytool -genkey -noprompt \
        -alias ${container} \
        -dname "CN=${container},OU=TEST,O=CONFLUENT,L=PaloAlto,S=Ca,C=US" \
        -ext "SAN=dns:${container},dns:localhost" \
        -keystore /tmp/kafka.${container}.keystore.jks \
        -keyalg RSA \
        -storepass confluent \
        -keypass confluent \
        -storetype pkcs12

    # Create the certificate signing request (CSR)
    keytool -keystore /tmp/kafka.${container}.keystore.jks -alias ${container} -certreq -file /tmp/${container}.csr -storepass confluent -keypass confluent -ext "SAN=dns:${container},dns:localhost"
    #openssl req -in ${container}.csr -text -noout

cat << EOF > /tmp/extfile
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = ${container}
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${container}
DNS.2 = localhost
EOF
    # Sign the host certificate with the certificate authority (CA)
    openssl x509 -req -CA /tmp/snakeoil-ca-1.crt -CAkey /tmp/snakeoil-ca-1.key -in /tmp/${container}.csr -out /tmp/${container}-ca1-signed.crt -days 9999 -CAcreateserial -passin pass:confluent -extensions v3_req -extfile /tmp/extfile $maybe_provider

    # Sign and import the CA cert into the keystore
    keytool -noprompt -keystore /tmp/kafka.${container}.keystore.jks -alias CARoot -import -file /tmp/snakeoil-ca-1.crt -storepass confluent -keypass confluent

    # Sign and import the host certificate into the keystore
    keytool -noprompt -keystore /tmp/kafka.${container}.keystore.jks -alias ${container} -import -file /tmp/${container}-ca1-signed.crt -storepass confluent -keypass confluent -ext "SAN=dns:${container},dns:localhost"

    # Create truststore and import the CA cert
    keytool -noprompt -keystore /tmp/kafka.${container}.truststore.jks -alias CARoot -import -file /tmp/snakeoil-ca-1.crt -storepass confluent -keypass confluent

    # Save creds
    echo  "confluent" > /tmp/${container}_sslkey_creds
    echo  "confluent" > /tmp/${container}_keystore_creds
    echo  "confluent" > /tmp/${container}_truststore_creds

    # Create pem files and keys used for Schema Registry HTTPS testing
    keytool -export -alias ${container} -file /tmp/${container}.der -keystore /tmp/kafka.${container}.keystore.jks -storepass confluent
    openssl x509 -inform der -in /tmp/${container}.der -out /tmp/${container}.certificate.pem $maybe_provider
    keytool -importkeystore -srckeystore /tmp/kafka.${container}.keystore.jks -destkeystore /tmp/${container}.keystore.p12 -deststoretype PKCS12 -deststorepass confluent -srcstorepass confluent -noprompt
    openssl pkcs12 -in /tmp/${container}.keystore.p12 -nodes -nocerts -out /tmp/${container}.key -passin pass:confluent $maybe_provider $maybe_nomacver


    cacerts_path="$(readlink -f /usr/bin/java | sed "s:bin/java::")lib/security/cacerts"
    keytool -noprompt -destkeystore /tmp/kafka.${container}.truststore.jks -importkeystore -srckeystore $cacerts_path -srcstorepass changeit -deststorepass confluent

    if [ "${container}" == "clientrestproxy" ]
    then
        # used for other/rest-proxy-security-plugin test
        # https://stackoverflow.com/a/8224863
        openssl pkcs12 -export -in /tmp/clientrestproxy-ca1-signed.crt -inkey /tmp/clientrestproxy.key \
            -out /tmp/clientrestproxy.p12 -name clientrestproxy \
            -CAfile /tmp/snakeoil-ca-1.crt -caname CARoot -passout pass:confluent $maybe_provider $maybe_nomac

        keytool -importkeystore \
                -deststorepass confluent -destkeypass confluent -destkeystore /tmp/kafka.restproxy.keystore.jks \
                -srckeystore /tmp/clientrestproxy.p12 -srcstoretype PKCS12 -srcstorepass confluent \
                -alias clientrestproxy
    fi
done

