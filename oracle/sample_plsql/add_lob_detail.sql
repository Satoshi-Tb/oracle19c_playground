CREATE OR REPLACE PROCEDURE add_sample_data
IS
    -- ログ
    v_wrap_out PLS_INTEGER := 1;
    v_ts_out PLS_INTEGER := 1;
    v_base_time  NUMBER := DBMS_UTILITY.GET_TIME;

    CURSOR c_src IS
    SELECT ID, TEXT, ROWID AS RID FROM T_LOB_HEADER
    WHERE DBMS_LOB.GETLENGTH(TEXT) <= 10000000
    ORDER BY ID;

    PROCEDURE WRAP_INIT
    IS
    BEGIN
        v_base_time := DBMS_UTILITY.GET_TIME;
    END WRAP_INIT;

    PROCEDURE WRAP_TIME(v_msg VARCHAR2)
    IS
        v_current NUMBER;
    BEGIN
        v_current := DBMS_UTILITY.GET_TIME;
        IF v_wrap_out = 1 THEN
            DBMS_OUTPUT.PUT_LINE(v_msg || ' ' || TO_CHAR((v_current - v_base_time) / 100, 'FM999,990.000'));
        END IF;
        v_base_time := v_current;
    END WRAP_TIME;

    PROCEDURE TS_LOG(v_msg VARCHAR2)
    IS
    BEGIN
        IF v_ts_out = 1 THEN
            DBMS_OUTPUT.PUT_LINE(v_msg || ' ' || TO_CHAR(SYSTIMESTAMP, 'YYYY/MM/DD HH24:MI:SS.FF3'));
        END IF;
    END TS_LOG;

    -- LOB文字列のSUBSTRING関数
    FUNCTION LOB_SUBSTR(
        v_src CLOB, -- 抽出対象文字列
        v_amount NUMBER, -- 抽出文字数
        v_position NUMBER -- 抽出文字位置
    )
    RETURN CLOB
    IS
        -- 抽出結果を格納するためのCLOB
        dest_clob CLOB;
        -- 作業用変数
        v_buff VARCHAR2(32767);
        -- 読み取り済サイズ
        v_read_ttl NUMBER := 0;
        -- 読み取りサイズ
        v_read_sz NUMBER;
    BEGIN
        IF v_amount <= 0 THEN
            RETURN NULL;
        END IF;

        IF v_position <= 0 THEN
            RETURN NULL;
        END IF;

        -- 一時CLOBの初期化
        DBMS_LOB.CREATETEMPORARY(dest_clob, TRUE);

        WHILE (v_read_ttl < v_amount) LOOP
            -- 読込サイズ決定。最大32767または残りの文字数
            IF (v_amount - v_read_ttl) > 32767 THEN
                v_read_sz := 32767;
            ELSE
                v_read_sz := v_amount - v_read_ttl;
            END IF;
            
            -- CLOBからデータを読み取る
            v_buff := DBMS_LOB.SUBSTR(v_src, v_read_sz, v_position + v_read_ttl);
            
            -- 読込済サイズ加算
            v_read_ttl := v_read_ttl + v_read_sz;
            
            -- 抽出されたデータをdest_clobに追加
            DBMS_LOB.WRITEAPPEND(dest_clob, LENGTH(v_buff), v_buff);
            
            -- 最後まで読み取ったか、または読み取りバッファが空の場合ループを終了
            EXIT WHEN LENGTH(v_buff) < v_read_sz OR v_buff IS NULL;
        END LOOP;

        RETURN dest_clob;
    EXCEPTION
        WHEN OTHERS THEN
            -- 例外が発生した場合、一時CLOBを解放してから例外を再送出
            IF dest_clob IS NOT NULL THEN
                DBMS_LOB.FREETEMPORARY(dest_clob);
            END IF;
            RAISE;
    END LOB_SUBSTR;

    -- 1.初期バージョン
    PROCEDURE PROC_ADD_1
    IS
        v_ptag_count NUMBER;
        v_count NUMBER;
        v_fragment CLOB;
    BEGIN
        -- EXECUTE IMMEDIATE 'TRUNCATE TABLE T_LOB_DETAIL';
        TS_LOG('PROC_ADD_1 処理開始');


        v_count := 0;
        FOR rec IN c_src
        LOOP
            v_count := v_count + 1;
            WRAP_INIT;
            v_ptag_count := REGEXP_COUNT(rec.TEXT, '<p>(.*?)</p>', 1, 'i');
            FOR i IN 1 .. v_ptag_count
            LOOP
                v_fragment := REGEXP_SUBSTR(rec.TEXT, '<p>(.*?)</p>', 1, i, 'i', 1);

                INSERT INTO T_LOB_DETAIL (HEADER_ID, NO, FRAGMENT, FRAGMENT_LEN, MEMO)
                VALUES (
                    rec.ID,
                    i,
                    v_fragment,
                    DBMS_LOB.GETLENGTH(v_fragment),
                    'ADD1'
                );
            END LOOP;
            WRAP_TIME('(' || v_count || ') text_len[' || DBMS_LOB.GETLENGTH(rec.TEXT) || '] ptag_count[' || v_ptag_count || ']');

            COMMIT;

            UPDATE T_LOB_HEADER
            SET
                TEXT_LEN = DBMS_LOB.GETLENGTH(rec.TEXT),
                FRAGMENT_COUNT = v_ptag_count
            WHERE ROWID = rec.RID;
            COMMIT;

        END LOOP;
        TS_LOG('PROC_ADD_1 処理完了');
    
    END PROC_ADD_1;

    -- 2.REGEXP_SUBSTR改善
    PROCEDURE PROC_ADD_2
    IS
        v_cur_pos NUMBER;
        v_found_pos NUMBER;
        v_ptag_count NUMBER;
        v_count NUMBER;
        v_fragment CLOB;
        v_fragment_len NUMBER;
    BEGIN
        -- EXECUTE IMMEDIATE 'TRUNCATE TABLE T_LOB_DETAIL';
        TS_LOG('PROC_ADD_2 処理開始');


        v_count := 0;
        FOR rec IN c_src
        LOOP
            v_count := v_count + 1;
            v_cur_pos := 1;
            v_ptag_count := 0;
            WRAP_INIT;

            LOOP

                -- パターン有無チェック
                v_found_pos := REGEXP_INSTR(rec.TEXT, '<p>(.*?)</p>', v_cur_pos, 1, 0, 'i');
                EXIT WHEN v_found_pos = 0; -- パターン無し

                -- 部分文字列取得（Pタグの中身）（NULL文字の可能性あり）
                v_fragment := REGEXP_SUBSTR(rec.TEXT, '<p>(.*?)</p>', v_cur_pos, 1, 'i', 1);
                v_fragment_len := NVL(DBMS_LOB.GETLENGTH(v_fragment), 0);

                v_ptag_count := v_ptag_count + 1;
                INSERT INTO T_LOB_DETAIL (HEADER_ID, NO, FRAGMENT, FRAGMENT_LEN, MEMO)
                VALUES (
                    rec.ID,
                    v_ptag_count,
                    CASE v_fragment_len WHEN 0 THEN NULL ELSE v_fragment END,
                    v_fragment_len,
                    'ADD2'
                );

                -- 次の検索位置を更新
                v_cur_pos := v_found_pos + 3 + NVL(DBMS_LOB.GETLENGTH(v_fragment), 0) + 4;

            END LOOP;
            WRAP_TIME('(' || v_count || ') text_len[' || DBMS_LOB.GETLENGTH(rec.TEXT) || '] ptag_count[' || v_ptag_count || ']');

            COMMIT;

            UPDATE T_LOB_HEADER
            SET
                TEXT_LEN = DBMS_LOB.GETLENGTH(rec.TEXT),
                FRAGMENT_COUNT = v_ptag_count
            WHERE ROWID = rec.RID;
            COMMIT;

        END LOOP;
        TS_LOG('PROC_ADD_2 処理完了');
    
    END PROC_ADD_2;

    -- 3.INSTR使用。
    PROCEDURE PROC_ADD_3
    IS
        v_pos_check NUMBER;
        v_start_pos NUMBER;
        v_end_pos NUMBER;
        v_ptag_count NUMBER;
        v_count NUMBER;
        v_fragment_len NUMBER;
        v_fragment CLOB;
    BEGIN
        -- EXECUTE IMMEDIATE 'TRUNCATE TABLE T_LOB_DETAIL';
        TS_LOG('PROC_ADD_3 処理開始');


        v_count := 0;
        FOR rec IN c_src
        LOOP
            v_count := v_count + 1;
            v_start_pos := 1;
            v_ptag_count := 0;
            WRAP_INIT;

            LOOP
                -- REG_ISTRよりも若干速い
                v_pos_check := INSTR(rec.TEXT, '<p>', v_start_pos);
                IF v_pos_check = 0 THEN
                    v_pos_check := INSTR(rec.TEXT, '<P>', v_start_pos); --<>
                END IF;
                EXIT WHEN v_pos_check = 0; --見つからない場合終了
                v_start_pos := v_pos_check;

                v_pos_check := INSTR(rec.TEXT, '</p>', v_start_pos + 3);
                IF v_pos_check = 0 THEN
                    v_pos_check := INSTR(rec.TEXT, '</P>', v_start_pos + 3);
                END IF;
                EXIT WHEN v_end_pos = 0; --見つからない場合終了
                v_end_pos := v_pos_check;

                v_fragment_len := v_end_pos - v_start_pos - 3;

                -- 一時CLOBの初期化
                DBMS_LOB.CREATETEMPORARY(v_fragment, TRUE);

                IF v_fragment_len > 0 THEN
                    -- CLOBの部分コピー
                    DBMS_LOB.COPY(v_fragment, rec.TEXT, v_fragment_len, 1, v_start_pos + 3);
                END IF;

                v_ptag_count := v_ptag_count + 1;

                -- DEBUGログ(SUBSTR失敗ログ)
                IF v_fragment_len > 0 AND v_fragment IS NULL THEN
                    TS_LOG('ptag(' || v_ptag_count || ') actual[' || v_fragment_len || '] but fragment is null');
                END IF;

                INSERT INTO T_LOB_DETAIL (HEADER_ID, NO, FRAGMENT, FRAGMENT_LEN, MEMO)
                VALUES (
                    rec.ID,
                    v_ptag_count,
                    CASE v_fragment_len WHEN 0 THEN NULL ELSE v_fragment END,
                    v_fragment_len,
                    'ADD3'
                );

                -- 解放
                DBMS_LOB.FREETEMPORARY(v_fragment);

                -- 次の検索位置を更新
                v_start_pos := v_end_pos + 1;

            END LOOP;
            WRAP_TIME('(' || v_count || ') text_len[' || DBMS_LOB.GETLENGTH(rec.TEXT) || '] ptag_count[' || v_ptag_count || ']');

            COMMIT;

            UPDATE T_LOB_HEADER
            SET
                TEXT_LEN = DBMS_LOB.GETLENGTH(rec.TEXT),
                FRAGMENT_COUNT = v_ptag_count
            WHERE ROWID = rec.RID;
            COMMIT;

        END LOOP;
        TS_LOG('PROC_ADD_3 処理完了');
    
    EXCEPTION
        WHEN OTHERS THEN
            -- 例外が発生した場合、一時CLOBを解放してから例外を再送出
            IF v_fragment IS NOT NULL THEN
                DBMS_LOB.FREETEMPORARY(v_fragment);
            END IF;
            RAISE;

    END PROC_ADD_3;

BEGIN

    EXECUTE IMMEDIATE 'TRUNCATE TABLE T_LOB_DETAIL';

    -- PROC_ADD_1;
    -- PROC_ADD_2;
    PROC_ADD_3;

END;
/

exit;