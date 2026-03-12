#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

set +e
if ! connect_cp_version_greater_than_8
then
     logwarn "CP 8.0 or above should be used as log4j2 is not supported in CP 5/6/7"
     exit 111
fi
set -e 

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

playground container logs --container connect --wait-for-log "xxxxxx" --max-wait 60

# [2026-03-12 09:43:44,520] INFO Addxxxxxxd cxxxxxxnnxxxxxxctxxxxxxr fxxxxxxr http://:8083 (org.apache.kafka.connect.runtime.rest.RestServer:193)
# [2026-03-12 09:43:44,521] INFO Inxxxxxxtxxxxxxxxxxxxlxxxxxxzxxxxxxng REST sxxxxxxrvxxxxxxr (org.apache.kafka.connect.runtime.rest.RestServer:267)
# [2026-03-12 09:43:44,544] INFO jxxxxxxtty-12.0.25; bxxxxxxxxxxxxlt: 2025-08-11T23:52:37.219Z; gxxxxxxt: xxxxxx862b76d8372xxxxxx24205765182d9xxxxxxxxxxxx1d1d333cxxxxxx2xxxxxxxxxxxx; jvm 21.0.10+7-LTS (org.eclipse.jetty.server.Server:555)
# [2026-03-12 09:43:44,556] INFO Stxxxxxxrtxxxxxxd http_8083@343f2ccf{HTTP/1.1, (http/1.1)}{0.0.0.0:8083} (org.eclipse.jetty.server.AbstractConnector:326)
# [2026-03-12 09:43:44,558] INFO Stxxxxxxrtxxxxxxd xxxxxxxxxxxxjs.Sxxxxxxrvxxxxxxr@5fbxxxxxx155{STARTING}[12.0.25,stxxxxxx=60000] @6379ms (org.eclipse.jetty.server.Server:612)
# [2026-03-12 09:43:44,573] INFO Advxxxxxxrtxxxxxxsxxxxxxd URI: http://cxxxxxxnnxxxxxxct:8083/ (org.apache.kafka.connect.runtime.rest.RestServer:505)
# [2026-03-12 09:43:44,573] INFO REST sxxxxxxrvxxxxxxr lxxxxxxstxxxxxxnxxxxxxng xxxxxxt http://172.27.0.7:8083/, xxxxxxdvxxxxxxrtxxxxxxsxxxxxxng URL http://cxxxxxxnnxxxxxxct:8083/ (org.apache.kafka.connect.runtime.rest.RestServer:287)
# [2026-03-12 09:43:44,574] INFO Advxxxxxxrtxxxxxxsxxxxxxd URI: http://cxxxxxxnnxxxxxxct:8083/ (org.apache.kafka.connect.runtime.rest.RestServer:505)
# [2026-03-12 09:43:44,574] INFO REST xxxxxxdmxxxxxxn xxxxxxndpxxxxxxxxxxxxnts xxxxxxt http://cxxxxxxnnxxxxxxct:8083/ (org.apache.kafka.connect.runtime.rest.RestServer:290)
# [2026-03-12 09:43:44,574] INFO Advxxxxxxrtxxxxxxsxxxxxxd URI: http://cxxxxxxnnxxxxxxct:8083/ (org.apache.kafka.connect.runtime.rest.RestServer:505)
# [2026-03-12 09:43:44,575] INFO Sxxxxxxttxxxxxxng xxxxxxp All Pxxxxxxlxxxxxxcy fxxxxxxr CxxxxxxnnxxxxxxctxxxxxxrClxxxxxxxxxxxxntCxxxxxxnfxxxxxxgOvxxxxxxrrxxxxxxdxxxxxx. Thxxxxxxs wxxxxxxll xxxxxxllxxxxxxw xxxxxxll clxxxxxxxxxxxxnt cxxxxxxnfxxxxxxgxxxxxxrxxxxxxtxxxxxxxxxxxxns txxxxxx bxxxxxx xxxxxxvxxxxxxrrxxxxxxddxxxxxxn (org.apache.kafka.connect.connector.policy.AllConnectorClientConfigOverridePolicy:45)
# [2026-03-12 09:43:44,580] INFO JsxxxxxxnCxxxxxxnvxxxxxxrtxxxxxxrCxxxxxxnfxxxxxxg vxxxxxxlxxxxxxxxxxxxs: 
#         cxxxxxxnvxxxxxxrtxxxxxxr.typxxxxxx = kxxxxxxy
#         dxxxxxxcxxxxxxmxxxxxxl.fxxxxxxrmxxxxxxt = BASE64
#         rxxxxxxplxxxxxxcxxxxxx.nxxxxxxll.wxxxxxxth.dxxxxxxfxxxxxxxxxxxxlt = trxxxxxxxxxxxx
#         schxxxxxxmxxxxxx.cxxxxxxntxxxxxxnt = nxxxxxxll
#         schxxxxxxmxxxxxxs.cxxxxxxchxxxxxx.sxxxxxxzxxxxxx = 1000
#         schxxxxxxmxxxxxxs.xxxxxxnxxxxxxblxxxxxx = fxxxxxxlsxxxxxx
# [2026-03-12 09:43:44,599] INFO Kxxxxxxfkxxxxxx vxxxxxxrsxxxxxxxxxxxxn: 8.2.0-cxxxxxx (org.apache.kafka.common.utils.AppInfoParser:145)
# [2026-03-12 09:43:44,599] INFO Kxxxxxxfkxxxxxx cxxxxxxmmxxxxxxtId: 927b71ffbd2477xxxxxxxxxxxx (org.apache.kafka.common.utils.AppInfoParser:146)
# [2026-03-12 09:43:44,599] INFO Kxxxxxxfkxxxxxx stxxxxxxrtTxxxxxxmxxxxxxMs: 1773308624599 (org.apache.kafka.common.utils.AppInfoParser:147)
# [2026-03-12 09:43:44,602] INFO MxxxxxxtxxxxxxdxxxxxxtxxxxxxPxxxxxxblxxxxxxshxxxxxxrMxxxxxxtrxxxxxxcs xxxxxxnxxxxxxtxxxxxxxxxxxxlxxxxxxzxxxxxxd wxxxxxxth txxxxxxggxxxxxxd sxxxxxxnsxxxxxxrs fxxxxxxr xxxxxxpxxxxxxrxxxxxxtxxxxxxxxxxxxns, lxxxxxxtxxxxxxncy, xxxxxxnd pxxxxxxylxxxxxxxxxxxxd sxxxxxxzxxxxxx (org.apache.kafka.connect.runtime.events.MetadataPublisherMetrics:151)
# [2026-03-12 09:43:44,605] INFO JsxxxxxxnCxxxxxxnvxxxxxxrtxxxxxxrCxxxxxxnfxxxxxxg vxxxxxxlxxxxxxxxxxxxs: 
#         cxxxxxxnvxxxxxxrtxxxxxxr.typxxxxxx = kxxxxxxy
#         dxxxxxxcxxxxxxmxxxxxxl.fxxxxxxrmxxxxxxt = BASE64
#         rxxxxxxplxxxxxxcxxxxxx.nxxxxxxll.wxxxxxxth.dxxxxxxfxxxxxxxxxxxxlt = trxxxxxxxxxxxx
#         schxxxxxxmxxxxxx.cxxxxxxntxxxxxxnt = nxxxxxxll
#         schxxxxxxmxxxxxxs.cxxxxxxchxxxxxx.sxxxxxxzxxxxxx = 1000
#         schxxxxxxmxxxxxxs.xxxxxxnxxxxxxblxxxxxx = fxxxxxxlsxxxxxx
# [2026-03-12 09:43:44,605] INFO JsxxxxxxnCxxxxxxnvxxxxxxrtxxxxxxrCxxxxxxnfxxxxxxg vxxxxxxlxxxxxxxxxxxxs: 
#         cxxxxxxnvxxxxxxrtxxxxxxr.typxxxxxx = vxxxxxxlxxxxxxxxxxxx
#         dxxxxxxcxxxxxxmxxxxxxl.fxxxxxxrmxxxxxxt = BASE64
#         rxxxxxxplxxxxxxcxxxxxx.nxxxxxxll.wxxxxxxth.dxxxxxxfxxxxxxxxxxxxlt = trxxxxxxxxxxxx
#         schxxxxxxmxxxxxx.cxxxxxxntxxxxxxnt = nxxxxxxll
#         schxxxxxxmxxxxxxs.cxxxxxxchxxxxxx.sxxxxxxzxxxxxx = 1000
#         schxxxxxxmxxxxxxs.xxxxxxnxxxxxxblxxxxxx = fxxxxxxlsxxxxxx