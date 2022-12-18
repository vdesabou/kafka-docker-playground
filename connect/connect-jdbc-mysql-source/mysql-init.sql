CREATE DATABASE IF NOT EXISTS mydb;

USE mydb;

-- used for ssl case: tells the server to permit only encrypted connections
GRANT ALL PRIVILEGES ON *.* TO 'userssl'@'%' IDENTIFIED BY 'password' REQUIRE SSL;
-- used for mtls case: requires that clients present a valid certificate
GRANT ALL PRIVILEGES ON *.* TO 'usermtls'@'%' IDENTIFIED BY 'password' REQUIRE X509;
