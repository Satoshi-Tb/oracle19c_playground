--
select DBMS_LOB.GETLENGTH(TEXT) text_len from T_LOB_HEADER
/
-- 検証用SQL
select memo, HEADER_ID, count(*) from T_LOB_DETAIL
group by memo, HEADER_ID
order by 1, 2
/
select HEADER_ID, NO, DBMS_LOB.SUBSTR(FRAGMENT, 4000, 1), FRAGMENT_LEN
from T_LOB_DETAIL where MEMO = 'ADD2'
minus
select HEADER_ID, NO, DBMS_LOB.SUBSTR(FRAGMENT, 4000, 1), FRAGMENT_LEN
from T_LOB_DETAIL where MEMO = 'ADD3'
/
select HEADER_ID, NO, DBMS_LOB.SUBSTR(FRAGMENT, 4000, 1), FRAGMENT_LEN
from T_LOB_DETAIL where MEMO = 'ADD3'
MINUS
select HEADER_ID, NO, DBMS_LOB.SUBSTR(FRAGMENT, 4000, 1), FRAGMENT_LEN
from T_LOB_DETAIL where MEMO = 'ADD2'
/
select memo, HEADER_ID, count(*) from T_LOB_DETAIL
where FRAGMENT_LEN = 0
group by memo, HEADER_ID
order by 1, 2
/
select HEADER_ID, NO, FRAGMENT, FRAGMENT_LEN
from T_LOB_DETAIL
where FRAGMENT is null
--where MEMO = 'ADD2' and FRAGMENT_LEN = 0
/
select memo, HEADER_ID, count(*) from T_LOB_DETAIL
where FRAGMENT is null
--where FRAGMENT_LEN = 0
group by memo, HEADER_ID
order by 1, 2
/
-- OracleText最新化
-- EXEC CTX_DDL.SYNC_INDEX('CTX1_T_LOB_HEADER');
-- EXEC CTX_DDL.SYNC_INDEX('CTX1_T_LOB_DETAIL');