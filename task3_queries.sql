-- Task 3.1: Join two large tables
-- Join impressions to viewing_segments by impression_id

EXPLAIN QUERY PLAN
SELECT
    i.impression_id,
    i.video_id,
    vs.watch_seconds,
    vs.reached_end
FROM impressions AS i
JOIN viewing_segments AS vs
    ON vs.impression_id = i.impression_id;


-- Task 3.1: Join 2
EXPLAIN QUERY PLAN
SELECT
    i.impression_id,
    i.user_id,
    i.video_id,
    r.turn_id
FROM impressions AS i
JOIN recommendations AS r
    ON r.video_id = i.video_id;

--task 3.2
SELECT 'impressions' AS table_name, COUNT(*) AS row_count
FROM impressions

UNION ALL

SELECT 'viewing_segments', COUNT(*)
FROM viewing_segments

UNION ALL

SELECT 'recommendations', COUNT(*)
FROM recommendations;

--task 3.3
SELECT 'sessions' AS table_name, COUNT(*) AS row_count FROM sessions
UNION ALL
SELECT 'turns', COUNT(*) FROM turns
UNION ALL
SELECT 'recommendations', COUNT(*) FROM recommendations;


-- A: sessions JOIN turns
SELECT COUNT(*) AS rows_after_join
FROM sessions AS s
JOIN turns AS t
  ON t.session_id = s.session_id;

-- B: turns JOIN recommendations
SELECT COUNT(*) AS rows_after_join
FROM turns AS t
JOIN recommendations AS r
  ON r.turn_id = t.turn_id;


-- C: sessions JOIN turns JOIN recommendations
SELECT COUNT(*) AS rows_after_join
FROM sessions AS s
JOIN turns AS t
  ON t.session_id = s.session_id
JOIN recommendations AS r
  ON r.turn_id = t.turn_id;


EXPLAIN QUERY PLAN
SELECT
    s.session_id,
    t.turn_id,
    r.video_id
FROM sessions AS s
JOIN turns AS t
    ON t.session_id = s.session_id
JOIN recommendations AS r
    ON r.turn_id = t.turn_id;