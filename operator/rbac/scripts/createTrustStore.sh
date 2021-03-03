#!/bin/bash
set -e

pem=$1
[[ $# -ne 1 ]] && {
	echo "Usage: $0 CA_pem_file_to_add_in_truststore or Fullchain_pem_file";
	echo -e "\tCA_pem_file_to_add_in_truststore: CA certificate";
        echo -e "\tFullchain_pem_file: Includes CA & Certificate of server or client to trust";
        exit 1;
}

if [[ -e /tmp/truststore.jks ]];then
  rm /tmp/truststore.jks
fi
rm -rf /tmp/trustCAs
mkdir /tmp/trustCAs
cat ${pem} | awk 'split_after==1{n++;split_after=0} /-----END CERTIFICATE-----/ {split_after=1} {print > ("/tmp/trustCAs/ca" n ".pem")}'
for file in /tmp/trustCAs/*; do
  fileName="${file##*/}"
  keytool -import \
        -trustcacerts \
        -alias ${fileName} \
        -file ${file} \
	-keystore /tmp/truststore.jks \
	-deststorepass mystorepassword \
  -deststoretype pkcs12 \
	-noprompt
done
echo "validate CA certs"
keytool -list -v -keystore /tmp/truststore.jks -storepass mystorepassword
echo -e "\n"
echo "ssl.truststore.location=/tmp/truststore.jks"
echo "ssl.truststore.password=mystorepassword"
