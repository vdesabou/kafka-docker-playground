--
-- Copyright [2024 - 2025] Confluent Inc.
--

-- Confluent Oracle XStream CDC connector readiness script (version 1.0)
--
-- This script validates that all database pre-requisites for the Oracle XStream CDC connector as documented in the 'Oracle Database Prerequisites' section of the documentation are met.
--
-- This script does not make any modifications to the database.
--
-- Parameters
-- 1 - Capture database user (default: C##CFLTADMIN)
-- 2 - Connect database user (default: C##CFLTUSER)
-- 3 - Outbound server name (default: XOUT)
-- 4 - Pluggable database (PDB) name in case of multi-tenant database (default: NULL)

SET SERVEROUTPUT ON;
SET VERIFY OFF;
SET LINESIZE 300;

DECLARE
    -- Types
    TYPE varchar2_tt IS TABLE OF VARCHAR2(128);

    -- Constants
    k_db_version NUMBER := DBMS_DB_VERSION.VERSION;
    k_new_line VARCHAR2(10) := CHR(13) || CHR(10);
    k_docs_base_url VARCHAR2(1000) := 'https://docs.confluent.io/cloud/current/connectors/cc-oracle-xstream-cdc-source';

    -- Global variables
    g_capture_user DBA_USERS.USERNAME%TYPE := UPPER(NVL('&1', 'C##CFLTADMIN'));
    g_connect_user DBA_USERS.USERNAME%TYPE := UPPER(NVL('&2', 'C##CFLTUSER'));
    g_outbound_server DBA_XSTREAM_OUTBOUND.SERVER_NAME%TYPE := UPPER(NVL('&3', 'XOUT'));
    g_capture_process DBA_CAPTURE.CAPTURE_NAME%TYPE;
    g_pdb_name V$PDBS.NAME%TYPE := UPPER(NVL('&4', NULL));
    g_is_multitenant BOOLEAN;
    g_is_rac BOOLEAN;
    g_is_rds BOOLEAN;
    g_required_system_privs varchar2_tt := varchar2_tt('CREATE SESSION');

-- ### Define all functions and procedures ###

-- Quotes a string
FUNCTION quote(p_input IN VARCHAR2) RETURN VARCHAR2
IS
BEGIN
    RETURN '''' || p_input || '''';
END;

-- Constructs container prefix for messages
FUNCTION msg_container_prefix(p_container IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2
IS
BEGIN
    IF NOT g_is_multitenant THEN
        RETURN '';
    ELSIF p_container IS NULL THEN
        RETURN '(Container: CDB$ROOT) ';
    ELSE
        RETURN '(Container: ' || p_container || ') ';
    END IF;
END;

-- Logs exception
PROCEDURE log_exception(p_msg IN VARCHAR2, p_errcode IN NUMBER, p_errmsg IN VARCHAR2)
IS
BEGIN
    dbms_output.put_line('ERROR: ' || p_msg);
    dbms_output.put_line('Error code: ' || p_errcode || ', Message: ' || p_errmsg);
END;

-- Checks if current user has enough privilege to run the script
PROCEDURE check_dba_role
IS
    l_result NUMBER;
BEGIN
    SELECT 1
    INTO l_result
    FROM dual
    WHERE USER IN
    (
        SELECT GRANTEE
        FROM DBA_ROLE_PRIVS
        START WITH GRANTED_ROLE = 'DBA'
        CONNECT BY PRIOR GRANTEE = GRANTED_ROLE
    );
EXCEPTION
    WHEN no_data_found THEN
        RAISE_APPLICATION_ERROR(-20001, 'ERROR: Current user does not have DBA role. Please execute the script using a user having DBA role.');
    WHEN others THEN
        log_exception('Failed to check if current user has DBA role.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
        raise;
END;

-- Checks if DB architecture is Multitenant
FUNCTION is_db_multitenant RETURN BOOLEAN
IS
    l_is_cdb V$DATABASE.CDB%TYPE;
BEGIN
    SELECT CDB
    INTO l_is_cdb
    FROM V$DATABASE;

    IF l_is_cdb = 'YES' THEN
        dbms_output.put_line(k_new_line || 'Detected multitenant database architecture.');
        RETURN TRUE;
    ELSE
        dbms_output.put_line(k_new_line || 'Detected non-multitenant database architecture.');
        RETURN FALSE;
    END IF;
EXCEPTION
    WHEN others THEN
        log_exception('Failed to fetch database architecture type.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
        raise;
END;

-- Checks if the provided PDB exists
FUNCTION pdb_exists(p_pdb_name IN VARCHAR2) RETURN BOOLEAN
IS
    l_count NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO l_count
    FROM DBA_PDBS
    WHERE PDB_NAME = p_pdb_name;

    RETURN l_count > 0;
EXCEPTION
    WHEN others THEN
        log_exception('Failed to check if PDB ' || quote(p_pdb_name) || ' exists.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
        raise;
END;

-- Checks if database is RAC (Real Application Clusters) or single instance
FUNCTION is_db_rac RETURN BOOLEAN
IS
    l_is_rac BOOLEAN;
BEGIN
    l_is_rac := DBMS_UTILITY.IS_CLUSTER_DATABASE;
    IF l_is_rac THEN
        dbms_output.put_line(k_new_line || 'Detected RAC (Real Application Clusters) database.');
    ELSE
        dbms_output.put_line(k_new_line || 'Detected single instance database.');
    END IF;

    RETURN l_is_rac;
EXCEPTION
    WHEN others THEN
        log_exception('Failed to check if database is RAC (Real Application Clusters).', SQLCODE, SUBSTR(SQLERRM, 1, 128));
        RETURN FALSE;
END;

-- Checks if database is Amazon RDS
FUNCTION is_db_rds RETURN BOOLEAN
IS
    l_is_rdsadmin_package       NUMBER;
    l_is_rdsadmin_schema        NUMBER;
    l_has_rds_internal_objects  NUMBER;
    l_is_rds                    BOOLEAN := FALSE;
BEGIN
  -- Check if RDSADMIN schema exists
  SELECT COUNT(*) INTO l_is_rdsadmin_schema
  FROM DBA_USERS
  WHERE USERNAME = 'RDSADMIN';

  -- Check if RDSADMIN package exists
  SELECT COUNT(*)
  INTO l_is_rdsadmin_package
  FROM DBA_PROCEDURES
  WHERE OBJECT_TYPE = 'PACKAGE' AND OBJECT_NAME = 'RDSADMIN';

  l_is_rds := l_is_rdsadmin_schema > 0
               AND l_is_rdsadmin_package > 0;

  IF l_is_rds THEN
    DBMS_OUTPUT.PUT_LINE('Detected Amazon RDS for Oracle instance.');
  END IF;

  RETURN l_is_rds;
EXCEPTION
    WHEN others THEN
        log_exception('Failed to check if the database instance is running on Amazon RDS.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
        RETURN FALSE;
END;

-- Checks if XStream is enabled
PROCEDURE validate_xstream
IS
    l_db_xstream V$PARAMETER.VALUE%TYPE;
    l_xstream_docs_url VARCHAR2(1000) := k_docs_base_url || '/oracle-xstream-cdc-setup-includes/prereqs-validation.html#connect-oracle-xstream-cdc-source-prereqs-enable-xstream';
BEGIN
    dbms_output.put_line(k_new_line || 'Validating if XStream is enabled.');
    SELECT MIN(value)
    INTO l_db_xstream
    FROM GV$PARAMETER
    WHERE name = 'enable_goldengate_replication';

    IF l_db_xstream = 'TRUE' THEN
        dbms_output.put_line('SUCCESS: XStream is enabled.');
    ELSE
        dbms_output.put_line('FAILED: XStream is not enabled.');
        dbms_output.put_line('Please refer to the documentation for the procedure to enable XStream: ' || l_xstream_docs_url);
    END IF;
EXCEPTION
    WHEN others THEN
        log_exception('Failed to validate if XStream is enabled.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
END;

-- Checks if log mode is set to 'ARCHIVELOG'
PROCEDURE validate_log_mode
IS
    l_db_log_mode V$DATABASE.LOG_MODE%TYPE;
    l_log_mode_docs_url VARCHAR2(1000) := k_docs_base_url || '/oracle-xstream-cdc-setup-includes/prereqs-validation.html#configure-archivelog-mode';
BEGIN
    dbms_output.put_line(k_new_line || 'Validating database log mode.');
    SELECT LOG_MODE
    INTO l_db_log_mode
    FROM V$DATABASE;

    IF l_db_log_mode = 'ARCHIVELOG' THEN
        dbms_output.put_line('SUCCESS: Database is set to ''ARCHIVELOG'' mode.');
    ELSE
        dbms_output.put_line('FAILED: Database is not set to ''ARCHIVELOG'' mode. Current mode: ' || quote(l_db_log_mode) || '.');
        dbms_output.put_line('Please refer to the documentation for the procedure to set the database to ARCHIVELOG mode: ' || l_log_mode_docs_url);
    END IF;
EXCEPTION
    WHEN others THEN
        log_exception('Failed to validate database log mode.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
END;

-- Checks the archive log retention. Can only get it for Managed RDS at the moment.
PROCEDURE validate_archive_log_retention
IS
    l_retention_hours NUMBER;
    l_rds_docs_url varchar2(1000) := k_docs_base_url || '/oracle-xstream-cdc-setup-includes/prereqs-validation.html#configure-archivelog-mode-rds';
BEGIN
    dbms_output.put_line(k_new_line || 'Validating archive log retention period.');

    IF g_is_rds THEN
        -- Using execute immediate otherwise it will fail to compile for non RDS DBs
        EXECUTE IMMEDIATE 'SELECT value FROM rdsadmin.rds_configuration WHERE name =''archivelog retention hours''' INTO l_retention_hours;

        IF l_retention_hours < 24 THEN
            dbms_output.put_line('WARN: Archive log retention is set to ' || quote(l_retention_hours) || ' hours. Confluent recommends setting the archive log retention to at least 24 hours.');
            dbms_output.put_line('Please refer to the documentation for steps to configure archive log retention: ' || l_rds_docs_url);
        ELSE
            dbms_output.put_line('SUCCESS: ARCHIVELOG mode is enabled, and archive log retention is set to ' || quote(l_retention_hours) || ' hours.');
        END IF;
    ELSE
        dbms_output.put_line('INFO: Confluent recommends that archive logs be retained for at least 24 hours.');
    END IF;
EXCEPTION
    WHEN others THEN
        log_exception('Failed to fetch archive log retention.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
END;

-- Checks if supplemental logs is enabled or not
PROCEDURE validate_supplemental_logging
IS
    l_supp_log_min V$DATABASE.SUPPLEMENTAL_LOG_DATA_MIN%TYPE;
    l_supp_log_all V$DATABASE.SUPPLEMENTAL_LOG_DATA_ALL%TYPE;
    l_supp_docs_url VARCHAR2(1000) := k_docs_base_url || '/oracle-xstream-cdc-setup-includes/prereqs-validation.html#configure-supplemental-logging';
BEGIN
    dbms_output.put_line(k_new_line || 'Validating supplemental logging.');
    SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_ALL
    INTO l_supp_log_min, l_supp_log_all
    FROM V$DATABASE;

    IF l_supp_log_all = 'YES' THEN
        dbms_output.put_line('WARN: ''ALL COLUMN'' supplemental logging is enabled at the database level. Confluent recommends enabling minimal supplemental logging at the database level and ''ALL COLUMN'' supplemental logging for the specific tables that require change data capture.');
        dbms_output.put_line('Please refer to the documentation for the procedure to enable supplemental logging: ' || l_supp_docs_url);
    ELSIF l_supp_log_min = 'NO' THEN
        dbms_output.put_line('FAILED: Minimal supplemental logging is not enabled and is required for the connector to function. Confluent recommends enabling minimal supplemental logging at the database level and ''ALL COLUMN'' supplemental logging for the specific tables that require change data capture.');
        dbms_output.put_line('Please refer to the documentation for the procedure to enable supplemental logging: ' || l_supp_docs_url);
    ELSE
        dbms_output.put_line('INFO: Please ensure that ''ALL COLUMN'' supplemental logging is enabled for the specific tables that require change data capture.');
        dbms_output.put_line('Please refer to the documentation for the procedure to enable supplemental logging: ' || l_supp_docs_url);
    END IF;
EXCEPTION
    WHEN others THEN
        log_exception('Failed to validate supplemental logging.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
END;

-- Populates required system privileges based on architecture
PROCEDURE init_required_sys_privs
IS
BEGIN
    IF g_is_multitenant AND g_pdb_name IS NOT NULL THEN
        g_required_system_privs := g_required_system_privs MULTISET UNION varchar2_tt('SET CONTAINER');
    END IF;
END;

-- Checks if the provided database user exists
FUNCTION user_exists(p_user IN VARCHAR2) RETURN BOOLEAN
IS
    l_count NUMBER;
    l_docs_url VARCHAR2(1000) := k_docs_base_url || '/oracle-xstream-cdc-setup-includes/prereqs-validation.html#configure-database-users';
BEGIN
    dbms_output.put_line(k_new_line || 'Validating if the database user ' || quote(p_user) || ' exists.');

    IF g_is_multitenant THEN
        SELECT COUNT(*)
        INTO l_count
        FROM DBA_USERS
        WHERE USERNAME = p_user
        AND COMMON = 'YES';

        IF l_count > 0 THEN
            dbms_output.put_line('SUCCESS: The database user ' || quote(p_user) || ' exists and is a common user.');
            RETURN TRUE;
        ELSE
            dbms_output.put_line('FAILED: The database user ' || quote(p_user) || ' does not exist or is not a common user.');
            dbms_output.put_line('Please refer to the documentation for the steps to create and configure the database user: ' || l_docs_url);
            RETURN FALSE;
        END IF;
    ELSE
        SELECT COUNT(*)
        INTO l_count
        FROM DBA_USERS
        WHERE USERNAME = p_user;

        IF l_count > 0 THEN
            dbms_output.put_line('SUCCESS: The database user ' || quote(p_user) || ' exists.');
            RETURN TRUE;
        ELSE
            dbms_output.put_line('FAILED: The database user ' || quote(p_user) || ' does not exist.');
            dbms_output.put_line('Please refer to the documentation for the steps to create and configure the database user: ' || l_docs_url);
            RETURN FALSE;
        END IF;
    END IF;
EXCEPTION
    WHEN others THEN
        log_exception('Failed to validate if the database user ' || quote(p_user) || ' exists.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
        raise;
END;

-- Checks if a user has a specific system privilege in the given container
FUNCTION has_system_privilege(p_privilege IN VARCHAR2, p_user IN VARCHAR2, p_container IN VARCHAR2 DEFAULT NULL) RETURN BOOLEAN
IS
    l_count NUMBER;
BEGIN
    IF p_container IS NULL THEN
        SELECT COUNT(*)
        INTO l_count
        FROM DBA_SYS_PRIVS dsp
        WHERE dsp.PRIVILEGE = p_privilege
        AND (
            GRANTEE = p_user OR GRANTEE IN (
                SELECT GRANTED_ROLE
                FROM DBA_ROLE_PRIVS
                CONNECT BY PRIOR GRANTED_ROLE = GRANTEE
                START WITH GRANTEE = p_user
            )
        );
    ELSE
        SELECT COUNT(*)
        INTO l_count
        FROM CDB_SYS_PRIVS
        WHERE PRIVILEGE = p_privilege
        AND CON_ID = CON_NAME_TO_ID(p_container)
        AND (
            GRANTEE = p_user OR GRANTEE IN (
                SELECT GRANTED_ROLE
                FROM CDB_ROLE_PRIVS
                WHERE CON_ID = CON_NAME_TO_ID(p_container)
                CONNECT BY PRIOR GRANTED_ROLE = GRANTEE AND PRIOR CON_ID = CON_ID
                START WITH GRANTEE = p_user
            )
        );
    END IF;

    RETURN l_count > 0;
END;

-- Checks if user has all the required system privileges in place
PROCEDURE validate_system_privileges(p_user IN VARCHAR2)
IS
    l_docs_url VARCHAR2(1000) := k_docs_base_url || '/oracle-xstream-cdc-setup-includes/prereqs-validation.html#configure-database-users';
    l_containers varchar2_tt := varchar2_tt(NULL);
BEGIN
    l_containers(1) := NULL;
    IF g_is_multitenant AND g_pdb_name IS NOT NULL THEN
        l_containers.EXTEND;
        l_containers(2) := g_pdb_name;
    END IF;

    FOR c_idx IN 1..l_containers.COUNT LOOP
        FOR p_idx IN 1..g_required_system_privs.COUNT LOOP
            dbms_output.put_line(k_new_line || msg_container_prefix(l_containers(c_idx)) || 'Validating ' || quote(g_required_system_privs(p_idx)) || ' privilege for database user ' || quote(p_user) || '.');
            IF has_system_privilege(g_required_system_privs(p_idx), p_user, l_containers(c_idx)) THEN
                dbms_output.put_line('SUCCESS: ' || msg_container_prefix(l_containers(c_idx)) || 'Database user ' || quote(p_user) || ' has the required system privilege ' || quote(g_required_system_privs(p_idx)) || '.');
            ELSE
                dbms_output.put_line('FAILED: ' || msg_container_prefix(l_containers(c_idx)) || 'Database user ' || quote(p_user) || ' is missing the required system privilege ' || quote(g_required_system_privs(p_idx)) || '.');
                dbms_output.put_line('Please refer to the documentation for steps to grant this access: ' || l_docs_url);
            END IF;
        END LOOP;
    END LOOP;
EXCEPTION
    WHEN others THEN
        log_exception('Failed to validate system privileges for database user ' || quote(p_user) || '.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
END;

-- Checks if capture user has been granted privileges to be an XStream administrator
PROCEDURE validate_xstream_admin
IS
    l_count NUMBER;
    l_xstream_admin_docs_url VARCHAR2(1000) := k_docs_base_url || '/oracle-xstream-cdc-setup-includes/prereqs-validation.html#configure-database-users';
BEGIN
    dbms_output.put_line(k_new_line || 'Validating XStream administrator privileges for database user ' || quote(g_capture_user) || '.');
    SELECT COUNT(*)
    INTO l_count
    FROM DBA_XSTREAM_ADMINISTRATOR
    WHERE USERNAME = g_capture_user
    AND PRIVILEGE_TYPE = 'CAPTURE'
    AND GRANT_SELECT_PRIVILEGES = 'YES';

    IF l_count > 0 THEN
        dbms_output.put_line('SUCCESS: Database user ' || quote(g_capture_user) || ' has the required XStream administrator privileges.');
    ELSE
        dbms_output.put_line('FAILED: Database user ' || quote(g_capture_user) || ' does not have the required XStream administrator privileges.');
        dbms_output.put_line('Please refer to the documentation for steps to grant XStream administrator privileges: ' || l_xstream_admin_docs_url);
    END IF;
EXCEPTION
    WHEN others THEN
        log_exception('Failed to validate XStream administrator privileges for database user ' || quote(g_capture_user) || '.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
END;

-- Checks if a user has the specified role in the given container
FUNCTION has_role(p_role IN VARCHAR2, p_user IN VARCHAR2, p_container IN VARCHAR2 DEFAULT NULL) RETURN BOOLEAN
IS
    l_count NUMBER;
BEGIN
    IF p_container IS NULL THEN
        SELECT COUNT(*)
        INTO l_count
        FROM DBA_ROLE_PRIVS
        WHERE GRANTED_ROLE = p_role
        CONNECT BY PRIOR GRANTED_ROLE = GRANTEE
        START WITH GRANTEE = p_user;
    ELSE
        SELECT COUNT(*)
        INTO l_count
        FROM CDB_ROLE_PRIVS
        WHERE GRANTED_ROLE = p_role AND CON_ID = CON_NAME_TO_ID(p_container)
        CONNECT BY PRIOR GRANTED_ROLE = GRANTEE AND PRIOR CON_ID = CON_ID
        START WITH GRANTEE = p_user AND CON_ID = CON_NAME_TO_ID(p_container);
    END IF;

    RETURN l_count > 0;
END;

-- Checks if connect user has 'SELECT_CATALOG_ROLE'
PROCEDURE validate_select_catalog_role
IS
    l_privs_docs_url VARCHAR2(1000) := k_docs_base_url || '/oracle-xstream-cdc-setup-includes/prereqs-validation.html#configure-database-users';
    l_container VARCHAR2(128) := CASE WHEN g_pdb_name IS NOT NULL THEN g_pdb_name ELSE NULL END;
BEGIN
    dbms_output.put_line(k_new_line || 'Validating ''SELECT_CATALOG_ROLE'' role for database user ' || quote(g_connect_user) || '.');

    IF has_role('SELECT_CATALOG_ROLE', g_connect_user, l_container) THEN
        dbms_output.put_line('SUCCESS: ' || msg_container_prefix(l_container) || 'Database user ' || quote(g_connect_user) || ' has ''SELECT_CATALOG_ROLE'' role.');
    ELSE
        dbms_output.put_line('FAILED: ' || msg_container_prefix(l_container) || 'Database user ' || quote(g_connect_user) || ' is missing ''SELECT_CATALOG_ROLE'' role.');
        dbms_output.put_line('Please refer to the documentation for steps to grant this role: ' || l_privs_docs_url);
    END IF;
EXCEPTION
    WHEN others THEN
        log_exception('Failed to validate ''SELECT_CATALOG_ROLE'' role for database user ' || quote(g_connect_user) || '.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
END;

-- Checks the user privileges for snapshot
PROCEDURE validate_snapshot_privileges
IS
    l_docs_url VARCHAR2(1000) := k_docs_base_url || '/oracle-xstream-cdc-setup-includes/prereqs-validation.html#configure-database-users';
    l_container VARCHAR2(128) := CASE WHEN g_pdb_name IS NOT NULL THEN g_pdb_name ELSE NULL END;
BEGIN
    dbms_output.put_line(k_new_line || 'Validating snapshot privileges for database user ' || quote(g_connect_user) || '.');

    IF has_system_privilege('SELECT ANY TABLE', g_connect_user, l_container) AND has_system_privilege('LOCK ANY TABLE', g_connect_user, l_container) THEN
        dbms_output.put_line('SUCCESS: ' || msg_container_prefix(l_container) || 'Database user ' || quote(g_connect_user) || ' has the required system privileges ''SELECT ANY TABLE'' and ''LOCK ANY TABLE''.');
    ELSE
        dbms_output.put_line('INFO: ' || msg_container_prefix(l_container) || 'Database user ' || quote(g_connect_user) || ' does not have the ''SELECT ANY TABLE'' and ''LOCK ANY TABLE'' system privileges. Either grant these system privileges or grant the ''SELECT'' object privilege on the tables included in the capture set.');
        dbms_output.put_line('Please refer to the documentation for the steps to grant this access: ' || l_docs_url);
    END IF;

    IF has_system_privilege('FLASHBACK ANY TABLE', g_connect_user, l_container) THEN
        dbms_output.put_line('SUCCESS: ' || msg_container_prefix(l_container) || 'Database user ' || quote(g_connect_user) || ' has the system privilege ''FLASHBACK ANY TABLE'' required to snapshot table data.');
    ELSE
        dbms_output.put_line('INFO: ' || msg_container_prefix(l_container) || 'Database user ' || quote(g_connect_user) || ' does not have the ''FLASHBACK ANY TABLE'' system privilege. Either grant this system privilege or grant the ''FLASHBACK'' object privilege on the tables included in the capture set if the connector is configured to snapshot table data.');
        dbms_output.put_line('Please refer to the documentation for the steps to grant this access: ' || l_docs_url);
    END IF;
EXCEPTION
    WHEN others THEN
        log_exception('Failed to validate snapshot privileges.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
END;

-- Checks the outbound server details
PROCEDURE validate_outbound_server
IS
    l_connect_user DBA_XSTREAM_OUTBOUND.CONNECT_USER%TYPE;
    l_capture_name DBA_XSTREAM_OUTBOUND.CAPTURE_NAME%TYPE;
    l_status DBA_XSTREAM_OUTBOUND.STATUS%TYPE;
    l_docs_url VARCHAR2(1000) := k_docs_base_url || '/oracle-xstream-cdc-setup-includes/prereqs-validation.html#create-xstream-out';
BEGIN
    dbms_output.put_line(k_new_line || 'Validating outbound server: ' || quote(g_outbound_server));
    SELECT CONNECT_USER, CAPTURE_NAME, STATUS
    INTO l_connect_user, l_capture_name, l_status
    FROM DBA_XSTREAM_OUTBOUND
    WHERE SERVER_NAME = g_outbound_server;

    IF l_connect_user != g_connect_user THEN
        dbms_output.put_line('FAILED: The connect user ' || quote(l_connect_user) || ' for outbound server ' || quote(g_outbound_server) || ' does not match the connect user ' || quote(g_connect_user) || ' provided in the input.');
        dbms_output.put_line('Please refer to the documentation for the steps to change the connect user for the outbound server: ' || l_docs_url);
    END IF;

    g_capture_process := l_capture_name;

    IF g_capture_process IS NULL THEN
        dbms_output.put_line('WARN: The outbound server ' || quote(g_outbound_server) || ' does not have an associated capture process.');
    END IF;

    IF l_status = 'ABORTED' THEN
        dbms_output.put_line('FAILED: The outbound server is in ''ABORTED'' status due to an error.');
        dbms_output.put_line('To view details, run the following query on the ''DBA_APPLY'' view: ''SELECT STATUS, ERROR_NUMBER, ERROR_MESSAGE FROM DBA_APPLY WHERE PURPOSE = ''XStream Out'' AND APPLY_NAME = ' || quote(g_outbound_server) || '''');
    ELSIF l_status = 'DISABLED' THEN
        dbms_output.put_line('INFO: The outbound server is currently in ''DISABLED'' status and not running.');
        dbms_output.put_line('You can start the outbound server manually using the ''DBMS_XSTREAM_ADM.START_OUTBOUND'' procedure, or it will start automatically when the connector attaches to it during startup.');
    ELSE
        dbms_output.put_line('SUCCESS: The outbound server has been successfully validated.');
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        dbms_output.put_line('FAILED: The outbound server ' || quote(g_outbound_server) || ' does not exist.');
        dbms_output.put_line('Please refer to the documentation for the steps to set up the outbound server: ' || l_docs_url);
    WHEN others THEN
        log_exception('Failed to validate outbound server ' || quote(g_outbound_server) || '.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
END;

-- Checks the capture process details
PROCEDURE validate_capture_process
IS
    l_capture_user DBA_CAPTURE.CAPTURE_USER%TYPE;
    l_status DBA_CAPTURE.STATUS%TYPE;
    l_docs_url VARCHAR2(1000) := k_docs_base_url || '/oracle-xstream-cdc-setup-includes/prereqs-validation.html#create-xstream-out';
BEGIN
    dbms_output.put_line(k_new_line || 'Validating capture process: ' || quote(g_capture_process));
    SELECT CAPTURE_USER, STATUS
    INTO l_capture_user, l_status
    FROM DBA_CAPTURE
    WHERE CAPTURE_NAME = g_capture_process;

    IF l_capture_user != g_capture_user THEN
        dbms_output.put_line('FAILED: The capture user ' || quote(l_capture_user) || ' for capture process ' || quote(g_capture_process) || ' does not match the capture user ' || quote(g_capture_user) || ' provided in the input.');
        dbms_output.put_line('Please refer to the documentation for the steps to change the capture user for the capture process: ' || l_docs_url);
    END IF;

    IF l_status = 'ABORTED' THEN
        dbms_output.put_line('FAILED: The capture process is in ''ABORTED'' status due to an error.');
        dbms_output.put_line('To view details, run the following query on the ''DBA_CAPTURE'' view: ''SELECT STATUS, ERROR_NUMBER, ERROR_MESSAGE FROM DBA_CAPTURE WHERE PURPOSE = ''XStream Out'' AND CAPTURE_NAME = ' || quote(g_capture_process) || '''');
    ELSIF l_status = 'DISABLED' THEN
        dbms_output.put_line('INFO: The capture process is currently in ''DISABLED'' status and not running.');
        dbms_output.put_line('You can start the capture process manually using the ''DBMS_CAPTURE_ADM.START_CAPTURE'' procedure, or it may start automatically when the connector attaches to it during startup.');
    ELSE
        dbms_output.put_line('SUCCESS: The capture process has been successfully validated.');
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        dbms_output.put_line('FAILED: The capture process ' || quote(g_capture_process) || ' does not exist.');
        dbms_output.put_line('Please refer to the documentation for the steps to set up the capture process: ' || l_docs_url);
    WHEN others THEN
        log_exception('Failed to validate capture process ' || quote(g_capture_process) || '.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
END;

-- Checks if the 'USE_RAC_SERVICE' parameter is enabled for the capture process (only on RAC databases)
PROCEDURE validate_rac_enabled
IS
    l_rac_service_enabled DBA_CAPTURE_PARAMETERS.VALUE%TYPE;
    l_docs_url VARCHAR2(1000) := k_docs_base_url || '/oracle-xstream-cdc-setup-includes/prereqs-validation.html#capture-changes-from-oracle-rac';
BEGIN
    dbms_output.put_line(k_new_line || 'Validating if the ''USE_RAC_SERVICE'' parameter is enabled for the capture process ' || quote(g_capture_process) || '.');
    SELECT VALUE
    INTO l_rac_service_enabled
    FROM DBA_CAPTURE_PARAMETERS
    WHERE CAPTURE_NAME = g_capture_process
    AND PARAMETER = 'USE_RAC_SERVICE';

    IF l_rac_service_enabled = 'N' THEN
        dbms_output.put_line('FAILED: The capture parameter ''USE_RAC_SERVICE'' is not set to ''Y'' for the capture process ' || quote(g_capture_process) || '.');
        dbms_output.put_line('Please refer to the documentation for the steps to capture changes from an Oracle RAC database: ' || l_docs_url);
    ELSE
        dbms_output.put_line('SUCCESS: The capture parameter ''USE_RAC_SERVICE'' is set to ''Y'' for the capture process ' || quote(g_capture_process) || '.');
    END IF;
EXCEPTION
    WHEN others THEN
        log_exception('Failed to validate if the ''USE_RAC_SERVICE'' parameter is enabled for the capture process ' || quote(g_capture_process) || '.', SQLCODE, SUBSTR(SQLERRM, 1, 128));
END;

-- MAIN SCRIPT
BEGIN
    dbms_output.put_line('Running prerequisite checks for the connector on Oracle Database ' || quote(k_db_version) || ' for the XStream capture user ' || quote(g_capture_user) || ' and connect user ' || quote(g_connect_user) || '.');

    IF k_db_version < 19 OR k_db_version >= 23 THEN
        dbms_output.put_line('FAILED: The connector does not support Oracle Database version: ' || quote(k_db_version) || '.');
        dbms_output.put_line('Please refer to the documentation for supported database versions: ' || k_docs_base_url || '/cc-oracle-xstream-cdc-source.html#supported-versions');
        RETURN;
    END IF;

    check_dba_role();

    g_is_rds := is_db_rds();

    g_is_multitenant := is_db_multitenant();

    IF g_is_rds AND g_is_multitenant THEN
      dbms_output.put_line('FAILED: The connector does not support container databases (CDB) on Amazon RDS for Oracle.');
      RETURN;
    END IF;

    IF g_is_multitenant AND g_pdb_name IS NOT NULL THEN
        IF pdb_exists(g_pdb_name) THEN
            dbms_output.put_line('Using Pluggable Database (PDB) name: ' || quote(g_pdb_name) || '.');
        ELSE
            dbms_output.put_line('FAILED: The Pluggable Database (PDB) name ' || quote(g_pdb_name) || ' does not exist in the database.');
            dbms_output.put_line('Please verify that the specified PDB name is correct and present in the database.');
            RETURN;
        END IF;
    ELSIF g_pdb_name IS NOT NULL THEN
        g_pdb_name := NULL;
    END IF;

    g_is_rac := is_db_rac();

    validate_xstream();
    validate_log_mode();
    validate_supplemental_logging();
    validate_archive_log_retention();

    init_required_sys_privs();

    IF user_exists(g_capture_user) THEN
        validate_system_privileges(g_capture_user);
        validate_xstream_admin();
    END IF;

    IF user_exists(g_connect_user) THEN
        validate_system_privileges(g_connect_user);
        validate_select_catalog_role();
        validate_snapshot_privileges();
    END IF;

    validate_outbound_server();

    IF g_capture_process IS NOT NULL THEN
        validate_capture_process();

        IF g_is_rac THEN
            validate_rac_enabled();
        END IF;
    END IF;

    dbms_output.put_line(k_new_line || 'Finished script execution.');
END;
/