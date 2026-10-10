--original F13 query

SELECT
    t.turn_id,
    t.session_id,
    js.helpfulness AS judge_helpfulness,
    ur.rating AS user_rating,
    js.judged_at,
    ur.rated_at
FROM turns AS t
JOIN judge_scores AS js
    ON js.turn_id = t.turn_id
JOIN user_ratings AS ur
    ON ur.turn_id = t.turn_id
WHERE js.helpfulness > 4
  AND ur.rating = 'thumbs_down'
ORDER BY
    t.session_id,
    t.turn_number;


--pushed down version

SELECT
    t.turn_id,
    t.session_id,
    js.helpfulness AS judge_helpfulness,
    ur.rating AS user_rating,
    js.judged_at,
    ur.rated_at
FROM turns AS t
JOIN (
    SELECT *
    FROM judge_scores
    WHERE helpfulness > 4
) AS js
    ON js.turn_id = t.turn_id
JOIN (
    SELECT *
    FROM user_ratings
    WHERE rating = 'thumbs_down'
) AS ur
    ON ur.turn_id = t.turn_id
ORDER BY
    t.session_id,
    t.turn_number;



EXPLAIN QUERY PLAN
SELECT
    t.turn_id,
    t.session_id,
    js.helpfulness AS judge_helpfulness,
    ur.rating AS user_rating,
    js.judged_at,
    ur.rated_at
FROM turns AS t
JOIN judge_scores AS js
    ON js.turn_id = t.turn_id
JOIN user_ratings AS ur
    ON ur.turn_id = t.turn_id
WHERE js.helpfulness > 4
  AND ur.rating = 'thumbs_down'
ORDER BY
    t.session_id,
    t.turn_number;



EXPLAIN QUERY PLAN
SELECT
    t.turn_id,
    t.session_id,
    js.helpfulness AS judge_helpfulness,
    ur.rating AS user_rating,
    js.judged_at,
    ur.rated_at
FROM turns AS t
JOIN (
    SELECT *
    FROM judge_scores
    WHERE helpfulness > 4
) AS js
    ON js.turn_id = t.turn_id
JOIN (
    SELECT *
    FROM user_ratings
    WHERE rating = 'thumbs_down'
) AS ur
    ON ur.turn_id = t.turn_id
ORDER BY
    t.session_id,
    t.turn_number;