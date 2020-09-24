#!/bin/sh

echo 'Configuring Oracle for user myuser'

# Set archive log mode and enable GG replication
ORACLE_SID=ORCLCDB
export ORACLE_SID

sqlplus /nolog <<- EOF
	CONNECT sys/Admin123 AS SYSDBA
	shutdown immediate
	startup mount
	alter database archivelog;
	alter database open;
        -- Should show "Database log mode: Archive Mode"
	archive log list
	exit;
EOF

# Create myuser user
sqlplus sys/Admin123@//localhost:1521/ORCLPDB1 as sysdba <<- EOF
	create role cdc_privs;
	grant create session,
	execute_catalog_role,
	select any transaction,
	select any dictionary to cdc_privs;
	grant select on SYSTEM.LOGMNR_COL$ to cdc_privs;
	grant select on SYSTEM.LOGMNR_OBJ$ to cdc_privs;
	grant select on SYSTEM.LOGMNR_USER$ to cdc_privs;
	grant select on SYSTEM.LOGMNR_UID$ to cdc_privs;

	create user myuser identified by mypassword;
	grant cdc_privs to myuser;
	alter user myuser quota unlimited on users;

	grant LOGMINING to cdc_privs;

	GRANT CONNECT TO myuser;
	GRANT CREATE SESSION TO myuser;
	GRANT CREATE TABLE TO myuser;
	GRANT CREATE SEQUENCE TO myuser;
	GRANT CREATE TRIGGER TO myuser;

	ALTER SESSION SET CONTAINER=cdb$root;
	ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
	ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

	exit;
EOF

