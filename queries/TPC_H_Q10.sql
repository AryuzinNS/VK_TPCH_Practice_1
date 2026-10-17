-- TPC-H Q10: отчет по возвращенным товарам
-- Медальонный конвейер: tpch.sf1 -> Bronze -> Silver -> Gold
-- Целевой стек: Trino 476 + Lakekeeper + MinIO; имена каталогов взяты из предоставленного архива.
-- Выполняйте операторы по порядку в DBeaver, используя одно и то же подключение к Trino (localhost:8080).
-- Приведенные ниже операторы DROP удаляют только таблицы, созданные этим скриптом Q10, поэтому его можно запускать повторно.

-- 0. Создать пространства имен, если они еще не существуют.
CREATE SCHEMA IF NOT EXISTS bronze.lakehouse;
CREATE SCHEMA IF NOT EXISTS silver.lakehouse;
CREATE SCHEMA IF NOT EXISTS gold.lakehouse;

-- 0.1. Необязательная пересборка: удалить только таблицы этого конвейера в порядке зависимостей.
DROP TABLE IF EXISTS gold.lakehouse.top20_returned;
DROP TABLE IF EXISTS silver.lakehouse.returned_items;
DROP TABLE IF EXISTS bronze.lakehouse.customer;
DROP TABLE IF EXISTS bronze.lakehouse.orders;
DROP TABLE IF EXISTS bronze.lakehouse.lineitem;
DROP TABLE IF EXISTS bronze.lakehouse.nation;

-- 1. BRONZE: скопировать исходные таблицы без бизнес-фильтров и преобразований.
CREATE TABLE bronze.lakehouse.customer
WITH (format = 'PARQUET')
AS SELECT * FROM tpch.sf1.customer;

CREATE TABLE bronze.lakehouse.orders
WITH (format = 'PARQUET')
AS SELECT * FROM tpch.sf1.orders;


CREATE TABLE bronze.lakehouse.lineitem
WITH (format = 'PARQUET')
AS SELECT * FROM tpch.sf1.lineitem;

CREATE TABLE bronze.lakehouse.nation
WITH (format = 'PARQUET')
AS SELECT * FROM tpch.sf1.nation;



-- 1.1. Необязательная проверка количества строк: числа строк в источнике и Bronze должны совпадать.
SELECT 'customer' AS table_name,
       (SELECT COUNT(*) FROM tpch.sf1.customer) AS source_rows,
       (SELECT COUNT(*) FROM bronze.lakehouse.customer) AS bronze_rows
UNION ALL
SELECT 'orders',
       (SELECT COUNT(*) FROM tpch.sf1.orders),
       (SELECT COUNT(*) FROM bronze.lakehouse.orders)
UNION ALL
SELECT 'lineitem',
       (SELECT COUNT(*) FROM tpch.sf1.lineitem),
       (SELECT COUNT(*) FROM bronze.lakehouse.lineitem)
UNION ALL
SELECT 'nation',
       (SELECT COUNT(*) FROM tpch.sf1.nation),
       (SELECT COUNT(*) FROM bronze.lakehouse.nation);

-- 2. SILVER: объединить клиентов, заказы, позиции заказов и страны;
-- оставить возвращенные товары за IV квартал 1993 года, нормализовать текст и рассчитать выручку по каждой позиции.
CREATE TABLE silver.lakehouse.returned_items
WITH (format = 'PARQUET')
AS
SELECT
    c.custkey,
    NULLIF(TRIM(c.name), '') AS name,
    c.acctbal,
    NULLIF(TRIM(n.name), '') AS nation,
    NULLIF(TRIM(c.address), '') AS address,
    NULLIF(TRIM(c.phone), '') AS phone,
    NULLIF(TRIM(c.comment), '') AS comment,
    o.orderkey,
    o.orderdate,
    l.linenumber,
    l.partkey,
    l.suppkey,
    l.quantity,
    l.extendedprice,
    l.discount,
    UPPER(TRIM(l.returnflag)) AS returnflag,
    l.extendedprice * (1 - l.discount) AS line_revenue
FROM bronze.lakehouse.customer AS c
JOIN bronze.lakehouse.orders AS o
    ON c.custkey = o.custkey
JOIN bronze.lakehouse.lineitem AS l
    ON l.orderkey = o.orderkey
JOIN bronze.lakehouse.nation AS n
    ON c.nationkey = n.nationkey
WHERE o.orderdate >= DATE '1993-10-01'
  AND o.orderdate <  DATE '1994-01-01'
  AND UPPER(TRIM(l.returnflag)) = 'R'
  AND c.custkey IS NOT NULL
  AND o.orderkey IS NOT NULL
  AND l.extendedprice IS NOT NULL
  AND l.discount IS NOT NULL;



-- 2.1. Проверить фильтры и даты слоя Silver.
SELECT
    COUNT(*) AS silver_rows,
    MIN(orderdate) AS first_order_date,
    MAX(orderdate) AS last_order_date,
    COUNT_IF(returnflag <> 'R') AS rows_not_marked_returned
FROM silver.lakehouse.returned_items;

-- 3. GOLD: агрегировать выручку по клиентам, сохранить запрошенные выходные столбцы
-- и записать 20 клиентов с наибольшей выручкой.
CREATE TABLE gold.lakehouse.top20_returned
WITH (format = 'PARQUET')
AS
SELECT
    custkey,
    name,
    SUM(line_revenue) AS revenue,
    acctbal,
    nation,
    address,
    phone,
    comment
FROM silver.lakehouse.returned_items
GROUP BY
    custkey,
    name,
    acctbal,
    nation,
    address,
    phone,
    comment
ORDER BY revenue DESC
LIMIT 20;

-- 3.1. Итоговый бизнес-отчет. При чтении данных из Gold всегда указывайте ORDER BY.
SELECT
    custkey,
    name,
    revenue,
    acctbal,
    nation,
    address,
    phone,
    comment
FROM gold.lakehouse.top20_returned
ORDER BY revenue DESC
LIMIT 20;

-- 3.2. Проверка: должно быть возвращено 20 строк (или меньше, если подходящих записей меньше).
select * from gold.lakehouse.top20_returned 

SELECT COUNT(*) AS gold_customers
FROM gold.lakehouse.top20_returned;

-- 4. НЕОБЯЗАТЕЛЬНАЯ проверка эквивалентности результатов.
-- В обоих направлениях различия между ожидаемыми и фактическими данными должны отсутствовать.
WITH expected AS (
    SELECT
        c.custkey,
        NULLIF(TRIM(c.name), '') AS name,
        SUM(l.extendedprice * (1 - l.discount)) AS revenue,
        c.acctbal,
        NULLIF(TRIM(n.name), '') AS nation,
        NULLIF(TRIM(c.address), '') AS address,
        NULLIF(TRIM(c.phone), '') AS phone,
        NULLIF(TRIM(c.comment), '') AS comment
    FROM bronze.lakehouse.customer AS c
    JOIN bronze.lakehouse.orders AS o
        ON c.custkey = o.custkey
    JOIN bronze.lakehouse.lineitem AS l
        ON l.orderkey = o.orderkey
    JOIN bronze.lakehouse.nation AS n
        ON c.nationkey = n.nationkey
    WHERE o.orderdate >= DATE '1993-10-01'
      AND o.orderdate <  DATE '1994-01-01'
      AND UPPER(TRIM(l.returnflag)) = 'R'
    GROUP BY
        c.custkey,
        NULLIF(TRIM(c.name), ''),
        c.acctbal,
        NULLIF(TRIM(n.name), ''),
        NULLIF(TRIM(c.address), ''),
        NULLIF(TRIM(c.phone), ''),
        NULLIF(TRIM(c.comment), '')
    ORDER BY revenue DESC
    LIMIT 20
), actual AS (
    SELECT custkey, name, revenue, acctbal, nation, address, phone, comment
    FROM gold.lakehouse.top20_returned
)
SELECT 'expected_minus_gold' AS difference_type, COUNT(*) AS difference_rows
FROM (SELECT * FROM expected EXCEPT SELECT * FROM actual) AS d
UNION ALL
SELECT 'gold_minus_expected', COUNT(*)
FROM (SELECT * FROM actual EXCEPT SELECT * FROM expected) AS d;
