CREATE OR REPLACE PROCEDURE process_sample_list(p_sample_list IN T_SAMPLE_LIST_ARRAY) IS
  TYPE t_numlist IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  l_indexes t_numlist;
  n_bulk_count CONSTANT NUMBER := 100;
BEGIN

  FOR i IN 1 .. p_sample_list.COUNT LOOP
    IF MOD(i, n_bulk_count) = 0 OR i = p_sample_list.COUNT THEN
      l_indexes(CEIL(i / n_bulk_count)) := i;
    END IF;
  END LOOP;

--  FOR idx IN 1 .. l_indexes.COUNT LOOP
    DECLARE
--      l_start_index PLS_INTEGER := NVL(l_indexes(idx-1), 0) + 1;
--      l_end_index PLS_INTEGER := l_indexes(idx);
    BEGIN
--      FORALL i IN l_start_index .. l_end_index
      FORALL i IN 1 .. p_sample_list.COUNT
        INSERT INTO t_sample_list (id, item1, item2, item3, created_at, created_by, updated_at, updated_by)
        VALUES (p_sample_list(i).id, p_sample_list(i).item1, p_sample_list(i).item2, p_sample_list(i).item3,
                p_sample_list(i).created_at, p_sample_list(i).created_by, p_sample_list(i).updated_at, p_sample_list(i).updated_by);
      COMMIT;
    END;
--  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
    ROLLBACK;
    RAISE;
END;
/

