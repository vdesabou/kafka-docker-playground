-- Create the test database
CREATE DATABASE testDB;
GO
USE testDB;
EXEC sys.sp_cdc_enable_db;

-- Create some customers ...
CREATE TABLE customers (
  field_no_optional INTEGER IDENTITY(1001,1) NOT NULL PRIMARY KEY,
  field_first_optional VARCHAR(255) NULL,
  field_second_optional INTEGER NULL,
  field_third_optional VARCHAR(255) NULL
);
INSERT INTO customers(field_first_optional,field_second_optional,field_third_optional)
  VALUES ('Sally',1,'sally.thomas@acme.com');
INSERT INTO customers(field_first_optional,field_second_optional,field_third_optional)
  VALUES ('George',1,'gbailey@foobar.com');
INSERT INTO customers(field_first_optional,field_second_optional,field_third_optional)
  VALUES ('Edward',1,'ed@walker.com');
INSERT INTO customers(field_first_optional,field_second_optional,field_third_optional)
  VALUES ('Anne',1,'annek@noanswer.org');
EXEC sys.sp_cdc_enable_table @source_schema = 'dbo', @source_name = 'customers', @role_name = NULL, @supports_net_changes = 0;
GO
