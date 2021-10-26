	-- Turn on Archivelog Mode
SHUTDOWN IMMEDIATE
STARTUP MOUNT
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
	-- Should show "Database log mode: Archive Mode"
ARCHIVE LOG LIST
exit;