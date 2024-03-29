DROP TABLE IF EXISTS `customers`;
CREATE EXTERNAL TABLE CUSTOMERS (
  id INT,
  first_name STRING,
  last_name STRING,
  email STRING,
  gender STRING,
  club_status STRING,
  comments STRING,
  create_ts timestamp,
  update_ts timestamp
) LOCATION 's3://pgbucketvsaboulin/athena';


insert into CUSTOMERS (id, first_name, last_name, email, gender, club_status, comments, update_ts) values (1, 'Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy',current_timestamp);
