CREATE DATABASE IF NOT EXISTS mydb;

USE mydb;

-- Unable to load authentication plugin 'caching_sha2_password'
ALTER USER 'user'@'%' IDENTIFIED WITH mysql_native_password BY 'password';

-- used for ssl case: tells the server to permit only encrypted connections
CREATE USER 'userssl'@'%' IDENTIFIED WITH mysql_native_password BY 'password' REQUIRE SSL;
GRANT ALL PRIVILEGES ON *.* TO 'userssl'@'%';
-- used for mtls case: requires that clients present a valid certificate
CREATE USER 'usermtls'@'%' IDENTIFIED WITH mysql_native_password BY 'password' REQUIRE X509;
GRANT ALL PRIVILEGES ON *.* TO 'usermtls'@'%';
