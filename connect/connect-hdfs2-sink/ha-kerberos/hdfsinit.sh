#!/usr/bin/env bash
# Replaces /opt/launcher/plugins/012_hdfsinit/hdfsinit.sh of flokkr/hadoop (namenodes only), which formats the namenode
# (ENSURE_NAMENODE_DIR) or bootstraps the standby (ENSURE_STANDBY_NAMENODE_DIR) once and ignores a failure: the namenode
# then starts without storage directory. Here a failed attempt is retried: an open journal node port (8485) does not mean
# the journal node already answers "ready for formatting" (QuorumException), and an open namenode1 port (9820) does not
# mean namenode1 already serves the bootstrapStandby RPCs.
# HDFSINIT_RETRIES (default 10) attempts, HDFSINIT_RETRY_INTERVAL (default 15) seconds apart.
# Plugins are sourced by the launcher: keep every name prefixed.
HDFSINIT_RETRIES=${HDFSINIT_RETRIES:-10}
HDFSINIT_RETRY_INTERVAL=${HDFSINIT_RETRY_INTERVAL:-15}

# $1: storage directory, removed before each retry so that a half-created directory is not mistaken for a done init
# $2...: command
hdfsinit_retry() {
   local dir=$1 i
   shift
   for i in $(seq "$HDFSINIT_RETRIES"); do
      if "$@"; then
         return 0
      fi
      echo "hdfsinit: attempt $i/$HDFSINIT_RETRIES of '$*' failed, retrying in $HDFSINIT_RETRY_INTERVAL seconds" >&2
      rm -rf "$dir"
      sleep "$HDFSINIT_RETRY_INTERVAL"
   done
   echo "hdfsinit: '$*' still failing after $HDFSINIT_RETRIES attempts" >&2
   exit 1
}

if [ -n "$ENSURE_NAMENODE_DIR" ] && [ ! -d "$ENSURE_NAMENODE_DIR" ]; then
   CLUSTERID_OPTS=""
   if [ -n "$ENSURE_NAMENODE_CLUSTERID" ]; then
      CLUSTERID_OPTS="-clusterid $ENSURE_NAMENODE_CLUSTERID"
   fi
   hdfsinit_retry "$ENSURE_NAMENODE_DIR" /opt/hadoop/bin/hdfs namenode -format -force -nonInteractive $CLUSTERID_OPTS
fi

if [ -n "$ENSURE_STANDBY_NAMENODE_DIR" ] && [ ! -d "$ENSURE_STANDBY_NAMENODE_DIR" ]; then
   hdfsinit_retry "$ENSURE_STANDBY_NAMENODE_DIR" /opt/hadoop/bin/hdfs namenode -bootstrapStandby -force -nonInteractive
fi

call-next-plugin "$@"
