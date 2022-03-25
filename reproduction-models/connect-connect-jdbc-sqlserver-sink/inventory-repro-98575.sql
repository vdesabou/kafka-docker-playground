-- Create the test database
CREATE DATABASE testDB;
GO
USE testDB;
EXEC sys.sp_cdc_enable_db;

-- Create some customers ...
CREATE TABLE customers (id INTEGER IDENTITY(1,1) NOT NULL, first_name VARCHAR(20) NOT NULL, CONSTRAINT [ID_PK] PRIMARY KEY CLUSTERED (id ASC) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY] ) ON [PRIMARY];

INSERT INTO customers(first_name)
  VALUES ('Sally');
INSERT INTO customers(first_name)
  VALUES ('George');
INSERT INTO customers(first_name)
  VALUES ('Edward');
INSERT INTO customers(first_name)
  VALUES ('Anne');

GO
