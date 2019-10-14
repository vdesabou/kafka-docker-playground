CREATE USER myuser IDENTIFIED BY mypassword;

GRANT CONNECT,
      CREATE SESSION,
      CREATE TABLE,
      CREATE SEQUENCE,
      CREATE TRIGGER
   TO myuser;

ALTER USER myuser QUOTA 100M ON users;
ALTER DATABASE default tablespace users;
