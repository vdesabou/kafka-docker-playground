#!/bin/bash
# promyk.doleczek.pl
# LICENSE MIT

PORT=${1:-8080}
FILES=${2:-"./"}

NS=$(netstat -taupen 2>/dev/null | grep ":$PORT ")
test -n "$NS" && echo "Port $PORT is already taken" && exit 1

echo -e "\n\tHTTPD started for files in $FILES:"

for IP in $(ifconfig | grep "inet addr" | cut -d ':' -f 2 | cut -d ' ' -f 1) ; do
    echo -e "\tlistening at $IP:$PORT"
done

echo -e "\n"
FIFO="/tmp/httpd$PORT"
rm -f $FIFO
mkfifo $FIFO
trap ctrl_c INT

function ctrl_c() {
    rm -f $FIFO && echo -e "\n\tServer shut down.\n" && exit
}

while true; do (
    read req < $FIFO;
        echo "HTTP/1.1 200 OK"
        echo "Date: $(LC_TIME=en_US date -u)"
        echo "Server: promyk.doleczek.pl"
        echo "Connection: close"
        echo "Pragma: public"
        echo "Content-Type: application/json; charset=UTF-8"
        FILESIZE=$(wc -c < "/tmp/json/sr.json")
        echo -e "Content-Length: $FILESIZE\n"
        cat "/tmp/json/sr.json"
        >&2 echo "[ ok ]"
) | nc -l -k -w 1 -p $PORT > $FIFO; done;
