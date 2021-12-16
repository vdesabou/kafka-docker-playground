GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replicator' IDENTIFIED BY 'replpass';

GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT  ON *.* TO 'debezium' IDENTIFIED BY 'dbz';


CREATE DATABASE mydb;

GRANT ALL PRIVILEGES ON mydb.* TO 'user'@'%';

USE mydb;

CREATE TABLE outboxevent (
  id varchar(255) NOT NULL,
  aggregatetype varchar(255) NULL,
  aggregateid varchar(255) NULL,
  type varchar(255) NULL,
  payload varbinary(4000) NOT NULL,
  PRIMARY KEY (id)
);

INSERT INTO outboxevent (
  id,
  aggregatetype,
  aggregateid,
  type,
  payload
) VALUES (
  '406c07f3-26f0-4eea-a50c-109940064b8f',
  'Order',
  '1',
  'OrderCreated',
  0x12345
);