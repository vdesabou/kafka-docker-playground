CREATE STREAM ORDERS (
    id VARCHAR,
    timestamp VARCHAR,
    amount DOUBLE,
    customer STRUCT<firstName VARCHAR,
                    lastName VARCHAR,
                    phoneNumber VARCHAR,
                    address STRUCT<street VARCHAR,
                                   number VARCHAR,
                                   zipcode VARCHAR,
                                   city VARCHAR,
                                   state VARCHAR>>,
    product STRUCT<sku VARCHAR,
                   name VARCHAR,
                   vendor STRUCT<vendorName VARCHAR,
                                 country VARCHAR>>)
    WITH (KAFKA_TOPIC = 'ORDERS',
          VALUE_FORMAT = 'JSON',
          TIMESTAMP = 'TIMESTAMP',
          TIMESTAMP_FORMAT = 'yyyy-MM-dd HH:mm:ss',
          PARTITIONS = 1, REPLICAS = 1);

CREATE STREAM FLATTENED_ORDERS AS
    SELECT
        ID AS ORDER_ID,
        TIMESTAMP AS ORDER_TS,
        AMOUNT AS ORDER_AMOUNT,
        CUSTOMER->FIRSTNAME AS CUST_FIRST_NAME,
        CUSTOMER->LASTNAME AS CUST_LAST_NAME,
        CUSTOMER->PHONENUMBER AS CUST_PHONE_NUMBER,
        CUSTOMER->ADDRESS->STREET AS CUST_ADDR_STREET,
        CUSTOMER->ADDRESS->NUMBER AS CUST_ADDR_NUMBER,
        CUSTOMER->ADDRESS->ZIPCODE AS CUST_ADDR_ZIPCODE,
        CUSTOMER->ADDRESS->CITY AS CUST_ADDR_CITY,
        CUSTOMER->ADDRESS->STATE AS CUST_ADDR_STATE,
        PRODUCT->SKU AS PROD_SKU,
        PRODUCT->NAME AS PROD_NAME,
        PRODUCT->VENDOR->VENDORNAME AS PROD_VENDOR_NAME,
        PRODUCT->VENDOR->COUNTRY AS PROD_VENDOR_COUNTRY
    FROM
        ORDERS
    PARTITION BY ID;