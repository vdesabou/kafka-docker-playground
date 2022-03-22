#!/bin/sh

echo 'Creating CUSTOMERS table in CDB'

sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLCDB  <<- EOF

  create table CUSTOMERS (
          "TATXA1" NCHAR(10),
          "TAITM" NUMBER,
          "TAEFDJ" NUMBER(6,0),
          first_name VARCHAR(50),
          last_name VARCHAR(50),
          email VARCHAR(50),
          gender VARCHAR(50),
          club_status VARCHAR(20),
          comments VARCHAR(90),
          create_ts timestamp DEFAULT CURRENT_TIMESTAMP ,
          update_ts timestamp
  );

  CREATE OR REPLACE TRIGGER TRG_CUSTOMERS_UPD
  BEFORE INSERT OR UPDATE ON CUSTOMERS
  REFERENCING NEW AS NEW_ROW
    FOR EACH ROW
  BEGIN
    SELECT SYSDATE
          INTO :NEW_ROW.UPDATE_TS
          FROM DUAL;
  END;
  /
  CREATE UNIQUE INDEX "CUSTOMERS_0" ON CUSTOMERS ("TATXA1", "TAITM", "TAEFDJ")  ; 
  ALTER TABLE CUSTOMERS ADD CONSTRAINT "CUSTOMERS_PK" PRIMARY KEY ("TATXA1", "TAITM", "TAEFDJ") USING INDEX "CUSTOMERS_0"  ENABLE NOVALIDATE; 

EOF

