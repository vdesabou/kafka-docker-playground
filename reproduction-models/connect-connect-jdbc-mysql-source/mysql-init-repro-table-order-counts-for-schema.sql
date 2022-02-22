CREATE DATABASE IF NOT EXISTS db;

USE db;

-- team_email is before name
CREATE TABLE IF NOT EXISTS application (
  id            INT          NOT NULL PRIMARY KEY AUTO_INCREMENT,
  team_email    VARCHAR(255) NOT NULL,
  name          VARCHAR(255) NOT NULL,
  last_modified DATETIME     NOT NULL
);

-- team_email is before name
INSERT INTO application (
  id,
  team_email,
  name,
  last_modified
) VALUES (
  1,
  'kafka@apache.org',
  'kafka',
  NOW()
);
