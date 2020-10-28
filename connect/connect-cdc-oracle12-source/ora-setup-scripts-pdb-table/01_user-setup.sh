#!/bin/sh

echo 'Configuring Oracle for user myuser'

# Set archive log mode and enable GG replication
ORACLE_SID=ORCLCDB
export ORACLE_SID

sqlplus /nolog <<- EOF
	CONNECT sys/Admin123 AS SYSDBA
        -- Turn on Archivelog Mode
	shutdown immediate
	startup mount
	alter database archivelog;
	alter database open;
        -- Should show "Database log mode: Archive Mode"
	archive log list
	exit;
EOF

# Create C##MYUSER user in CDB (see https://github.com/oracle/docker-images/issues/443#issuecomment-313157302)
sqlplus / as sysdba <<- EOF
	create role C##CDC_PRIVS;
	grant create session,
	execute_catalog_role,
	select any transaction,
	select any dictionary to C##CDC_PRIVS;
	grant select on SYSTEM.LOGMNR_COL\$ to C##CDC_PRIVS;
	grant select on SYSTEM.LOGMNR_OBJ\$ to C##CDC_PRIVS;
	grant select on SYSTEM.LOGMNR_USER\$ to C##CDC_PRIVS;
	grant select on SYSTEM.LOGMNR_UID\$ to C##CDC_PRIVS;

	create user C##MYUSER identified by mypassword CONTAINER=all;
	grant C##CDC_PRIVS to C##MYUSER CONTAINER=all;
	alter user C##MYUSER quota unlimited on users;
	alter user C##MYUSER set container_data = (cdb\$root, ORCLPDB1) container=current;

	ALTER SESSION SET CONTAINER=cdb\$root;
	GRANT create session, alter session, set container, logmining, execute_catalog_role TO C##MYUSER CONTAINER=all;
	GRANT select on GV_\$DATABASE to C##MYUSER CONTAINER=all;
	GRANT select on V_\$LOGMNR_CONTENTS to C##MYUSER CONTAINER=all;
	GRANT select on GV_\$ARCHIVED_LOG to C##MYUSER CONTAINER=all;

	GRANT CONNECT TO C##MYUSER container=all;
	GRANT CREATE TABLE TO C##MYUSER container=all;
	GRANT CREATE SEQUENCE TO C##MYUSER container=all;
	GRANT CREATE TRIGGER TO C##MYUSER container=all;

        -- Enable Supplemental Logging for All Columns
	ALTER SESSION SET CONTAINER=cdb\$root;
	ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
	ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

	exit;
EOF

