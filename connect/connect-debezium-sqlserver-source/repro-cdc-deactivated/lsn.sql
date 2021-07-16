USE testDB;
SELECT sys.fn_cdc_get_min_lsn ('dbo_customers')AS min_lsn;
SELECT sys.fn_cdc_get_max_lsn()AS max_lsn;
GO
