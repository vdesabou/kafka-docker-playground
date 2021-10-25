echo 'Creating CUSTOMERS table'

sqlplus MYUSER/password@//localhost:1521/XE  <<- EOF

create table CUSTOMERS (
        id NUMBER(10) NOT NULL PRIMARY KEY,
        first_name VARCHAR(50),
        last_name VARCHAR(50),
        email VARCHAR(50),
        gender VARCHAR(50),
        club_status VARCHAR(20),
        comments VARCHAR(90),
        create_ts timestamp DEFAULT CURRENT_TIMESTAMP,
        update_ts timestamp
);

ALTER TABLE CUSTOMERS ADD (
  CONSTRAINT CUSTOMERS_PK PRIMARY KEY (ID));

CREATE SEQUENCE CUSTOMERS_SEQ START WITH 1;

CREATE OR REPLACE TRIGGER CUSTOMERS_TRIGGER_ID
BEFORE INSERT ON CUSTOMERS
FOR EACH ROW

BEGIN
  SELECT CUSTOMERS_SEQ.NEXTVAL
  INTO   :new.id
  FROM   dual;
END;
/
EOF