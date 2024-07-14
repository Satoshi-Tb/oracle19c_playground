CREATE TABLE sales (
    sales_id NUMBER(10),
    product_id NUMBER(10),
    sale_date DATE,
    quantity_sold NUMBER(5),
    sale_amount NUMBER(10, 2)
)
PARTITION BY RANGE (sale_date) (
    PARTITION sales_jan2023 VALUES LESS THAN (TO_DATE('2023-02-01', 'YYYY-MM-DD')),
    PARTITION sales_feb2023 VALUES LESS THAN (TO_DATE('2023-03-01', 'YYYY-MM-DD')),
    PARTITION sales_mar2023 VALUES LESS THAN (TO_DATE('2023-04-01', 'YYYY-MM-DD'))
);