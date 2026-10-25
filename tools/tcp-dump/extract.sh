#!/bin/sh
# Extracts the fields that 'playground analyze tcp-dump' needs from a capture, as TSV files, with tshark.
# Runs in the nicolaka/netshoot image (tshark, capinfos), so nothing has to be installed on the host:
#
#   extract.sh <capture file> <output folder>
#
# KAFKA_PORTS (space separated) adds listener ports decoded as Kafka, besides 9092 (the default of the dissector).
# The analysis itself is done by tcp_dump_analyzer.py, on the host.

file="$1"
out="$2"
mkdir -p "$out"

decode=""
for port in $KAFKA_PORTS
do
    decode="$decode -d tcp.port==$port,kafka"
done
# HTTP_PORTS (space separated) adds ports decoded as HTTP, besides the defaults of the dissector (80, 8080, 8088...)
for port in $HTTP_PORTS
do
    decode="$decode -d tcp.port==$port,http"
done

# tshark, fields as TSV, no name resolution (the analyzer maps the ip addresses with the .hosts file)
fields () {
    filter="$1"
    shift
    # shellcheck disable=SC2086
    tshark -r "$file" -n $decode ${filter:+-Y "$filter"} -T fields -E separator=/t -E occurrence=a -E aggregator=, "$@" 2> /dev/null
}

capinfos -M "$file" > "$out/info.txt" 2> /dev/null

# one line per packet
fields "" -e frame.number -e frame.time_epoch -e frame.len -e frame.cap_len -e ip.src -e ip.dst -e ipv6.src -e ipv6.dst \
    -e tcp.stream -e tcp.srcport -e tcp.dstport -e udp.srcport -e udp.dstport -e tcp.flags.syn -e tcp.flags.ack \
    -e tcp.flags.reset -e tcp.flags.fin -e tcp.len -e _ws.col.protocol > "$out/packets.tsv"

# the frames flagged by the tcp analysis (two passes, so that every flag is set)
tshark -r "$file" -n -2 -Y "tcp.analysis.retransmission || tcp.analysis.fast_retransmission" -T fields -e frame.number > "$out/retransmissions.txt" 2> /dev/null
tshark -r "$file" -n -2 -Y "tcp.analysis.duplicate_ack" -T fields -e frame.number > "$out/duplicate_acks.txt" 2> /dev/null
tshark -r "$file" -n -2 -Y "tcp.analysis.zero_window" -T fields -e frame.number > "$out/zero_windows.txt" 2> /dev/null

fields "tls.handshake.type == 1 || tls.alert_message || tls.record.content_type == 23" \
    -e frame.number -e tls.handshake.type -e tls.handshake.extensions_server_name -e tls.alert_message.level \
    -e tls.alert_message.desc -e tls.record.content_type -e tls.record.version > "$out/tls.tsv"

fields "dns" -e frame.number -e dns.flags.response -e dns.qry.name -e dns.flags.rcode -e dns.time > "$out/dns.tsv"

fields "kafka" -e frame.number -e kafka.api_key -e kafka.api_version -e kafka.correlation_id -e kafka.request_frame \
    -e kafka.error -e kafka.client_id > "$out/kafka.tsv"

# the body (hex, de-chunked and decompressed by tshark) is the last field, cut to its first 1000 bytes
fields "http.request || http.response" -e frame.number -e http.request.method -e http.request.uri -e http.host \
    -e http.response.code -e http.response.phrase -e http.request_in -e http.time -e http.content_type \
    -e http.file_data | awk -F '\t' 'BEGIN { OFS = "\t" } { $NF = substr($NF, 1, 2000); print }' > "$out/http.tsv"
