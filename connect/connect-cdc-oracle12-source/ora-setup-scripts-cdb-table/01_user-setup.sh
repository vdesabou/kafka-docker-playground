#!/bin/sh

echo 'Configuring Oracle for user myuser'

# Set archive log mode and enable GG replication
ORACLE_SID=XE
export ORACLE_SID

# https://github.com/oracle/docker-images/issues/1213
# https://github.com/oracle/docker-images/pull/1217
su -p oracle -c "sqlplus /nolog <<- EOF
	CONNECT sys/Admin123 AS SYSDBA
        -- Turn on Archivelog Mode
	shutdown immediate
	startup mount
	alter database archivelog;
		-- ALTER DATABASE FLASHBACK ON;
	alter database open;
        -- Should show 'Database log mode: Archive Mode'
	archive log list
	exit;
EOF"

# Create C##MYUSER user in CDB (see https://github.com/oracle/docker-images/issues/443#issuecomment-313157302)
# https://github.com/oracle/docker-images/issues/1213
# https://github.com/oracle/docker-images/pull/1217
su -p oracle -c "sqlplus / as sysdba <<- EOF
	create role C##CDC_PRIVS;
	grant create session,
	execute_catalog_role,
	select any transaction,
	select any dictionary to C##CDC_PRIVS;
	grant select on SYSTEM.LOGMNR_COL$ to C##CDC_PRIVS;
	grant select on SYSTEM.LOGMNR_OBJ$ to C##CDC_PRIVS;
	grant select on SYSTEM.LOGMNR_USER$ to C##CDC_PRIVS;
	grant select on SYSTEM.LOGMNR_UID$ to C##CDC_PRIVS;

	create user C##MYUSER identified by mypassword;
	grant C##CDC_PRIVS to C##MYUSER;
	alter user C##MYUSER quota unlimited on users;

	grant LOGMINING to C##CDC_PRIVS;

	GRANT CREATE SESSION TO C##MYUSER container=all;
	GRANT CREATE TABLE TO C##MYUSER container=all;
	GRANT CREATE SEQUENCE TO C##MYUSER container=all;
	GRANT CREATE TRIGGER TO C##MYUSER container=all;
	GRANT FLASHBACK ANY TABLE TO C##MYUSER container=all;

        -- Enable Supplemental Logging for All Columns
	ALTER SESSION SET CONTAINER=cdb$root;
	ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
	ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

	exit;
EOF"

