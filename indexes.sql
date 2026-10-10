-- Checking the counts of the tables 
SELECT 'users' AS table_name, COUNT(*) AS row_count FROM users
UNION ALL
SELECT 'videos', COUNT(*) FROM videos
UNION ALL
SELECT 'impressions', COUNT(*) FROM impressions
UNION ALL
SELECT 'sessions', COUNT(*) FROM sessions;

--F1
EXPLAIN QUERY PLAN
SELECT
    v.audio_track_id,
    COUNT(DISTINCT v.video_id) AS distinct_videos
FROM impressions i
JOIN videos v ON v.video_id = i.video_id
WHERE v.audio_track_id IS NOT NULL
  AND i.occurred_at >= datetime('now', '-7 days')
GROUP BY v.audio_track_id
ORDER BY distinct_videos DESC
LIMIT 10;

--F2
EXPLAIN QUERY PLAN
SELECT
    c.creator_id,
    u.current_handle,
    COUNT(DISTINCT v.video_id) AS live_videos,
    COUNT(DISTINCT i.impression_id) AS impressions,
    COUNT(DISTINCT vs.segment_id) AS segments
FROM creators c
JOIN users u ON u.user_id = c.user_id
LEFT JOIN videos v
    ON v.creator_id = c.creator_id
   AND v.moderation_state = 'live'
LEFT JOIN impressions i
    ON i.video_id = v.video_id
LEFT JOIN viewing_segments vs
    ON vs.impression_id = i.impression_id
GROUP BY c.creator_id, u.current_handle
ORDER BY impressions DESC;

--F12
EXPLAIN QUERY PLAN
SELECT DISTINCT
    s.session_id,
    s.user_id,
    r.recommendation_id,
    r.video_id
FROM sessions s
JOIN turns t
    ON t.session_id = s.session_id
JOIN recommendations r
    ON r.turn_id = t.turn_id
JOIN impressions i
    ON i.video_id = r.video_id
JOIN viewing_segments vs
    ON vs.impression_id = i.impression_id
WHERE vs.reached_end = 1;

--find the count of viewing segments
SELECT COUNT(*) AS viewing_segments_count
FROM viewing_segments;

PRAGMA page_size;

SELECT
    name,
    SUM(pgsize) AS bytes
FROM dbstat
WHERE name = 'viewing_segments'
GROUP BY name;

--F12
SELECT DISTINCT
    s.session_id,
    t.turn_id,
    r.recommendation_id,
    i.impression_id,
    vs.segment_id
FROM sessions s
JOIN turns t
    ON t.session_id = s.session_id
JOIN recommendations r
    ON r.turn_id = t.turn_id
JOIN impressions i
    ON i.video_id = r.video_id
JOIN viewing_segments vs
    ON vs.impression_id = i.impression_id
WHERE vs.reached_end = 1;

--F2 explain Query - Task 2
EXPLAIN QUERY PLAN
SELECT
    c.creator_id,
    COALESCE(
        SUM(vs.watch_seconds) / 3600.0,
        0
    ) AS total_watch_hours,
    COALESCE(
        AVG(
            CASE
                WHEN vs.segment_id IS NOT NULL
                THEN vs.reached_end
            END
        ),
        0
    ) AS mean_completion_rate
FROM creators AS c
LEFT JOIN videos AS v
    ON v.creator_id = c.creator_id
   AND v.moderation_state = 'live'
LEFT JOIN impressions AS i
    ON i.video_id = v.video_id
LEFT JOIN viewing_segments AS vs
    ON vs.impression_id = i.impression_id
GROUP BY c.creator_id
ORDER BY total_watch_hours DESC, c.creator_id;

--F2 query running 
SELECT
    c.creator_id,
    COALESCE(SUM(vs.watch_seconds) / 3600.0, 0) AS total_watch_hours,
    COALESCE(
        AVG(
            CASE
                WHEN vs.segment_id IS NOT NULL
                THEN vs.reached_end
            END
        ),
        0
    ) AS mean_completion_rate
FROM creators AS c
LEFT JOIN videos AS v
    ON v.creator_id = c.creator_id
   AND v.moderation_state = 'live'
LEFT JOIN impressions AS i
    ON i.video_id = v.video_id
LEFT JOIN viewing_segments AS vs
    ON vs.impression_id = i.impression_id
GROUP BY c.creator_id
ORDER BY total_watch_hours DESC, c.creator_id;

CREATE INDEX idx_f2_videos_creator_state
ON videos(creator_id, moderation_state);



SELECT COUNT(*)
FROM (
    SELECT
        c.creator_id,
        COALESCE(SUM(vs.watch_seconds) / 3600.0, 0) AS total_watch_hours,
        COALESCE(
            AVG(CASE
                WHEN vs.segment_id IS NOT NULL THEN vs.reached_end
            END),
            0
        ) AS mean_completion_rate
    FROM creators AS c
    LEFT JOIN videos AS v
        ON v.creator_id = c.creator_id
       AND v.moderation_state = 'live'
    LEFT JOIN impressions AS i
        ON i.video_id = v.video_id
    LEFT JOIN viewing_segments AS vs
        ON vs.impression_id = i.impression_id
    GROUP BY c.creator_id
    ORDER BY total_watch_hours DESC, c.creator_id
);


CREATE INDEX idx_f2_videos_creator_state
ON videos(creator_id, moderation_state);


EXPLAIN QUERY PLAN
SELECT
    c.creator_id,
    COALESCE(SUM(vs.watch_seconds) / 3600.0, 0) AS total_watch_hours,
    COALESCE(
        AVG(CASE
            WHEN vs.segment_id IS NOT NULL THEN vs.reached_end
        END),
        0
    ) AS mean_completion_rate
FROM creators AS c
LEFT JOIN videos AS v
    ON v.creator_id = c.creator_id
   AND v.moderation_state = 'live'
LEFT JOIN impressions AS i
    ON i.video_id = v.video_id
LEFT JOIN viewing_segments AS vs
    ON vs.impression_id = i.impression_id
GROUP BY c.creator_id
ORDER BY total_watch_hours DESC, c.creator_id;


PRAGMA index_list('videos');


SELECT COUNT(*)
FROM videos AS v INDEXED BY ix_videos_creator
WHERE v.creator_id = 'cr_0d0964fc7278'
  AND v.moderation_state = 'live';


SELECT COUNT(*)
FROM videos AS v INDEXED BY idx_f2_videos_creator_state
WHERE v.creator_id = 'cr_0d0964fc7278'
  AND v.moderation_state = 'live';


PRAGMA index_list('impressions');


PRAGMA index_list('viewing_segments');


EXPLAIN QUERY PLAN
SELECT DISTINCT
    s.session_id,
    t.turn_id,
    r.recommendation_id,
    i.impression_id,
    vs.segment_id
FROM sessions s
JOIN turns t
    ON t.session_id = s.session_id
JOIN recommendations r
    ON r.turn_id = t.turn_id
JOIN impressions i
    ON i.video_id = r.video_id
JOIN viewing_segments vs
    ON vs.impression_id = i.impression_id
WHERE vs.reached_end = 1;

CREATE INDEX idx_vs_reached_impression
ON viewing_segments(reached_end, impression_id);

EXPLAIN QUERY PLAN
SELECT DISTINCT
    s.session_id,
    t.turn_id,
    r.recommendation_id,
    i.impression_id,
    vs.segment_id
FROM sessions s
JOIN turns t ON t.session_id = s.session_id
JOIN recommendations r ON r.turn_id = t.turn_id
JOIN impressions i ON i.video_id = r.video_id
JOIN viewing_segments vs ON vs.impression_id = i.impression_id
WHERE vs.reached_end = 1;


PRAGMA index_list('recommendations');


EXPLAIN QUERY PLAN
SELECT
    v.audio_track_id,
    COUNT(DISTINCT v.video_id) AS video_count
FROM impressions AS i
JOIN videos AS v
    ON v.video_id = i.video_id
WHERE v.audio_track_id IS NOT NULL
  AND i.occurred_at >= datetime('now', '-7 days')
GROUP BY v.audio_track_id
ORDER BY video_count DESC
LIMIT 10;


PRAGMA index_list('impressions');


PRAGMA index_info('ix_impressions_video_time');

CREATE INDEX idx_impressions_time_video
ON impressions(occurred_at, video_id);

SELECT
    v.audio_track_id,
    COUNT(DISTINCT v.video_id) AS distinct_videos
FROM impressions i
JOIN videos v
    ON v.video_id = i.video_id
WHERE v.audio_track_id IS NOT NULL
  AND i.occurred_at >= datetime('now', '-7 days')
GROUP BY v.audio_track_id
ORDER BY distinct_videos DESC
LIMIT 10;

SELECT COUNT(*) AS recent_impressions
FROM impressions
WHERE occurred_at >= datetime('now', '-7 days');


SELECT
    MIN(occurred_at) AS oldest_impression,
    MAX(occurred_at) AS newest_impression
FROM impressions;


SELECT
    datetime('now') AS sqlite_now,
    datetime('now', '-7 days') AS cutoff,
    COUNT(*) AS total_impressions,
    SUM(occurred_at >= datetime('now', '-7 days')) AS recent_count
FROM impressions;


SELECT COUNT(*) AS recent_impressions
FROM impressions
WHERE julianday(occurred_at) >= julianday('now', '-7 days');

SELECT
    v.audio_track_id,
    COUNT(DISTINCT v.video_id) AS distinct_videos
FROM impressions i
JOIN videos v ON v.video_id = i.video_id
WHERE v.audio_track_id IS NOT NULL
  AND julianday(i.occurred_at) >= julianday('2026-09-07')
GROUP BY v.audio_track_id
ORDER BY distinct_videos DESC
LIMIT 10;


SELECT
    v.audio_track_id,
    COUNT(DISTINCT v.video_id) AS distinct_videos
FROM impressions i
JOIN videos v ON v.video_id = i.video_id
WHERE v.audio_track_id IS NOT NULL
  AND julianday(i.occurred_at) >= julianday('2026-09-07')
GROUP BY v.audio_track_id
ORDER BY distinct_videos DESC
LIMIT 10;


DROP INDEX idx_impressions_time_video;


CREATE INDEX idx_impressions_time_video
ON impressions(occurred_at, video_id);

PRAGMA index_list('impressions');

PRAGMA index_list('videos');



-- F2 · Watch hours and mean completion rate per creator, live clips only.

SELECT
    c.creator_id,

    COALESCE(
        SUM(vs.watch_seconds) / 3600.0,
        0
    ) AS total_watch_hours,

    COALESCE(
        AVG(
            CASE
                WHEN vs.segment_id IS NOT NULL
                THEN vs.reached_end
            END
        ),
        0
    ) AS mean_completion_rate

FROM creators AS c

LEFT JOIN videos AS v
    ON v.creator_id = c.creator_id
   AND v.moderation_state = 'live'

LEFT JOIN impressions AS i
    ON i.video_id = v.video_id

LEFT JOIN viewing_segments AS vs
    ON vs.impression_id = i.impression_id

GROUP BY c.creator_id
ORDER BY total_watch_hours DESC, c.creator_id;


SELECT COUNT(*)
FROM videos AS v INDEXED BY idx_f2_videos_creator_state
WHERE v.creator_id = 'cr_0d0964fc7278'
  AND v.moderation_state = 'live';


SELECT COUNT(*)
FROM videos AS v INDEXED BY ix_videos_creator
WHERE v.creator_id = 'cr_0d0964fc7278'
  AND v.moderation_state = 'live';

PRAGMA index_list('viewing_segments');

SELECT COUNT(*)
FROM viewing_segments INDEXED BY idx_vs_reached_impression
WHERE reached_end = 1;


SELECT COUNT(*)
FROM viewing_segments NOT INDEXED
WHERE reached_end = 1;



SELECT DISTINCT
    s.session_id,
    t.turn_id,
    r.video_id
FROM sessions AS s
JOIN turns AS t
    ON t.session_id = s.session_id
JOIN recommendations AS r
    ON r.turn_id = t.turn_id
JOIN impressions AS i
    ON i.video_id = r.video_id
JOIN viewing_segments AS vs
    ON vs.impression_id = i.impression_id
WHERE vs.reached_end = 1;

DROP INDEX idx_vs_reached_impression;


CREATE INDEX idx_vs_reached_impression
ON viewing_segments(reached_end, impression_id);


EXPLAIN QUERY PLAN
SELECT DISTINCT
    s.session_id,
    t.turn_id,
    r.video_id
FROM sessions AS s
JOIN turns AS t
    ON t.session_id = s.session_id
JOIN recommendations AS r
    ON r.turn_id = t.turn_id
JOIN impressions AS i
    ON i.video_id = r.video_id
JOIN viewing_segments AS vs
    ON vs.impression_id = i.impression_id
WHERE vs.reached_end = 1;


DROP INDEX idx_impressions_time_video;

SELECT
    v.audio_track_id,
    COUNT(DISTINCT v.video_id) AS distinct_videos
FROM impressions i
JOIN videos v ON v.video_id = i.video_id
WHERE v.audio_track_id IS NOT NULL
  AND i.occurred_at >= '2026-09-07'
GROUP BY v.audio_track_id
ORDER BY distinct_videos DESC

PRAGMA index_list('impressions');

CREATE INDEX idx_impressions_time_video
ON impressions(occurred_at, video_id);


EXPLAIN QUERY PLAN
SELECT
    v.audio_track_id,
    COUNT(DISTINCT v.video_id) AS distinct_videos
FROM impressions i
JOIN videos v ON v.video_id = i.video_id
WHERE v.audio_track_id IS NOT NULL
  AND i.occurred_at >= '2026-09-07'
GROUP BY v.audio_track_id
ORDER BY distinct_videos DESC
LIMIT 10;