#!/usr/bin/env bash
# Replaces /opt/launcher/plugins/006_waitfor/waitfor.sh of flokkr/hadoop, which accepts a single host:port.
# WAITFOR is a space-separated list of host:port, all of them must be reachable before the next plugins run
# (012_hdfsinit formats the namenode or bootstraps the standby only once, it is never retried).
if [ ! -z "$WAITFOR" ]; then
  for HOSTPORT in $WAITFOR; do
    echo "Waiting for $HOSTPORT"
    WAITFOR_HOST=$(printf "%s\n" "$HOSTPORT"| cut -d : -f 1)
    WAITFOR_PORT=$(printf "%s\n" "$HOSTPORT"| cut -d : -f 2)
    READY=0
    for i in `seq ${WAITFOR_TIMEOUT:-60}` ; do
      if nc -z "$WAITFOR_HOST" "$WAITFOR_PORT" > /dev/null 2>&1 ; then
        READY=1
        break
      fi
      sleep 1
    done
    if [ $READY -eq 0 ] ; then
      echo "Operation timed out waiting for $HOSTPORT" >&2
      exit 1
    fi
  done
fi
call-next-plugin "$@"
