SET TERMOUT OFF
SET SERVEROUT ON
SET TRIMSPOOL ON
SPOOL output_ddl_sample2.log

DECLARE
    object_ddl CLOB;

    -- DROP文作成
    drop_flg char(1) := '0';

    -- テーブル出力順は外部制約の親から
    CURSOR c_objects IS
    WITH CHILDS (child_table, parent_table, depth) AS (
    SELECT
        pk.table_name AS parent_table,
        fk.table_name AS child_table,
        1 AS depth
    FROM
        user_constraints fk
        JOIN user_constraints pk
        ON fk.r_constraint_name = pk.constraint_name
        AND fk.constraint_type = 'R'
    UNION ALL
    SELECT
        r.parent_table,
        fk.table_name,
        r.depth + 1
    FROM
        CHILDS r
        JOIN user_constraints fk
        ON r.child_table  = fk.table_name
        AND fk.constraint_type = 'R'
        JOIN user_constraints pk
        ON fk.r_constraint_name = pk.constraint_name
    WHERE
        r.depth < 100
    )
    SELECT DISTINCT
        CASE o.OBJECT_TYPE
            WHEN 'TABLE' THEN 2
            WHEN 'INDEX' THEN 3
            WHEN 'VIEW' THEN 4
            WHEN 'SEQUENCE' THEN 1
            WHEN 'MATERIALIZED VIEW' THEN 5
            ELSE 99
        END PRI,
        OBJECT_NAME,
        OBJECT_TYPE,
        NVL(DEPTH, 0) DEPTH
    FROM USER_OBJECTS o
    LEFT OUTER JOIN CHILDS c
        ON o.OBJECT_NAME = c.PARENT_TABLE
    WHERE
        o.OBJECT_NAME LIKE '%/_LOB/_%' ESCAPE '/'
        AND o.OBJECT_NAME NOT LIKE 'DR$%' 
        AND o.OBJECT_TYPE IN ('TABLE', 'INDEX', 'VIEW', 'SEQUENCE', 'MATERIALIZED VIEW')
        AND NOT EXISTS (
            SELECT * FROM USER_CONSTRAINTS c
            WHERE c.CONSTRAINT_NAME = o.OBJECT_NAME
        )
    ORDER BY PRI, DEPTH, OBJECT_NAME;

BEGIN
    -- バッファサイズを無制限に設定(クライアント環境によるので注意)
    -- NULLにするとおそらく出力されなくなる
--    DBMS_OUTPUT.ENABLE(NULL);

    -- バッファサイズを100MBに設定
    DBMS_OUTPUT.ENABLE(1024 * 1024 * 100);
    -- LOBストレージ情報を出力しないように設定
    DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'STORAGE', FALSE);
    -- LOBのセグメント属性も出力しないように設定
    DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, 'SEGMENT_ATTRIBUTES', FALSE);

    DBMS_OUTPUT.PUT_LINE('SET TERMOUT ON');

    FOR rec IN c_objects LOOP
        BEGIN
            -- DDLを取得して出力
            object_ddl := DBMS_METADATA.GET_DDL(rec.OBJECT_TYPE, rec.OBJECT_NAME);

            -- 空文字を削除
            object_ddl := TRIM(object_ddl);
            -- object_ddl := REGEXP_REPLACE(object_ddl, '\r', '');
            -- object_ddl := REGEXP_REPLACE(object_ddl, '\n', '');
            -- object_ddl := REGEXP_REPLACE(object_ddl, '\t', '');
            object_ddl := REGEXP_REPLACE(object_ddl, '[[:cntrl:]]', '');
            object_ddl := REGEXP_REPLACE(object_ddl, '"', '');

            IF rec.OBJECT_TYPE = 'SEQUENCE' THEN
                object_ddl := REGEXP_REPLACE(object_ddl, 'START WITH \d+', 'START WITH 1');
            END IF;

            DBMS_OUTPUT.PUT_LINE('PROM > ' || rec.OBJECT_NAME);  -- 出力コメント。出力サイズが大きい場合コメントアウト

            IF drop_flg = '1' AND (
                rec.OBJECT_TYPE = 'TABLE' OR
                rec.OBJECT_TYPE = 'SEQUENCE' OR
                rec.OBJECT_TYPE = 'VIEW' OR
                rec.OBJECT_TYPE = 'MATERIALIZED VIEW'
            ) THEN
                DBMS_OUTPUT.PUT_LINE('DROP ' || rec.OBJECT_TYPE || ' ' || rec.OBJECT_NAME);  -- 出力コメント。出力サイズが大きい場合コメントアウト
                IF rec.OBJECT_TYPE = 'TABLE' THEN
                    DBMS_OUTPUT.PUT_LINE('CASCADE CONSTRAINTS');
                END IF;
                DBMS_OUTPUT.PUT_LINE('/');
            END IF;

            DBMS_OUTPUT.PUT_LINE(object_ddl);
            DBMS_OUTPUT.PUT_LINE('/');
        EXCEPTION
            WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error retrieving DDL for ' || rec.object_name || ': ' || SQLERRM);
        END;
    END LOOP;

END;
/

SPOOL OFF