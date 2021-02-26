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

log "Verify with curl version 7.38.0"
docker exec  -e SERVICENOW_URL=$SERVICENOW_URL -e SERVICENOW_PASSWORD=$SERVICENOW_PASSWORD oldcurl bash -c "export HTTP_PROXY=nginx_proxy:8888 && export HTTPS_PROXY=nginx_proxy:8888 && curl  -v ${SERVICENOW_URL}api/now/table/incident?sysparm_limit=1 -u \"admin:$SERVICENOW_PASSWORD\""

# * Hostname was NOT found in DNS cache
#   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
#                                  Dload  Upload   Total   Spent    Left  Speed
#   0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0*   Trying 172.28.0.2...
# * Connected to nginx_proxy (172.28.0.2) port 8888 (#0)
# * Establish HTTP proxy tunnel to dev86373.service-now.com:443
# * Server auth using Basic with user 'admin'
# > CONNECT dev86373.service-now.com:443 HTTP/1.1
# > Host: dev86373.service-now.com:443
# > User-Agent: curl/7.38.0
# > Proxy-Connection: Keep-Alive
# >
# < HTTP/1.1 200 Connection Established
# < Proxy-agent: nginx
# <
# * Proxy replied OK to CONNECT request
# * successfully set certificate verify locations:
# *   CAfile: none
#   CApath: /etc/ssl/certs
# * SSLv3, TLS handshake, Client hello (1):
# } [data not shown]
# * SSLv3, TLS handshake, Server hello (2):
# { [data not shown]
# * SSLv3, TLS handshake, CERT (11):
# { [data not shown]
# * SSLv3, TLS handshake, Server key exchange (12):
# { [data not shown]
# * SSLv3, TLS handshake, Server finished (14):
# { [data not shown]
# * SSLv3, TLS handshake, Client key exchange (16):
# } [data not shown]
# * SSLv3, TLS change cipher, Client hello (1):
# } [data not shown]
# * SSLv3, TLS handshake, Finished (20):
# } [data not shown]
# * SSLv3, TLS change cipher, Client hello (1):
# { [data not shown]
# * SSLv3, TLS handshake, Finished (20):
# { [data not shown]
# * SSL connection using TLSv1.2 / ECDHE-RSA-AES128-GCM-SHA256
# * Server certificate:
# *        subject: C=US; ST=California; L=San Diego; O=ServiceNow, Inc.; CN=*.service-now.com
# *        start date: 2020-07-22 23:55:53 GMT
# *        expire date: 2021-04-01 23:55:53 GMT
# *        subjectAltName: dev86373.service-now.com matched
# *        issuer: C=US; O=Entrust, Inc.; OU=See www.entrust.net/legal-terms; OU=(c) 2012 Entrust, Inc. - for authorized use only; CN=Entrust Certification Authority - L1K
# *        SSL certificate verify ok.
# * Server auth using Basic with user 'admin'
# > GET /api/now/table/incident?sysparm_limit=1 HTTP/1.1
# > Authorization: Basic YWRtaW46Nkd2S0s1bW5hSGpZ
# > User-Agent: curl/7.38.0
# > Host: dev86373.service-now.com
# > Accept: */*
# >
#   0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0< HTTP/1.1 200 OK
# < Set-Cookie: JSESSIONID=1460AB6D7BDED090BEC1AAF63751AA35; Path=/; HttpOnly;Secure
# < Set-Cookie: glide_user=; Max-Age=0; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/; HttpOnly;Secure
# < Set-Cookie: glide_user_session=; Max-Age=0; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Path=/; HttpOnly;Secure
# < Set-Cookie: glide_user_route=glide.163db7335e7500df6267a1f3113f00cf; Max-Age=2147483647; Expires=Wed, 16-Mar-2089 17:03:55 GMT; Path=/; HttpOnly;Secure
# < X-Is-Logged-In: true
# < X-Transaction-ID: 79aee3f52fa2
# < Set-Cookie: glide_session_store=35AEE3F52FA22010FC759BACF699B601; Max-Age=1800; Expires=Fri, 26-Feb-2021 14:19:48 GMT; Path=/; HttpOnly;Secure
# < Link: <https://dev86373.service-now.com/api/now/table/incident?sysparm_limit=1&sysparm_offset=0>;rel="first",<https://dev86373.service-now.com/api/now/table/incident?sysparm_limit=1&sysparm_offset=-1>;rel="prev",<https://dev86373.service-now.com/api/now/table/incident?sysparm_limit=1&sysparm_offset=1>;rel="next",<https://dev86373.service-now.com/api/now/table/incident?sysparm_limit=1&sysparm_offset=72>;rel="last"
# < X-Total-Count: 73
# < Pragma: no-store,no-cache
# < Cache-control: no-cache,no-store,must-revalidate,max-age=-1
# < Expires: 0
# < Content-Type: application/json;charset=UTF-8
# < Transfer-Encoding: chunked
# < Date: Fri, 26 Feb 2021 13:49:48 GMT
# * Server ServiceNow is not blacklisted
# < Server: ServiceNow
# < Set-Cookie: BIGipServerpool_dev86373=2843957002.9537.0000; path=/; Httponly; Secure
# < Strict-Transport-Security: max-age=63072000; includeSubDomains
# <
# { [data not shown]
# 100  3362    0  3362    0     0   5886      0 --:--:-- --:--:-- --:--:--  5877
# * Connection #0 to host nginx_proxy left intact

# block
echo "$SERVICENOW_URL" | cut -d "/" -f3
ip=$(dig +short $(echo "$SERVICENOW_URL" | cut -d "/" -f3))
log "Blocking serviceNow instance IP address $ip on connect, to make sure proxy is used"
docker exec -i --privileged --user root connect bash -c "yum update -y && yum install iptables -y"
docker exec -i --privileged --user root connect bash -c "iptables -A INPUT -s $ip -j REJECT"
docker exec -i --privileged --user root connect bash -c "iptables -A INPUT -d $ip -j REJECT"
docker exec -i --privileged --user root connect bash -c "iptables -A OUTPUT -s $ip -j REJECT"
docker exec -i --privileged --user root connect bash -c "iptables -A OUTPUT -d $ip -j REJECT"
docker exec -i --privileged --user root connect bash -c "iptables -L -n -v"

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