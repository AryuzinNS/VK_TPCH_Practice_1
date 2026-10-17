-- TPC-H Q10: отчет по возвращенным товарам
-- Формат Bronze: PARQUET; кодек сжатия: ZSTD
-- Рекомендуемый вариант: Parquet + ZSTD — хороший баланс сжатия, скорости чтения и совместимости.
-- Trino 476 + REST-каталог Iceberg (Lakekeeper) + MinIO.
-- Выполняйте операторы сверху вниз в DBeaver, используя одно подключение к Trino.
-- ВАЖНО: запускайте только один профиль за раз. Скрипты пересоздают одни и те же таблицы Bronze/Silver/Gold.
-- Для Silver и Gold сохраняются настройки PARQUET + ZSTD, поэтому профиль меняет только Bronze.
-- SET SESSION и следующий за ним CREATE TABLE должны выполняться в одной сессии DBeaver/Trino.

-- Создание схем выполняется один раз; IF NOT EXISTS позволяет запускать повторно.
CREATE SCHEMA IF NOT EXISTS bronze.lakehouse;
CREATE SCHEMA IF NOT EXISTS silver.lakehouse;
CREATE SCHEMA IF NOT EXISTS gold.lakehouse;

-- Пересборка именно этого конвейера. Удаляются только его шесть таблиц.
DROP TABLE IF EXISTS gold.lakehouse.top20_returned;
DROP TABLE IF EXISTS silver.lakehouse.returned_items;
DROP TABLE IF EXISTS bronze.lakehouse.customer;
DROP TABLE IF EXISTS bronze.lakehouse.orders;
DROP TABLE IF EXISTS bronze.lakehouse.lineitem;
DROP TABLE IF EXISTS bronze.lakehouse.nation;

-- BRONZE: исходные копии. Источник — сгенерированный коннектор TPC-H sf1.
-- На этом уровне не применяются фильтры и бизнес-преобразования.
-- customer: задаём кодек для записи следующей таблицы; выполнить в той же сессии Trino.
SET SESSION bronze.compression_codec = 'ZSTD';

CREATE TABLE bronze.lakehouse.customer
WITH (format = 'PARQUET')
AS SELECT * FROM tpch.sf1.customer;

-- orders: задаём кодек для записи следующей таблицы; выполнить в той же сессии Trino.
SET SESSION bronze.compression_codec = 'ZSTD';

CREATE TABLE bronze.lakehouse.orders
WITH (format = 'PARQUET')
AS SELECT * FROM tpch.sf1.orders;

-- lineitem: задаём кодек для записи следующей таблицы; выполнить в той же сессии Trino.
SET SESSION bronze.compression_codec = 'ZSTD';

CREATE TABLE bronze.lakehouse.lineitem
WITH (format = 'PARQUET')
AS SELECT * FROM tpch.sf1.lineitem;

-- nation: задаём кодек для записи следующей таблицы; выполнить в той же сессии Trino.
SET SESSION bronze.compression_codec = 'ZSTD';

CREATE TABLE bronze.lakehouse.nation
WITH (format = 'PARQUET')
AS SELECT * FROM tpch.sf1.nation;


-- Проверка: количество строк в Bronze должно совпадать с tpch.sf1.
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

-- SILVER: объединить исходные таблицы, отобрать возвраты за IV квартал 1993 года, нормализовать текст
-- и рассчитать чистую выручку по каждой возвращенной позиции.
SET SESSION silver.compression_codec = 'ZSTD';

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

-- Проверка Silver: строки только за IV квартал 1993 года и с флагом R.
SELECT
    COUNT(*) AS silver_rows,
    MIN(orderdate) AS first_order_date,
    MAX(orderdate) AS last_order_date,
    COUNT_IF(returnflag <> 'R') AS rows_not_marked_returned
FROM silver.lakehouse.returned_items;

-- GOLD: агрегировать выручку от возвращенных товаров по клиентам и сохранить 20 лучших.
SET SESSION gold.compression_codec = 'ZSTD';

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

-- Итоговый результат Q10.
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

-- Итоговое количество строк. Для TPC-H SF1 обычно возвращается 20 строк.
SELECT COUNT(*) AS gold_customers
FROM gold.lakehouse.top20_returned;

-- Дополнительная проверка: ожидаемый Q10 из Bronze и Gold должны совпасть.
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
    JOIN bronze.lakehouse.orders AS o ON c.custkey = o.custkey
    JOIN bronze.lakehouse.lineitem AS l ON l.orderkey = o.orderkey
    JOIN bronze.lakehouse.nation AS n ON c.nationkey = n.nationkey
    WHERE o.orderdate >= DATE '1993-10-01'
      AND o.orderdate < DATE '1994-01-01'
      AND UPPER(TRIM(l.returnflag)) = 'R'
      AND c.custkey IS NOT NULL
      AND o.orderkey IS NOT NULL
      AND l.extendedprice IS NOT NULL
      AND l.discount IS NOT NULL
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
