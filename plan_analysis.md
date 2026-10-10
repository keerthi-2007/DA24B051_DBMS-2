# Plan Analysis 

## 1. Overview

This document analyses the execution plans of selected queries from the ScrollSense database using SQLite's `EXPLAIN QUERY PLAN`. It identifies table scans, index searches, temporary B-trees, and the effect of additional indexes.

The analysis covers:

- **Task 1:** Original execution plans and scan-cost estimation.
- **Task 2:** Index selection and before/after execution-plan comparisons.
- **Task 3:** Join plans, cardinality estimates, and theoretical join-cost comparison.
- **Task 4:** Predicate pushdown and observed execution time.
- **Task 5:** Transaction behaviour and concurrency observations.

All plans and timings below are based on the observed database experiments. Timing results may include query execution and result-fetching overhead from DBeaver.

---

## 2. Task 1 — Original Query Plans

### 2.1 F1 — Audio Track Engagement

F1 joins `impressions` with `videos`, filters impressions by timestamp and non-null audio track, groups by audio track, and returns the top 10 tracks by distinct video count.

#### Original execution plan

```text
SCAN i USING COVERING INDEX ix_impressions_video_time
SEARCH v USING INDEX sqlite_autoindex_videos_1 (video_id=?)
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR count(DISTINCT)
USE TEMP B-TREE FOR ORDER BY
```

#### Analysis

- SQLite scans `ix_impressions_video_time` rather than performing a selective timestamp range search.
- For each matching impression, it searches `videos` using the primary-key index on `video_id`.
- Temporary B-trees are used for grouping, computing `COUNT(DISTINCT ...)`, and sorting the results.
- The original index begins with `video_id`, so it is not ideal for a query whose main selective predicate is on `occurred_at`.

**Potential improvement:** Add a composite index beginning with `occurred_at` and including `video_id`.

---

### 2.2 F2 — Creator and Viewing Analytics

F2 joins creators, users, videos, impressions, and viewing segments to compute creator-level analytics.

#### Original execution plan

```text
SCAN c USING INDEX sqlite_autoindex_creators_1
SEARCH u USING INDEX sqlite_autoindex_users_1 (user_id=?)
SEARCH v USING INDEX ix_videos_moderation_state (moderation_state=?) LEFT-JOIN
SEARCH i USING INDEX ix_impressions_video_time (video_id=?) LEFT-JOIN
SEARCH vs USING INDEX ix_viewing_segments_impression (impression_id=?) LEFT-JOIN
USE TEMP B-TREE FOR count(DISTINCT)
USE TEMP B-TREE FOR count(DISTINCT)
USE TEMP B-TREE FOR count(DISTINCT)
USE TEMP B-TREE FOR ORDER BY
```

#### Analysis

- SQLite scans creators and looks up the corresponding user rows through the user primary-key index.
- Videos are accessed using the index on `moderation_state`.
- Impressions and viewing segments are accessed through indexes on their join columns.
- The three distinct-count aggregates and final ordering require temporary B-trees.
- Although indexes are used, the query can still be expensive because of the large number of joined rows and distinct aggregations.

**Potential improvement:** Add a composite index on `videos(creator_id, moderation_state)` to support lookups using both the creator and moderation state.

The full F2 query was very expensive in the observed experiment. No reliable before/after full-query runtime comparison was obtained, so a full-query speedup is not claimed.

---

### 2.3 F12 — Completed Viewing Sessions

F12 joins sessions, turns, recommendations, impressions, and viewing segments, filtering for rows where `reached_end = 1`.

#### Original execution plan

```text
SCAN vs
SEARCH i USING INDEX sqlite_autoindex_impressions_1 (impression_id=?)
SEARCH r USING INDEX ix_recommendations_video (video_id=?)
SEARCH t USING INDEX sqlite_autoindex_turns_1 (turn_id=?)
SEARCH s USING INDEX sqlite_autoindex_sessions_1 (session_id=?)
USE TEMP B-TREE FOR DISTINCT
```

#### Analysis

- SQLite scans the `viewing_segments` table.
- It then performs indexed lookups into impressions, recommendations, turns, and sessions.
- The scan is a potential bottleneck because `viewing_segments` contains approximately 7.35 million rows.
- A composite index beginning with `reached_end` can help SQLite locate qualifying rows and provide `impression_id` for the subsequent join.

**Potential improvement:** Add a composite index on `viewing_segments(reached_end, impression_id)`.

---

## 3. Task 1 — Scan-Cost Estimation

The following values were measured from the database:

| Metric | Value |
|---|---:|
| Rows in `viewing_segments` | 7,350,347 |
| SQLite page size | 4,096 bytes |
| Allocated bytes reported by `dbstat` | 700,424,192 bytes |
| Average allocated bytes per row | Approximately 95.29 bytes |

The average allocated bytes per row are estimated as:

\[
\frac{700,424,192}{7,350,347}
\approx 95.29 \text{ bytes/row}
\]

Using this average, the estimated number of rows per 4,096-byte page is:

\[
\left\lfloor\frac{4096}{95.29}\right\rfloor=42
\]

The approximate number of pages required for a full scan is therefore:

\[
\left\lceil\frac{7,350,347}{42}\right\rceil
=175,009
\]

These are approximate estimates, not exact physical page counts for the table. The `dbstat` allocation can include B-tree and record overhead, unused space, and other storage effects. The estimate is useful for understanding the scale of scanning the table, but it should not be interpreted as an exact I/O count.

---

## 4. Task 2 — Index Selection and Execution-Plan Changes

### 4.1 F1 — Timestamp-Based Filtering

#### Index added

```sql
CREATE INDEX idx_impressions_time_video
ON impressions(occurred_at, video_id);
```

#### Before adding the index

```text
SCAN i USING COVERING INDEX ix_impressions_video_time
SEARCH v USING INDEX sqlite_autoindex_videos_1 (video_id=?)
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR count(DISTINCT)
USE TEMP B-TREE FOR ORDER BY
```

#### After adding the index

```text
SEARCH i USING COVERING INDEX idx_impressions_time_video (occurred_at>?)
SEARCH v USING INDEX sqlite_autoindex_videos_1 (video_id=?)
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR count(DISTINCT)
USE TEMP B-TREE FOR ORDER BY
```

#### Analysis

The important change is from a full index scan to a range search on `occurred_at`. Because `occurred_at` is the leading column of the new composite index, SQLite can navigate to the relevant timestamp range instead of scanning the entire existing index.

The lookup into `videos` and the temporary B-trees remain because the join, grouping, distinct count, and ordering requirements have not changed.

For a fixed diagnostic cutoff of `'2026-09-07'`, the observed timings were:

| Configuration | Observed time |
|---|---:|
| Without the new index | Approximately 20 seconds |
| With the new index | Approximately 2.354 seconds |

The measured query time was approximately 8.5 times lower with the new index in this experiment. These timings are approximate and may include DBeaver result-fetching overhead.

**Note:** The dataset's maximum `occurred_at` was `2026-09-13T23:59:53Z`, while the rolling seven-day query was being evaluated around October 2026. Consequently, the original rolling-window query returned zero rows for that data. The fixed cutoff was used for the diagnostic comparison and should not be confused with a change to the original query's intended logic.

---

### 4.2 F2 — Creator and Moderation-State Lookup

#### Index added

```sql
CREATE INDEX idx_f2_videos_creator_state
ON videos(creator_id, moderation_state);
```

#### Before adding the index

The video lookup used:

```text
SEARCH v USING INDEX ix_videos_moderation_state (moderation_state=?) LEFT-JOIN
```

#### After adding the index

The video lookup changed to:

```text
SEARCH v USING INDEX idx_f2_videos_creator_state
(creator_id=? AND moderation_state=?) LEFT-JOIN
```

The remaining impression and viewing-segment lookups continued to use their existing indexes.

#### Analysis

The composite index supports a lookup involving both `creator_id` and `moderation_state`. This is more directly aligned with the combined conditions than using an index whose leading column is only `moderation_state`.

However, the full F2 query took a very long time in the experiments, and a reliable paired full-query timing comparison was not obtained. Small diagnostic count queries returned 18 rows in both tested configurations, with observed times around 0.003 seconds and 0.002 seconds. These diagnostic timings do not establish a full-query performance improvement.

The index is therefore justified by the execution-plan change, not by a proven full-query speedup.

---

### 4.3 F12 — Filtering Completed Viewing Segments

#### Index added

```sql
CREATE INDEX idx_vs_reached_impression
ON viewing_segments(reached_end, impression_id);
```

#### Before adding the index

```text
SCAN vs
SEARCH i USING INDEX sqlite_autoindex_impressions_1 (impression_id=?)
SEARCH r USING INDEX ix_recommendations_video (video_id=?)
SEARCH t USING INDEX sqlite_autoindex_turns_1 (turn_id=?)
SEARCH s USING INDEX sqlite_autoindex_sessions_1 (session_id=?)
USE TEMP B-TREE FOR DISTINCT
```

#### After adding the index

```text
SEARCH vs USING COVERING INDEX idx_vs_reached_impression (reached_end=?)
SEARCH i USING INDEX sqlite_autoindex_impressions_1 (impression_id=?)
SEARCH r USING INDEX ix_recommendations_video (video_id=?)
SEARCH t USING INDEX sqlite_autoindex_turns_1 (turn_id=?)
SEARCH s USING INDEX sqlite_autoindex_sessions_1 (session_id=?)
USE TEMP B-TREE FOR DISTINCT
```

#### Analysis

The original plan scanned `viewing_segments`. The new plan searches the composite index using `reached_end` and can obtain `impression_id` from the same index.

The composite index was chosen instead of an index on `reached_end` alone because the query both filters on `reached_end` and joins using `impression_id`.

The full query returned 210,602 rows in both experiments. The observed times were approximately 1 minute 19 seconds without the new index and 2 minutes 13 seconds with it. Since these measurements include uncontrolled execution and result-fetching effects, the timing difference is not treated as evidence that the index makes the query slower. The clear observed improvement is the execution-plan change from scanning `viewing_segments` to searching the composite index.

---

## 5. Task 3 — Join Plan Analysis

### 5.1 Join: Impressions and Viewing Segments

#### Query

```sql
EXPLAIN QUERY PLAN
SELECT i.impression_id,
       i.video_id,
       vs.watch_seconds,
       vs.reached_end
FROM impressions AS i
JOIN viewing_segments AS vs
  ON vs.impression_id = i.impression_id;
```

#### Observed plan

```text
SCAN vs
SEARCH i USING INDEX sqlite_autoindex_impressions_1 (impression_id=?)
```

#### Analysis

SQLite scans `viewing_segments` and uses the primary-key index on `impressions.impression_id` to look up the matching impression for each viewing segment.

This is an indexed nested-loop-style plan. The `EXPLAIN QUERY PLAN` output shows a scan followed by indexed searches; it does not explicitly print the name of the join algorithm.

The main cost is potentially the scan of the large `viewing_segments` relation.

---

### 5.2 Join: Impressions and Recommendations

#### Query

```sql
EXPLAIN QUERY PLAN
SELECT i.impression_id,
       i.user_id,
       i.video_id,
       r.turn_id
FROM impressions AS i
JOIN recommendations AS r
  ON r.video_id = i.video_id;
```

#### Observed plan

```text
SCAN r USING COVERING INDEX sqlite_autoindex_recommendations_3
SEARCH i USING INDEX ix_impressions_video_time (video_id=?)
```

#### Analysis

SQLite scans the recommendations index and uses `ix_impressions_video_time` to search impressions by `video_id`.

The plan uses an indexed search rather than an explicit full scan of impressions for every recommendation. The recommendations index is covering for the columns SQLite needs from that side of the join.

---

### 5.3 Approximate Join-Cost Comparison

The measured relation sizes were:

| Relation | Rows |
|---|---:|
| `impressions` | 15,000,000 |
| `viewing_segments` | 7,350,347 |

For illustration, let:

\[
N=15,000,000,\qquad M=7,350,347
\]

#### Unindexed nested-loop comparison

A basic unindexed nested-loop comparison has a rough pairwise work estimate of:

\[
N\times M
=15,000,000\times7,350,347
\approx1.103\times10^{14}
\]

This is approximately 110.3 trillion tuple-pair comparisons.

#### Sort-merge comparison

Using the simplified estimate \(N\log_2N+M\log_2M+(N+M)\):

\[
N\log_2N\approx357.6\text{ million}
\]

\[
M\log_2M\approx167.7\text{ million}
\]

\[
N+M=22,350,347
\]

The combined estimate is approximately 547.6 million abstract work units.

#### Hash-join comparison

Under the simplified assumption of suitable memory and efficient hashing, the estimate is:

\[
N+M=22,350,347
\]

or approximately 22.35 million abstract work units.

#### Interpretation

These figures illustrate the theoretical differences between the simplified algorithms. They are not directly comparable measurements of CPU instructions or disk I/O, and they do not prove that SQLite would execute a hash join faster for this database.

The observed SQLite plans use indexed lookups. The existing indexes and actual data distribution influence the cost of these plans.

---

### 5.4 Join Order and Intermediate Cardinalities

The observed relation sizes were:

| Relation | Rows |
|---|---:|
| `sessions` | 100,000 |
| `turns` | 349,279 |
| `recommendations` | 524,801 |

The observed intermediate cardinalities were:

| Join | Result rows |
|---|---:|
| `sessions JOIN turns` | 349,279 |
| `turns JOIN recommendations` | 524,801 |
| Complete join | 524,801 |

Joining sessions to turns first creates an intermediate result of 349,279 rows, which is smaller than the observed 524,801-row intermediate result for turns joined with recommendations.

This provides a possible reason to investigate a sessions-first join order. However, intermediate cardinality alone does not prove that this order is faster: index availability, join selectivity, row width, and the cost of subsequent joins also matter.

The observed SQLite plan began with recommendations and then searched turns and sessions. No claim is made that the alternative order would necessarily improve runtime.

---

## 6. Task 4 — Predicate Pushdown

### 6.1 Original Query

```sql
SELECT t.turn_id,
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
ORDER BY t.session_id, t.turn_number;
```

### 6.2 Rewritten Query

The rewritten version applies the predicates inside subqueries before joining:

```sql
SELECT t.turn_id,
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
ORDER BY t.session_id, t.turn_number;
```

### 6.3 Observed Results

| Measurement | Original | Rewritten |
|---|---:|---:|
| Result rows | 127 | 127 |
| Observed time | 0.113 s | 0.128 s |

Both queries returned 127 rows, and their execution plans were effectively the same.

SQLite can optimize the predicates and subqueries internally, so the rewritten SQL does not necessarily result in a different physical execution plan. In this experiment, the rewritten query was slightly slower according to the observed timings.

**Conclusion:** Predicate pushdown was tested, but no runtime improvement was demonstrated.

---

## 7. Task 5 — Concurrency Observations

This section summarizes the observed transaction experiments. The detailed, step-by-step procedures are maintained separately in `concurrency_demo.sql`.

### 7.1 Isolation Experiment

In the earlier A1 experiment, Connection A inserted a moderation decision but did not commit it immediately. Connection B read the previously committed video state and observed `live`.

Because A inserted a separate row and B read the existing video row, these operations did not create a conflict cycle. The observed behaviour is consistent with a serial order in which B's read occurs before A's insertion and commit.

This experiment demonstrates visibility of committed data; it does not demonstrate a non-serializable schedule.

The A1 experiment uses the earlier schema and should be treated as an A1 result rather than executed unmodified against the A2 database.

### 7.2 Lost-Update Demonstration

Two autocommit connections read the same initial moderation state, `live`. Connection A then updated the state to `taken_down`, while Connection B subsequently updated it to `demoted`.

The final value was `demoted`, overwriting A's update. This demonstrates an application-level lost update caused by separate reads and writes without a transaction spanning the entire read-modify-write operation.

### 7.3 Prevention Using `BEGIN IMMEDIATE`

Connection A began a write transaction using:

```sql
BEGIN IMMEDIATE;
```

It read the current state and updated the video to `taken_down`, keeping the transaction open. Connection B then attempted a conflicting update and received a SQLite busy/database-locked error while A held the write transaction.

After A committed, B could retry its operation. This serializes the competing writes but can reduce write concurrency and require retry handling.

The test video was restored to `live` after the experiment, and the final state was verified.

---

## 8. Summary of Index Changes

The following indexes were added for the investigated queries:

```sql
CREATE INDEX idx_impressions_time_video
ON impressions(occurred_at, video_id);

CREATE INDEX idx_f2_videos_creator_state
ON videos(creator_id, moderation_state);

CREATE INDEX idx_vs_reached_impression
ON viewing_segments(reached_end, impression_id);
```

| Query | Main plan change | Performance conclusion |
|---|---|---|
| F1 | Full index scan changed to timestamp range search | Observed diagnostic timing improved from about 20 s to 2.354 s |
| F2 | Video lookup uses both `creator_id` and `moderation_state` | No reliable full-query timing comparison |
| F12 | Viewing-segment scan changed to composite-index search | Same 210,602 result rows; timing was inconclusive |

The indexes should be evaluated against the workload as a whole. Additional indexes require storage and can add overhead to inserts, updates, and deletes. The final decision should consider query plans, representative workloads, and repeatable measurements rather than relying on a single timing.

---

## 9. Reproducibility Notes

- Use SQLite's `EXPLAIN QUERY PLAN` to capture the plans.
- Compare plans before and after creating the indexes.
- Use the same query text, database state, and cutoff when comparing runtimes.
- Record whether timing includes result fetching in DBeaver.
- Do not interpret a single noisy timing as proof of an improvement or regression.
- Keep the detailed index definitions in `indexes.sql` and the transaction procedures in `concurrency_demo.sql`.
- Keep this file as the written explanation of the observed plans and experimental limitations.
