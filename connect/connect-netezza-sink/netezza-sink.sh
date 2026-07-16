#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.0.6"
then
     logwarn "minimal supported connector version is 1.0.7 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

# IBM Netezza (NPS) has no server docker image, so this test runs against an
# EXTERNAL, already-provisioned instance (NPS-as-a-Service or the Netezza
# emulator VM). Provide the connection details through environment variables.
if [ -z "$NETEZZA_HOST" ]
then
     logerror "NETEZZA_HOST is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$NETEZZA_USER" ]
then
     logerror "NETEZZA_USER is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$NETEZZA_PASSWORD" ]
then
     logerror "NETEZZA_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

NETEZZA_PORT=${NETEZZA_PORT:-5480}
NETEZZA_DB=${NETEZZA_DB:-SYSTEMTEST}

# Neither the Netezza JDBC driver (nzjdbc3.jar) nor the native SQL client (nzsql)
# are bundled with the connector, and IBM does not publish them at a public URL -
# they ship with the NPS Linux client tools. The full client tarball is hosted on
# the Confluent S3 bucket (Confluent employees only), so get_3rdparty_file fetches
# it automatically. Everything lives in the git-ignored nzclient/ folder (the
# tarball is cached there, and the client is extracted in place next to it).
# From it we get BOTH the JDBC driver (copied into the connector lib) and nzsql
# (mounted into the connect container to run SQL, the way connect-jdbc-vertica-sink
# uses vsql) - so we no longer need a PostgreSQL client stand-in.
NZ_CLIENT_TAR="nps-linuxclient-v11.3.1.2.tar.gz"
NZ_CLIENT_DIR="${DIR}/nzclient"
# The S3 tarball is an installer bundle: unpacking it yields an inner client
# tarball (linux64/npsclient.11.3.1.2.tar.gz) which in turn holds the actual
# bin64/, lib64/, ... tree with nzsql and nzjdbc3.jar. So there are two unpacks.
NZ_INNER_TAR="${NZ_CLIENT_DIR}/linux64/npsclient.11.3.1.2.tar.gz"
NZ_HOME="${NZ_CLIENT_DIR}/npsclient"   # where the inner tarball is unpacked

# get_3rdparty_file downloads into the current directory, so cd into nzclient/
# first (it also skips the download if the tarball is already there).
mkdir -p "${NZ_CLIENT_DIR}"
cd "${NZ_CLIENT_DIR}"
get_3rdparty_file "${NZ_CLIENT_TAR}"
cd -

if [ ! -f "${NZ_CLIENT_DIR}/${NZ_CLIENT_TAR}" ]
then
     logerror "❌ ${NZ_CLIENT_TAR} not found in ${NZ_CLIENT_DIR}"
     logerror "   It could not be downloaded from the Confluent S3 bucket (Confluent employees"
     logerror "   need valid AWS credentials set). Otherwise obtain the NPS Linux client tarball"
     logerror "   from your Netezza client tools distribution and copy it here as"
     logerror "   nzclient/${NZ_CLIENT_TAR}."
     exit 1
fi

# First unpack: extract the installer bundle to get the inner client tarball
if [ ! -f "${NZ_INNER_TAR}" ]
then
     log "Extracting NPS Linux client bundle from ${NZ_CLIENT_TAR}"
     tar xzf "${NZ_CLIENT_DIR}/${NZ_CLIENT_TAR}" -C "${NZ_CLIENT_DIR}"
fi

# Second unpack: extract the client tree (bin64/, lib64/, ...) into npsclient/
if [ ! -d "${NZ_HOME}" ]
then
     log "Unpacking NPS client (nzsql + nzjdbc3.jar)"
     mkdir -p "${NZ_HOME}"
     tar xzf "${NZ_INNER_TAR}" -C "${NZ_HOME}"
fi

# The JDBC driver and nzsql live at fixed paths inside the unpacked client tree.
NZJDBC_JAR_HOST="${NZ_HOME}/lib64/nzjdbc3.jar"
NZSQL_HOST="${NZ_HOME}/bin64/nz/nzsql"
if [ ! -f "${NZJDBC_JAR_HOST}" ] || [ ! -f "${NZSQL_HOST}" ]
then
     logerror "❌ nzjdbc3.jar and/or nzsql not found under ${NZ_HOME}"
     logerror "   The extracted contents of ${NZ_CLIENT_TAR} do not match the expected NPS client layout."
     exit 1
fi

# Copy the JDBC driver into the connector's lib dir. The connector was installed
# into ../../confluent-hub/confluentinc-kafka-connect-netezza when this script
# sourced utils.sh; that folder is mounted into the connect container at
# /usr/share/confluent-hub-components and used as CONNECT_PLUGIN_PATH.
NETEZZA_PLUGIN_LIB_DIR="${DIR}/../../confluent-hub/confluentinc-kafka-connect-netezza/lib"
mkdir -p "${NETEZZA_PLUGIN_LIB_DIR}"
cp "${NZJDBC_JAR_HOST}" "${NETEZZA_PLUGIN_LIB_DIR}/nzjdbc3.jar"

# nzsql is a Linux x86_64 binary. This host / the connect container is arm64
# (Apple Silicon), where an x86_64 binary cannot run - so we run our downloaded
# nzsql in a separate throwaway amd64 container (--platform=linux/amd64, qemu
# emulation). This is the same pattern connect-azure-functions-sink uses to run a
# tool in an amd64 base-image container. We use debian:bullseye-slim as the base
# because nzsql needs libnsl.so.2 (provided by debian, but NOT by the connect
# image). The nzclient/ tree is mounted at /opt/nz; nzsql gets its own bundled
# libs via LD_LIBRARY_PATH and the port via NZ_DBMS_PORT, and SQL is piped in on
# stdin.
NZSQL_IMAGE="debian:bullseye-slim"
NZ_HOME_CONTAINER="/opt/nz/npsclient"
NZSQL_CONTAINER="${NZ_HOME_CONTAINER}/bin64/nz/nzsql"

run_nzsql () {
     docker run --rm -i --platform=linux/amd64 \
          --entrypoint "${NZSQL_CONTAINER}" \
          -v "${NZ_CLIENT_DIR}:/opt/nz" \
          -e LD_LIBRARY_PATH="${NZ_HOME_CONTAINER}/lib64" \
          -e NZ_DBMS_PORT="${NETEZZA_PORT}" \
          "${NZSQL_IMAGE}" \
          -host "${NETEZZA_HOST}" -u "${NETEZZA_USER}" -pw "${NETEZZA_PASSWORD}" -d "${NETEZZA_DB}"
}

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Drop table orders in Netezza, if it exists"
set +e
run_nzsql << EOF
DROP TABLE orders;
EOF
set -e

log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 1 --forced-value '{"id":2,"product":"foo","quantity":2,"price":0.86583304}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ]
}
EOF

log "Creating Netezza sink connector"
playground connector create-or-update --connector netezza-sink  << EOF
{
  "connector.class": "io.confluent.connect.netezza.NetezzaSinkConnector",
  "tasks.max": "1",
  "connection.host": "${NETEZZA_HOST}",
  "connection.port": "${NETEZZA_PORT}",
  "connection.database": "${NETEZZA_DB}",
  "connection.user": "${NETEZZA_USER}",
  "connection.password": "${NETEZZA_PASSWORD}",
  "topics": "orders",
  "auto.create": "true"
}
EOF

sleep 15

log "Verify data is in Netezza"
run_nzsql > /tmp/result.log 2>&1 << EOF
SELECT * FROM orders;
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log

log "Drop table orders in Netezza (cleanup)"
run_nzsql << EOF
DROP TABLE orders;
EOF
