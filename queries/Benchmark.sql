CREATE SCHEMA IF NOT EXISTS bench.lakehouse;


CREATE TABLE bench.lakehouse.orders_gzip
WITH (
    format = 'PARQUET',
    compression_codec = 'GZIP'
)
AS
SELECT *
FROM tpch.sf1.orders;
SELECT 'GZIP' AS codec, COUNT(*) AS row_count
FROM bench.gzip.orders

UNION ALL

SELECT 'ZSTD' AS codec, COUNT(*) AS row_count
FROM bench.zstd.orders;


CREATE TABLE bench.lakehouse.orders_zstd
WITH (
    format = 'PARQUET',
    compression_codec = 'ZSTD'
)
AS
SELECT *
FROM tpch.sf1.orders;


SELECT 'GZIP' AS codec, COUNT(*) AS row_count
FROM bench.lakehouse.orders_gzip

UNION ALL

SELECT 'ZSTD', COUNT(*)
FROM bench.lakehouse.orders_zstd;


SELECT
    'GZIP' AS codec,
    COUNT(*) AS file_count,
    ROUND(SUM(file_size_in_bytes) / 1048576.0, 2) AS size_mb
FROM bench.lakehouse."orders_gzip$files"

UNION ALL

SELECT
    'ZSTD',
    COUNT(*),
    ROUND(SUM(file_size_in_bytes) / 1048576.0, 2)
FROM bench.lakehouse."orders_zstd$files";



