#!/bin/sh
# 

echo "Memory Stats"

docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA

drop table tab1 purge;
drop table tab2 purge;

--
-- Set up the environment for oradebug calls
--
oradebug setmypid

set echo off trimspool on
set verify off
undefine p_1
undefine p_2
undefine s1
undefine s2
variable p1 number
variable p2 number

column sys_date new_value sysdt noprint
select to_char(sysdate, 'RRRRMMDDHH24MISS') sys_date from dual;
--
-- Get process id of the C##MYUSER session
--
column pid new_value p_1
select pid from v\$process where addr in (select paddr from v\$session where username = 'C##MYUSER' and sid = (select max(sid) From v\$session where username = 'C##MYUSER'));

begin
	:p1 := &p_1;
end;
/

--
-- Dump process detail to v\$process_memory_detail
--
oradebug dump pga_detail_get &p_1

spool &p_1._pga_stats_&sysdt..log
--
-- Get session information for C##MYUSER
--
COLUMN alme     HEADING "Allocated MB" FORMAT 99999D9
COLUMN usme     HEADING "Used MB"      FORMAT 99999D9
COLUMN frme     HEADING "Freeable MB"  FORMAT 99999D9
COLUMN mame     HEADING "Max MB"       FORMAT 99999D9
COLUMN username                        FORMAT a25
COLUMN program                         FORMAT a22
COLUMN sid                             FORMAT a5
COLUMN spid                            FORMAT a8
column pid_remote format a12
SET LINESIZE 300
SELECT s.username, SUBSTR(s.sid,1,5) sid, p.spid, logon_time,
       SUBSTR(s.program,1,22) program , s.process pid_remote,
       s.status,
       ROUND(pga_used_mem/1024/1024) usme,
       ROUND(pga_alloc_mem/1024/1024) alme,
       ROUND(pga_freeable_mem/1024/1024) frme,
       ROUND(pga_max_mem/1024/1024) mame
FROM  v\$session s,v\$process p
WHERE p.addr=s.paddr
AND   s.username = 'C##MYUSER'
ORDER BY pga_max_mem,logon_time;

--
-- Sleep 30 seconds
--
-- Get session information again
--
exec dbms_lock.sleep(30)

column sid new_value s1 noprint
SELECT s.username, SUBSTR(s.sid,1,5) sid, p.spid, logon_time,
       SUBSTR(s.program,1,22) program , s.process pid_remote,
       s.status,
       ROUND(pga_used_mem/1024/1024) usme,
       ROUND(pga_alloc_mem/1024/1024) alme,
       ROUND(pga_freeable_mem/1024/1024) frme,
       ROUND(pga_max_mem/1024/1024) mame
FROM  v\$session s,v\$process p
WHERE p.addr=s.paddr
AND   s.username = 'C##MYUSER'
ORDER BY pga_max_mem,logon_time;

exec dbms_lock.sleep(10)

select max(sid) sid from v\$session where username = 'C##MYUSER';

--
-- Get process memory info
--
COLUMN category      HEADING "Category"
COLUMN allocated     HEADING "Allocated bytes"
COLUMN used          HEADING "Used bytes"
COLUMN max_allocated HEADING "Max allocated bytes"
SELECT pid, category, allocated, used, max_allocated
FROM   v\$process_memory
WHERE  pid in (SELECT pid
              FROM   v\$process
              WHERE  addr in (select paddr
                            FROM   v\$session
                            WHERE  sid = &&s1));

exec dbms_lock.sleep(10)

SELECT pid, category, allocated, used, max_allocated
FROM   v\$process_memory
WHERE  pid in (SELECT pid
              FROM   v\$process
              WHERE  addr in (select paddr
                            FROM   v\$session
                            WHERE  sid = &&s1));

exec dbms_lock.sleep(10)

select pid from v\$process where addr in (select paddr from v\$session where username = 'C##MYUSER' and sid = (select max(sid) from v\$session where username = 'C##MYUSER'));

--
-- Save first pass of pga stats
--
CREATE TABLE tab1 AS
SELECT pid, category, name, heap_name, bytes, allocation_count,
       heap_descriptor, parent_heap_descriptor
FROM   v\$process_memory_detail
WHERE  pid      = &p_1
AND    category = 'Other';

--
-- Get second pass of pga stats
--
oradebug dump pga_detail_get &p_1
exec dbms_lock.sleep(120)

--
-- Save second pass of pga stats
--
CREATE TABLE tab2 AS
SELECT pid, category, name, heap_name, bytes, allocation_count,
       heap_descriptor, parent_heap_descriptor
FROM   v\$process_memory_detail
WHERE  pid      = &p_1
AND    category = 'Other';

--
-- Start final reports
--
-- PGA heap info
--
COLUMN category      HEADING "Category"
COLUMN name          HEADING "Name"
COLUMN heap_name     HEADING "Heap name"
COLUMN q1            HEADING "Memory 1st"  Format 999,999,999,999
COLUMN q2            HEADING "Memory 2nd"  Format 999,999,999,999
COLUMN diff          HEADING "Difference"  Format S999,999,999,999
SET LINES 150
SELECT tab2.pid, tab2.category, tab2.name, tab2.heap_name, tab1.bytes q1, tab2.bytes q2, tab2.bytes-tab1.bytes diff
FROM   tab1, tab2
WHERE  tab1.category  =  tab2.category
AND    tab1.name      =  tab2.name
AND    tab1.heap_name =  tab2.heap_name
and    tab1.pid       =  tab2.pid
AND    tab1.bytes     <> tab2.bytes
ORDER BY 1, 7 DESC;

--
-- Logminer PGA info
--
COLUMN heap_name        HEADING "heap name"
COLUMN name             HEADING "Type"
COLUMN allocation_count HEADING "Count"
COLUMN bytes            HEADING "Sum"
COLUMN avg              HEADING "Average" FORMAT 99999D99
SELECT pid, heap_name, name, allocation_count, bytes, bytes/allocation_count avg
FROM   tab2
WHERE  heap_name like 'Logminer%';

spool off
drop table tab1 purge;
drop table tab2 purge;
EOF