SHOW SCHEMAS FROM bronze;
SHOW SCHEMAS FROM bench;


SHOW TABLES FROM bench.lakehouse;


SELECT count(*) AS source_rows
FROM bronze.lakehouse.lineitem ;

select * from bronze.lakehouse.raw_sales ;


SELECT *
FROM bronze.lakehouse.raw_sales
LIMIT 10;

DROP TABLE IF EXISTS bench.lakehouse.q10_gzip_customers;
DROP TABLE IF EXISTS bench.lakehouse.q10_gzip_orders;
DROP TABLE IF EXISTS bench.lakehouse.q10_gzip_lineitem;
DROP TABLE IF EXISTS bench.lakehouse.q10_gzip_nation;

DROP TABLE IF EXISTS bench.lakehouse.q10_zstd_customers;
DROP TABLE IF EXISTS bench.lakehouse.q10_zstd_orders;
DROP TABLE IF EXISTS bench.lakehouse.q10_zstd_lineitem;
DROP TABLE IF EXISTS bench.lakehouse.q10_zstd_nation;


SET SESSION bench.compression_codec = 'GZIP';

CREATE TABLE bench.lakehouse.q10_gzip_customers
WITH (format = 'PARQUET')
AS SELECT * FROM bronze.lakehouse.customer;

CREATE TABLE bench.lakehouse.q10_gzip_orders
WITH (format = 'PARQUET')
AS SELECT * FROM bronze.lakehouse.orders;

CREATE TABLE bench.lakehouse.q10_gzip_lineitem
WITH (format = 'PARQUET')
AS SELECT * FROM bronze.lakehouse.lineitem;

CREATE TABLE bench.lakehouse.q10_gzip_nation
WITH (format = 'PARQUET')
AS SELECT * FROM bronze.lakehouse.nation;


SET SESSION bench.compression_codec = 'ZSTD';

CREATE TABLE bench.lakehouse.q10_zstd_customers
WITH (format = 'PARQUET')
AS SELECT * FROM bronze.lakehouse.customer;

CREATE TABLE bench.lakehouse.q10_zstd_orders
WITH (format = 'PARQUET')
AS SELECT * FROM bronze.lakehouse.orders;

CREATE TABLE bench.lakehouse.q10_zstd_lineitem
WITH (format = 'PARQUET')
AS SELECT * FROM bronze.lakehouse.lineitem;

CREATE TABLE bench.lakehouse.q10_zstd_nation
WITH (format = 'PARQUET')
AS SELECT * FROM bronze.lakehouse.nation;




select 
    c.custkey,
    c.name,
    sum(l.extendedprice * (1 - l.discount)) AS revenue,
    c.acctbal,
    n.name AS nation,
    c.address,
    c.phone,
    c.comment
FROM bench.lakehouse.q10_gzip_customers c
JOIN bench.lakehouse.q10_gzip_orders o
    ON c.custkey = o.custkey
JOIN bench.lakehouse.q10_gzip_lineitem l
    ON o.orderkey = l.orderkey
JOIN bench.lakehouse.q10_gzip_nation n
    ON c.nationkey = n.nationkey
WHERE o.orderdate >= DATE '1993-10-01'
  AND o.orderdate < DATE '1994-01-01'
  AND l.returnflag = 'R'
GROUP BY
    c.custkey,
    c.name,
    c.acctbal,
    c.address,
    c.phone,
    c.comment,
    n.name
ORDER BY revenue DESC
LIMIT 20;

