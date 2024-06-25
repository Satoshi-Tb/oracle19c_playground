SET TERMOUT OFF
SET SERVEROUT ON
SET TRIMSPOOL ON
SPOOL output_ddl_sample2.log

DECLARE
    object_ddl CLOB;

    -- DROP文作成
    drop_flg char(1) := '0';

    CURSOR c_tables IS
    WITH refs (child, parent, depth) AS (
    SELECT
        t.table_name child,
        null parent,
        1 AS depth
    FROM
        user_tables t
    WHERE
        NOT EXISTS (
        SELECT *
        FROM user_constraints fk
        WHERE t.table_name = fk.table_name
        AND fk.CONSTRAINT_TYPE = 'R'
        )
        AND t.table_name NOT LIKE 'DR$%'
    UNION ALL
    SELECT
        fk.table_name,
        r.child,
        r.depth + 1
    FROM
        refs r
    INNER JOIN user_constraints pk
        ON pk.table_name = r.child
    INNER JOIN user_constraints fk
        ON fk.R_CONSTRAINT_NAME = pk.CONSTRAINT_NAME
        AND fk.constraint_type = 'R'
    WHERE
        r.depth < 100
    )
    cycle child set isloop to 'Y' default 'N'
    SELECT child table_name, parent, depth FROM Refs
    WHERE isloop = 'N'
    ORDER BY depth, parent, table_name;

    -- インデックス
    cursor c_indexes (p_table_name IN VARCHAR2)
    IS
    SELECT index_name
    FROM user_indexes ix
    WHERE ix.table_name = p_table_name
    AND ix.index_type <> 'LOB'
    AND NOT EXISTS (
        SELECT *
        FROM user_constraints cts
        WHERE cts.constraint_name = ix.index_name
    )
    ORDER BY index_name;

    -- コメント
    cursor c_comment_ddl(p_table_name IN VARCHAR2)
    IS
    SELECT 'COMMENT ON TABLE ' || table_name || ' IS ''' || REPLACE(comments, '''', '''''') || ''';' AS comment_ddl
    FROM user_tab_comments
    WHERE table_name = p_table_name AND comments IS NOT NULL
    UNION ALL
    SELECT 'COMMENT ON COLUMN ' || table_name || '.' || column_name || ' IS ''' || REPLACE(comments, '''', '''''') || ''';'
    FROM user_col_comments
    WHERE table_name = 'TABLE_NAME' AND comments IS NOT NULL;

    -- シーケンス
    cursor c_seqences
    IS
    SELECT sequence_name name
    FROM user_sequences
    WHERE sequence_name NOT LIKE 'ISEQ%'
    ORDER BY name;    

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
        AND o.OBJECT_TYPE IN ('VIEW', 'SEQUENCE', 'MATERIALIZED VIEW')
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

    FOR rec IN c_seqences LOOP
        object_ddl := DBMS_METADATA.GET_DDL('SEQUENCE', rec.name);
        -- 空文字を削除
        object_ddl := TRIM(object_ddl);
        object_ddl := REGEXP_REPLACE(object_ddl, '[[:cntrl:]]', '');
        object_ddl := REGEXP_REPLACE(object_ddl, '"', '');

        DBMS_OUTPUT.PUT_LINE(object_ddl);
        DBMS_OUTPUT.PUT_LINE('/');
    END LOOP;


    FOR rec IN c_tables LOOP
        object_ddl := DBMS_METADATA.GET_DDL('TABLE', rec.table_name);
        -- 空文字を削除
        object_ddl := TRIM(object_ddl);
        object_ddl := REGEXP_REPLACE(object_ddl, '[[:cntrl:]]', '');
        object_ddl := REGEXP_REPLACE(object_ddl, '"', '');

        DBMS_OUTPUT.PUT_LINE(object_ddl);
        DBMS_OUTPUT.PUT_LINE('/');

        -- インデックス定義
        FOR rec_idx IN c_indexes(rec.table_name) LOOP
            object_ddl := DBMS_METADATA.GET_DDL('INDEX', rec_idx.index_name);
            -- 空文字を削除
            object_ddl := TRIM(object_ddl);
            object_ddl := REGEXP_REPLACE(object_ddl, '[[:cntrl:]]', '');
            object_ddl := REGEXP_REPLACE(object_ddl, '"', '');

            DBMS_OUTPUT.PUT_LINE(object_ddl);
            DBMS_OUTPUT.PUT_LINE('/');
        END LOOP;

        -- コメント定義
        FOR rec_cmmmt IN c_comment_ddl(rec.table_name) LOOP
            DBMS_OUTPUT.PUT_LINE(rec_cmmmt.comment_ddl);
            DBMS_OUTPUT.PUT_LINE('/');          
        END LOOP;
    END LOOP;

    -- FOR rec IN c_objects LOOP
    --     BEGIN
    --         -- DDLを取得して出力
    --         object_ddl := DBMS_METADATA.GET_DDL(rec.OBJECT_TYPE, rec.OBJECT_NAME);

    --         -- 空文字を削除
    --         object_ddl := TRIM(object_ddl);
    --         object_ddl := REGEXP_REPLACE(object_ddl, '[[:cntrl:]]', '');
    --         object_ddl := REGEXP_REPLACE(object_ddl, '"', '');

    --         IF rec.OBJECT_TYPE = 'SEQUENCE' THEN
    --             object_ddl := REGEXP_REPLACE(object_ddl, 'START WITH \d+', 'START WITH 1');
    --         END IF;

    --         DBMS_OUTPUT.PUT_LINE('PROM > ' || rec.OBJECT_NAME);  -- 出力コメント。出力サイズが大きい場合コメントアウト

    --         IF drop_flg = '1' AND (
    --             rec.OBJECT_TYPE = 'TABLE' OR
    --             rec.OBJECT_TYPE = 'SEQUENCE' OR
    --             rec.OBJECT_TYPE = 'VIEW' OR
    --             rec.OBJECT_TYPE = 'MATERIALIZED VIEW'
    --         ) THEN
    --             DBMS_OUTPUT.PUT_LINE('DROP ' || rec.OBJECT_TYPE || ' ' || rec.OBJECT_NAME);  -- 出力コメント。出力サイズが大きい場合コメントアウト
    --             IF rec.OBJECT_TYPE = 'TABLE' THEN
    --                 DBMS_OUTPUT.PUT_LINE('CASCADE CONSTRAINTS');
    --             END IF;
    --             DBMS_OUTPUT.PUT_LINE('/');
    --         END IF;

    --         DBMS_OUTPUT.PUT_LINE(object_ddl);
    --         DBMS_OUTPUT.PUT_LINE('/');
    --     EXCEPTION
    --         WHEN OTHERS THEN
    --         DBMS_OUTPUT.PUT_LINE('Error retrieving DDL for ' || rec.object_name || ': ' || SQLERRM);
    --     END;
    -- END LOOP;

END;
/

SPOOL OFF