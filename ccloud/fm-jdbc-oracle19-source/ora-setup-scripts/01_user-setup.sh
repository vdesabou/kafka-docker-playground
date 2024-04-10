#!/bin/sh

echo 'Configuring Oracle for user myuser'

# Set archive log mode and enable GG replication
ORACLE_SID=ORCLCDB
export ORACLE_SID

sqlplus /nolog <<- EOF
	CONNECT sys/Admin123 AS SYSDBA
	-- Turn on Archivelog Mode
	SHUTDOWN IMMEDIATE
	STARTUP MOUNT
	ALTER DATABASE ARCHIVELOG;
	ALTER DATABASE FLASHBACK ON;
	ALTER DATABASE OPEN;
	-- Should show "Database log mode: Archive Mode"
	ARCHIVE LOG LIST
	exit;
EOF

