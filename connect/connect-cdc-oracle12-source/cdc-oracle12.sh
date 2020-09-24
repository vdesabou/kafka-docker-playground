#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -d ${DIR}/confluentinc-kafka-connect-oracle-cdc-0.1.0-preview ]
then
     logerror "ERROR: ${DIR}/confluentinc-kafka-connect-oracle-cdc-0.1.0-preview is missing."
     exit 1
fi

if [ -z "$TRAVIS" ]
then
     # not running with travis
     if test -z "$(docker images -q oracle/database:12.2.0.1-ee)"
     then
          if [ ! -f ${DIR}/linuxx64_12201_database.zip ]
          then
               logerror "ERROR: ${DIR}/linuxx64_12201_database.zip is missing. It must be downloaded manually in order to acknowledge user agreement"
               exit 1
          fi
          log "Building oracle/database:12.2.0.1-ee docker image..it can take a while...(more than 15 minutes!)"
          OLDDIR=$PWD
          rm -rf ${DIR}/docker-images
          git clone https://github.com/oracle/docker-images.git

          cp ${DIR}/linuxx64_12201_database.zip ${DIR}/docker-images/OracleDatabase/SingleInstance/dockerfiles/12.2.0.1/linuxx64_12201_database.zip
          cd ${DIR}/docker-images/OracleDatabase/SingleInstance/dockerfiles
          ./buildDockerImage.sh -v 12.2.0.1 -e
          rm -rf ${DIR}/docker-images
          cd ${OLDDIR}
     fi
fi

export ORACLE_IMAGE="oracle/database:12.2.0.1-ee"
if [ ! -z "$TRAVIS" ]
then
     # if this is travis build, use private image.
     export ORACLE_IMAGE="vdesabou/oracle12"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=900
CUR_WAIT=0
log "Waiting up to $MAX_WAIT seconds for Oracle DB to start"
docker container logs oracle > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "DONE: Executing user defined scripts" ]]; do
sleep 10
docker container logs oracle > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in oracle container do not show 'DONE: Executing user defined scripts' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "Oracle DB has started!"

log "Creating Oracle source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":1,
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "oracle.server": "oracle",
               "oracle.port": 1521,
               "oracle.database": "ORCLCDB",
               "oracle.username": "C##MYUSER",
               "oracle.password": "mypassword",
               "start.from":"snapshot",
               "log.topic.name": "redo-log-topic",
               "table.inclusion.regex": ".*CUSTOMERS.*",
               "_table.topic.name.template_":"Using template vars to set change event topic for each table",
               "table.topic.name.template": "${databaseName}.${tableName}",
               "connection.pool.max.size": 20,
               "confluent.topic.replication.factor":1
          }' \
     http://localhost:8083/connectors/cdc-oracle-source/config | jq .

# SQL> select table_name, tablespace_name from all_tables where owner = 'C##MYUSER';

# TABLE_NAME
# --------------------------------------------------------------------------------
# TABLESPACE_NAME
# ------------------------------
# CUSTOMERS
# USERS

# FIXTHIS:

{
  "error_code": 400,
  "message": "Connector configuration is invalid and contains the following 1 error(s):\nInclusion pattern matches no tables in 'ORCLCDB' database at oracle:1521 with user 'C##MYUSER' (pool=oracle-cdc-source:cdc-oracle-source9).\nYou can also find the above list of errors at the endpoint `/connector-plugins/{connectorType}/config/validate`"
}

sleep 5

log "Verifying topic oracle-CUSTOMERS"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic oracle-CUSTOMERS --from-beginning --max-messages 2

# SQL> SQL> Database closed.
# Database dismounted.
# ORACLE instance shut down.
# SQL> ORACLE instance started.

# Total System Global Area 1610612736 bytes
# Fixed Size                  8793304 bytes
# Variable Size             671089448 bytes
# Database Buffers          922746880 bytes
# Redo Buffers                7983104 bytes
# Database mounted.
# SQL>
# Database altered.

# SQL>
# Database altered.

# SQL> SQL> Database log mode            Archive Mode
# Automatic archival             Enabled
# Archive destination            /opt/oracle/product/12.2.0.1/dbhome_1/dbs/arch
# Oldest online log sequence     1
# Next log sequence to archive   2
# Current log sequence           2
# SQL> Disconnected from Oracle Database 12c Enterprise Edition Release 12.2.0.1.0 - 64bit Production

# SQL*Plus: Release 12.2.0.1.0 Production on Thu Sep 24 14:43:11 2020

# Copyright (c) 1982, 2016, Oracle.  All rights reserved.


# Connected to:
# Oracle Database 12c Enterprise Edition Release 12.2.0.1.0 - 64bit Production

# SQL> SQL> Disconnected from Oracle Database 12c Enterprise Edition Release 12.2.0.1.0 - 64bit Production

# SQL*Plus: Release 12.2.0.1.0 Production on Thu Sep 24 14:43:11 2020

# Copyright (c) 1982, 2016, Oracle.  All rights reserved.


# Connected to:
# Oracle Database 12c Enterprise Edition Release 12.2.0.1.0 - 64bit Production

# SQL>
# Role created.

# SQL>   2    3    4
# Grant succeeded.

# SQL>
# Grant succeeded.

# SQL>
# Grant succeeded.

# SQL>
# Grant succeeded.

# SQL>
# Grant succeeded.

# SQL> SQL>
# User created.

# SQL>
# Grant succeeded.

# SQL>
# User altered.

# SQL> SQL>
# Grant succeeded.

# SQL> SQL>
# Grant succeeded.

# SQL>
# Grant succeeded.

# SQL>
# Grant succeeded.

# SQL>
# Grant succeeded.

# SQL>
# Grant succeeded.

# SQL> SQL> SQL>
# Session altered.

# SQL>
# Database altered.

# SQL>
# Database altered.

# SQL> SQL> Disconnected from Oracle Database 12c Enterprise Edition Release 12.2.0.1.0 - 64bit Production

# DONE: Executing user defined scripts

# The Oracle base remains unchanged with value /opt/oracle
# #########################
# DATABASE IS READY TO USE!
# #########################

# Executing user defined scripts
# /opt/oracle/runUserScripts.sh: running /opt/oracle/scripts/startup/01_create_customers.sh
# Creating CUSTOMERS table

# SQL*Plus: Release 12.2.0.1.0 Production on Thu Sep 24 14:43:12 2020

# Copyright (c) 1982, 2016, Oracle.  All rights reserved.


# Connected to:
# Oracle Database 12c Enterprise Edition Release 12.2.0.1.0 - 64bit Production

# SQL> SQL>   2    3    4    5    6    7    8    9   10   11
# Table created.

# SQL> SQL>   2    3    4    5    6    7    8    9   10
# Trigger created.

# SQL> SQL> Disconnected from Oracle Database 12c Enterprise Edition Release 12.2.0.1.0 - 64bit Production

# /opt/oracle/runUserScripts.sh: running /opt/oracle/scripts/startup/02_populate_customers.sh
# Creating and populating customers table

# SQL*Plus: Release 12.2.0.1.0 Production on Thu Sep 24 14:43:13 2020

# Copyright (c) 1982, 2016, Oracle.  All rights reserved.

# Last Successful login time: Thu Sep 24 2020 14:43:12 +00:00

# Connected to:
# Oracle Database 12c Enterprise Edition Release 12.2.0.1.0 - 64bit Production

# SQL> SQL> insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (1, 'Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy')
#             *
# ERROR at line 1:
# ORA-00942: table or view does not exist


# SQL> insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (2, 'Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface')
#             *
# ERROR at line 1:
# ORA-00942: table or view does not exist


# SQL> insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (3, 'Mariejeanne', 'Cocci', 'mcocci2@techcrunch.com', 'Female', 'bronze', 'Multi-tiered bandwidth-monitored capability')
#             *
# ERROR at line 1:
# ORA-00942: table or view does not exist


# SQL> insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (4, 'Hashim', 'Rumke', 'hrumke3@sohu.com', 'Male', 'platinum', 'Self-enabling 24/7 firmware')
#             *
# ERROR at line 1:
# ORA-00942: table or view does not exist


# SQL> insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments) values (5, 'Hansiain', 'Coda', 'hcoda4@senate.gov', 'Male', 'platinum', 'Centralized full-range approach')
#             *
# ERROR at line 1:
# ORA-00942: table or view does not exist


# SQL> SQL> Disconnected from Oracle Database 12c Enterprise Edition Release 12.2.0.1.0 - 64bit Production

# DONE: Executing user defined scripts

# The following output is now a tail of the alert.log:
# SUPLOG:  procedural replication = OFF
# SUPPLEMENTAL LOG: Waiting for completion of transactions started at or before scn 1448229 (0x0000000000161925)
# SUPPLEMENTAL LOG: All transactions started at or before scn 1448229 (0x0000000000161925) have completed
# Completed: ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS
# 2020-09-24T14:43:12.349945+00:00
# ===========================================================
# Dumping current patch information
# ===========================================================
# No patches have been applied
# ===========================================================

