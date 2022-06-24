-- Create the test database
CREATE DATABASE testDB;
GO
USE testDB;
EXEC sys.sp_cdc_enable_db;

-- Create some customers ...
CREATE TABLE customers (
  f0 VARCHAR(20) NOT NULL PRIMARY KEY,
  f1 VARCHAR(20),
  f2 Binary(32)
);
GO
