#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

SERVICENOW_URL=${SERVICENOW_URL:-$1}
SERVICENOW_PASSWORD=${SERVICENOW_PASSWORD:-$2}

if [ -z "$SERVICENOW_URL" ]
then
     logerror "SERVICENOW_URL is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [[ "$SERVICENOW_URL" != */ ]]
then
    logerror "SERVICENOW_URL does not end with "/" Example: https://dev12345.service-now.com/ "
    exit 1
fi

if [ -z "$SERVICENOW_PASSWORD" ]
then
     logerror "SERVICENOW_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-repro-proxy.yml"

export HTTP_PROXY=127.0.0.1:8888
export HTTPS_PROXY=127.0.0.1:8888
log "Verify forward proxy is working correctly"
curl -v ${SERVICENOW_URL}api/now/table/incident?sysparm_limit=1 -u "admin:$SERVICENOW_PASSWORD" | jq .

# * Uses proxy env variable HTTPS_PROXY == '127.0.0.1:8888'
# *   Trying 127.0.0.1...
# * TCP_NODELAY set
# * Connected to 127.0.0.1 (127.0.0.1) port 8888 (#0)
# * allocate connect buffer!
# * Establish HTTP proxy tunnel to dev86373.service-now.com:443
# > CONNECT dev86373.service-now.com:443 HTTP/1.1
# > Host: dev86373.service-now.com:443
# > User-Agent: curl/7.64.1
# > Proxy-Connection: Keep-Alive
# >
# < HTTP/1.1 200 Connection Established
# < Proxy-agent: nginx
# <
# * Proxy replied 200 to CONNECT request
# * CONNECT phase completed!
# * ALPN, offering h2
# * ALPN, offering http/1.1
# * successfully set certificate verify locations:
# *   CAfile: /etc/ssl/cert.pem
#   CApath: none
# * TLSv1.2 (OUT), TLS handshake, Client hello (1):
# * CONNECT phase completed!
# * CONNECT phase completed!
# * TLSv1.2 (IN), TLS handshake, Server hello (2):
# * TLSv1.2 (IN), TLS handshake, Certificate (11):
# * TLSv1.2 (IN), TLS handshake, Server key exchange (12):
# * TLSv1.2 (IN), TLS handshake, Server finished (14):
# * TLSv1.2 (OUT), TLS handshake, Client key exchange (16):
# * TLSv1.2 (OUT), TLS change cipher, Change cipher spec (1):
# * TLSv1.2 (OUT), TLS handshake, Finished (20):
# * TLSv1.2 (IN), TLS change cipher, Change cipher spec (1):
# * TLSv1.2 (IN), TLS handshake, Finished (20):
# * SSL connection using TLSv1.2 / ECDHE-RSA-AES128-GCM-SHA256
# * ALPN, server did not agree to a protocol
# * Server certificate:
# *  subject: C=US; ST=California; L=San Diego; O=ServiceNow, Inc.; CN=*.service-now.com
# *  start date: Jul 22 23:55:53 2020 GMT
# *  expire date: Apr  1 23:55:53 2021 GMT
# *  subjectAltName: host "dev86373.service-now.com" matched cert's "*.service-now.com"
# *  issuer: C=US; O=Entrust, Inc.; OU=See www.entrust.net/legal-terms; OU=(c) 2012 Entrust, Inc. - for authorized use only; CN=Entrust Certification Authority - L1K
# *  SSL certificate verify ok.
# > GET /api/now/table/incident?sysparm_limit=1 HTTP/1.1
# > Host: dev86373.service-now.com
# > User-Agent: curl/7.64.1
# > Accept: */*
# >
# < HTTP/1.1 401 Unauthorized
# < Set-Cookie: JSESSIONID=4C37481E1E5C3C37AEF09AD9442887DF; Path=/; HttpOnly;Secure
# < Set-Cookie: glide_user=; Max-Age=0; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/; HttpOnly;Secure
# < Set-Cookie: glide_user_session=; Max-Age=0; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/; HttpOnly;Secure
# < WWW-Authenticate: BASIC realm="Service-now"
# < Pragma: no-store,no-cache
# < Cache-control: no-cache,no-store,must-revalidate,max-age=-1
# < Expires: 0
# < Content-Type: application/json;charset=UTF-8
# < Transfer-Encoding: chunked
# < Date: Fri, 26 Feb 2021 11:40:33 GMT
# < Server: ServiceNow
# < Set-Cookie: BIGipServerpool_dev86373=2843957002.9537.0000; path=/; Httponly; Secure
# < Strict-Transport-Security: max-age=63072000; includeSubDomains
# < Connection: close
# <
# * Closing connection 0
# * TLSv1.2 (OUT), TLS alert, close notify (256):
# {"error":{"detail":"Required to provide Auth information","message":"User Not Authenticated"},"status":"failure"}

TODAY=$(date '+%Y-%m-%d')

log "Creating ServiceNow Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.servicenow.ServiceNowSourceConnector",
                    "kafka.topic": "topic-servicenow",
                    "proxy.url": "nginx_proxy:8888",
                    "servicenow.url": "'"$SERVICENOW_URL"'",
                    "tasks.max": "1",
                    "servicenow.table": "incident",
                    "servicenow.user": "admin",
                    "servicenow.password": "'"$SERVICENOW_PASSWORD"'",
                    "servicenow.since": "'"$TODAY"'",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/servicenow-source/config | jq .


sleep 10

log "Create one record to ServiceNow"
docker exec -e SERVICENOW_URL="$SERVICENOW_URL" -e SERVICENOW_PASSWORD="$SERVICENOW_PASSWORD" connect \
   curl -X POST \
    "${SERVICENOW_URL}/api/now/table/incident" \
    --user admin:"$SERVICENOW_PASSWORD" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' \
    -d '{"short_description": "This is test"}'

sleep 5

log "Verify we have received the data in topic-servicenow topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic topic-servicenow --from-beginning --max-messages 1