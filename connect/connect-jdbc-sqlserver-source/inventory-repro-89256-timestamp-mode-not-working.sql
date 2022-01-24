-- Create the test database
CREATE DATABASE testDB;
GO
USE testDB;
EXEC sys.sp_cdc_enable_db;

-- Create some customers ...
CREATE TABLE customers (
  id INTEGER IDENTITY(1001,1) NOT NULL PRIMARY KEY,
  first_name VARCHAR(255) NOT NULL,
  last_name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  last_update DATETIME2
);
INSERT INTO customers(first_name,last_name,email,last_update)
  VALUES ('Sally','Thomas','sally.thomas@acme.com', GETDATE());
INSERT INTO customers(first_name,last_name,email,last_update)
  VALUES ('George','Bailey','gbailey@foobar.com', GETDATE());
INSERT INTO customers(first_name,last_name,email,last_update)
  VALUES ('Edward','Walker','ed@walker.com', GETDATE());
INSERT INTO customers(first_name,last_name,email,last_update)
  VALUES ('Anne','Kretchmar','annek@noanswer.org', GETDATE());
GO
