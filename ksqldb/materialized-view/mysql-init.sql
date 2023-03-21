CREATE USER 'repl'@'localhost' IDENTIFIED BY 'password';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'localhost';

CREATE USER 'debezium'@'%' IDENTIFIED WITH mysql_native_password BY 'dbz';
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'debezium'@'%';
FLUSH PRIVILEGES;

CREATE DATABASE mydb;

GRANT ALL PRIVILEGES ON mydb.* TO 'debezium'@'%';


USE mydb;

CREATE TABLE calls (name TEXT, reason TEXT, duration_seconds INT);

INSERT INTO calls (name, reason, duration_seconds) VALUES ("michael", "purchase", 540);
INSERT INTO calls (name, reason, duration_seconds) VALUES ("michael", "help", 224);
INSERT INTO calls (name, reason, duration_seconds) VALUES ("colin", "help", 802);
INSERT INTO calls (name, reason, duration_seconds) VALUES ("derek", "purchase", 10204);
INSERT INTO calls (name, reason, duration_seconds) VALUES ("derek", "help", 600);
INSERT INTO calls (name, reason, duration_seconds) VALUES ("colin", "refund", 105);
INSERT INTO calls (name, reason, duration_seconds) VALUES ("michael", "help", 2030);
INSERT INTO calls (name, reason, duration_seconds) VALUES ("colin", "purchase", 800);
INSERT INTO calls (name, reason, duration_seconds) VALUES ("derek", "help", 2514);
INSERT INTO calls (name, reason, duration_seconds) VALUES ("derek", "refund", 325);

