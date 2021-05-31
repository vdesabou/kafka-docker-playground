#!/bin/bash
#
# Copyright (c) 2014-2018 Oracle and/or its affiliates. All rights reserved.
#

# If log.nm does not exists, container is starting for 1st time
# So it should start NM and also associate with AdminServer
# Otherwise, only start NM (container restarted)
if [ ! -f log.nm ]; then
    ADD_MACHINE=1
fi

# Wait for AdminServer to become available for any subsequent operation
/u01/oracle/waitForAdminServer.sh

# Start Node Manager
echo "Starting NodeManager in background..."
nohup startNodeManager.sh > log.nm 2>&1 &
echo "NodeManager started."

# Add a Machine to the AdminServer only if 1st execution
if [ $ADD_MACHINE -eq 1 ]; then
  wlst /u01/oracle/add-machine.py
fi

# print log
tail -f log.nm
