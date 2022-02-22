-- Create the test database
CREATE DATABASE testDB;
GO
USE testDB;
EXEC sys.sp_cdc_enable_db;

-- Create some customers ...
CREATE TABLE customers (
  id INTEGER IDENTITY(1001,1) NOT NULL PRIMARY KEY,
  first_name VARCHAR(20) NOT NULL
);
INSERT INTO customers(first_name)
  VALUES ('Sally');
INSERT INTO customers(first_name)
  VALUES ('George');
INSERT INTO customers(first_name)
  VALUES ('Edward');
INSERT INTO customers(first_name)
  VALUES ('Anne');
GO
