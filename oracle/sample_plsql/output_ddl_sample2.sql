SET TERMOUT OFF
SET SERVEROUT ON
SET TRIMSPOOL ON
SPOOL output_ddl_sample2.log

DECLARE
    object_ddl CLOB;

    -- DROP文作成
    drop_flg char(1) := '1';
    out_prom char(1) := '1';

    TYPE ARR_VARCHAR2 IS TABLE OF VARCHAR2(255) INDEX BY PLS_INTEGER;
    arr_table_names ARR_VARCHAR2;
    table_name VARCHAR2(255);
    i PLS_INTEGER;

    -- テーブル名取得（親子関係の上から順に取得）
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
    WHERE table_name = p_table_name AND comments IS NOT NULL;

    -- シーケンス
    cursor c_seqences
    IS
    SELECT sequence_name name
    FROM user_sequences
    WHERE sequence_name NOT LIKE 'ISEQ%'
    ORDER BY name;    

    -- 空白文字除去
    FUNCTION TRIM_LOB(input_clob CLOB) RETURN CLOB IS
        cleaned_clob CLOB;
    BEGIN
        -- 空のCLOBを初期化
        DBMS_LOB.CREATETEMPORARY(cleaned_clob, TRUE);

        -- トリム処理と正規表現による制御文字とダブルクォートの削除
        cleaned_clob := TRIM(input_clob);
        cleaned_clob := REGEXP_REPLACE(cleaned_clob, '[[:cntrl:]]', '');
        cleaned_clob := REGEXP_REPLACE(cleaned_clob, '"', '');

        RETURN cleaned_clob;
    EXCEPTION
        WHEN OTHERS THEN
            -- 何らかのエラーが発生した場合、CLOBを解放してエラーを再度発生させる
            DBMS_LOB.FREETEMPORARY(cleaned_clob);
            RAISE;
    END;

    --
    PROCEDURE PROM(prompt IN VARCHAR2)
    IS
    BEGIN
        IF out_prom = '1' THEN
            DBMS_OUTPUT.PUT_LINE('PROM ' || prompt);
        END IF;
    END;

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

    -- 対象テーブルを格納
    FOR rec IN c_tables LOOP
        arr_table_names(arr_table_names.COUNT) := rec.table_name;
    END LOOP;

    -- DROP文
    IF drop_flg = '1' THEN
        FOR rec IN c_seqences LOOP
            PROM('> DROP SEQUENCE ' || rec.name);
            DBMS_OUTPUT.PUT_LINE('DROP SEQUENCE ' || rec.name);
            DBMS_OUTPUT.PUT_LINE('/');
        END LOOP;

        i := arr_table_names.LAST;
        WHILE i IS NOT NULL LOOP
            table_name := arr_table_names(i);

            PROM('> DROP TABLE ' || table_name);
            DBMS_OUTPUT.PUT_LINE('DROP TABLE ' || table_name || ' CASCADE CONSTRAINTS');
            DBMS_OUTPUT.PUT_LINE('/');
            i := arr_table_names.PRIOR(i);
        END LOOP;
    END IF;

    FOR rec IN c_seqences LOOP
        object_ddl := TRIM_LOB(DBMS_METADATA.GET_DDL('SEQUENCE', rec.name));
        -- 開始番号を1にセット
        object_ddl := REGEXP_REPLACE(object_ddl, 'START WITH \d+', 'START WITH 1');

        PROM('> CREATE SEQUENCE ' || rec.name);
        DBMS_OUTPUT.PUT_LINE(object_ddl);
        DBMS_OUTPUT.PUT_LINE('/');
    END LOOP;


    i := arr_table_names.FIRST;
    WHILE i IS NOT NULL LOOP
        table_name := arr_table_names(i);

        object_ddl := TRIM_LOB(DBMS_METADATA.GET_DDL('TABLE', table_name));

        PROM('> CREATE TABLE ' || table_name);
        DBMS_OUTPUT.PUT_LINE(object_ddl);
        DBMS_OUTPUT.PUT_LINE('/');

        -- インデックス定義
        FOR rec_idx IN c_indexes(table_name) LOOP
            object_ddl := TRIM_LOB(DBMS_METADATA.GET_DDL('INDEX', rec_idx.index_name));
            DBMS_OUTPUT.PUT_LINE(object_ddl);
            DBMS_OUTPUT.PUT_LINE('/');
        END LOOP;

        -- コメント定義
        FOR rec_cmmmt IN c_comment_ddl(table_name) LOOP
            DBMS_OUTPUT.PUT_LINE(rec_cmmmt.comment_ddl);
            DBMS_OUTPUT.PUT_LINE('/');          
        END LOOP;

        i := arr_table_names.NEXT(i);
    END LOOP;
END;
/

SPOOL OFF