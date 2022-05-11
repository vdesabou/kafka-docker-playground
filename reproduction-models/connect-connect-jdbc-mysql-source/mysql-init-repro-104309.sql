CREATE DATABASE IF NOT EXISTS db;

USE db;

-- used for ssl case: tells the server to permit only encrypted connections
GRANT ALL PRIVILEGES ON *.* TO 'userssl'@'%' IDENTIFIED BY 'password' REQUIRE SSL;
-- used for mtls case: requires that clients present a valid certificate
GRANT ALL PRIVILEGES ON *.* TO 'usermtls'@'%' IDENTIFIED BY 'password' REQUIRE X509;

CREATE TABLE IF NOT EXISTS application (
  id            INT          NOT NULL PRIMARY KEY AUTO_INCREMENT,
  name          VARCHAR(255) NOT NULL,
  team_email    VARCHAR(255) NOT NULL,
  last_modified DATETIME     NOT NULL,
  myEpochTime   DATE         NOT NULL
);


INSERT INTO application (
  id,
  name,
  team_email,
  last_modified,
  myEpochTime
) VALUES (
  1,
  'kafka',
  'kafka@apache.org',
  NOW(),
  '2020-01-01 10:10:10'
);
