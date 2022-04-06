USE testDB;
ALTER TABLE master.dbo.customers ADD phone_number VARCHAR(32) NOT NULL default 'test';
GO
