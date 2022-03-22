USE testDB;
EXEC sys.sp_cdc_disable_table @source_schema = 'dbo', @source_name = 'customers', @capture_instance = 'dbo_customers';
GO
