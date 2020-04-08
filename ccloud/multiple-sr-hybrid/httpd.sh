#!/bin/bash
# https://stackoverflow.com/a/24342101

PORT=${1:-8080}
FILES=${2:-"./"}

rm -f out
mkfifo out
trap "rm -f out" EXIT

function echoResponse() {
        echo "HTTP/1.1 200 OK"
        echo "Date: $(LC_TIME=en_US date -u)"
        echo "Server: a server"
        echo "Connection: close"
        echo "Pragma: public"
        echo "Content-Type: application/json; charset=UTF-8"
        FILESIZE=$(wc -c < "$FILES")
        echo -e "Content-Length: $FILESIZE\n"
        cat "$FILES"
        >&2 echo "[ ok ]"
}
while true
do
  cat out | nc -l $PORT > >( # parse the netcat output, to build the answer redirected to the pipe "out".
    export REQUEST=
    while read -r line
    do
      line=$(echo "$line" | tr -d '\r\n')

      if echo "$line" | grep -qE '^GET /' # if line starts with "GET /"
      then
        REQUEST=$(echo "$line" | cut -d ' ' -f2) # extract the request
      elif [ -z "$line" ] # empty line / end of request
      then
        # call a script here
        # Note: REQUEST is exported, so the script can parse it (to answer 200/403/404 status code + content)
        echoResponse > out
      fi
    done
  )
done