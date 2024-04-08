#!/bin/sh

if [ -z $DOGSHELL_API_KEY ]; then
  echo "env DOGSHELL_API_KEY does not exist"
  exit 1
fi

if [ -z $DOGSHELL_APP_KEY ]; then
  echo "env DOGSHELL_APP_KEY does not exist"
  exit 1
fi

echo "[Connection]" > ~/.dogrc
echo "apikey = ${DOGSHELL_API_KEY}" >> ~/.dogrc
echo "appkey = ${DOGSHELL_APP_KEY}" >> ~/.dogrc

/usr/local/bin/dog $@
