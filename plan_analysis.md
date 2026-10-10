# Query Plan Analysis

## 1. Overview

This document records the query execution plans and optimisation experiments conducted on the ScrollSense SQLite database. The main objective was to understand how SQLite executes the assignment queries, identify expensive operations, and evaluate whether suitable indexes and query rewrites improve performance.

The experiments were performed using DBeaver and SQLite's `EXPLAIN QUERY PLAN`. Execution times are observations from the local environment, so they may vary with caching, database state, and result-fetching overhead.

The original queries are retained in `queries.sql`. The additional indexes used in the experiments are defined in `indexes.sql`.

---

## 2. Baseline Query Plans

Before adding the new indexes, I inspected the execution plans for F1, F2, and F12. These plans help identify the tables SQLite scans, the indexes it uses, and operations that may require additional temporary storage.

### 2.1 F1 — Audio-track popularity

F1 joins impressions with videos, filters impressions from the rolling seven-day window with a non-null audio track, counts distinct videos per audio track, and returns the top 10 results.

**Baseline execution plan:**

```text
SCAN i USING COVERING INDEX ix_impressions_video_time
SEARCH v USING INDEX sqlite_autoindex_videos_1 (video_id=?)
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR count(DISTINCT)
USE TEMP B-TREE FOR ORDER BY
```

**Analysis:** SQLite scans the existing impressions index and looks up the corresponding video for each matching row. It then uses temporary B-trees for grouping, counting distinct videos, and sorting the results. These operations contribute to the query's cost.

### 2.2 F2 — Creator-level statistics

F2 joins creators, users, videos, impressions, and viewing segments to calculate creator-level statistics. The query uses left joins to retain creators even when matching records are absent.

**Baseline execution plan:**

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

**Analysis:** SQLite starts with creators and performs indexed lookups in the related tables. However, the joins can produce a large intermediate result, and the distinct counts require temporary B-trees. Sorting the final results also requires a temporary B-tree.

### 2.3 F12 — Sessions and completed viewing

F12 joins sessions, turns, recommendations, impressions, and viewing segments, filtering for viewing segments where `reached_end = 1`.

**Baseline execution plan:**

```text
SCAN vs
SEARCH i USING INDEX sqlite_autoindex_impressions_1 (impression_id=?)
SEARCH r USING INDEX ix_recommendations_video (video_id=?)
SEARCH t USING INDEX sqlite_autoindex_turns_1 (turn_id=?)
SEARCH s USING INDEX sqlite_autoindex_sessions_1 (session_id=?)
USE TEMP B-TREE FOR DISTINCT
```

**Analysis:** The plan begins by scanning the viewing segments table and then looks up related records using indexes. Since viewing segments contains millions of rows, scanning the table is a potentially expensive operation. This motivated testing an index that starts with the `reached_end` filter.

---

## 3. Task 1 — Database Size and Scan-Cost Estimate

The viewing segments table contains **7,350,347 rows**. The database page size is **4,096 bytes**, and the reported database allocation was approximately **700,424,192 bytes**.

Using these values, the average allocated space per row is approximately:

\frac{700,424,192}{7,350,347} \approx 95.29 \text{ bytes per row}

An approximate estimate of the number of rows that fit on a page is:

\left\lfloor \frac{4096}{95.29} \right\rfloor = 42

The estimated number of pages is therefore:

\left\lceil \frac{7,350,347}{42} \right\rceil \approx 175,009 \text{ pages}

These figures are estimates rather than an exact SQLite page-level scan count. Actual page occupancy depends on record headers, B-tree structure, free space, and other database overhead.

The estimate nevertheless illustrates why a full scan of a multi-million-row table can be expensive.

---

## 4. Task 2 — Index Optimisation

I tested three additional indexes targeting the access patterns observed in F1, F2, and F12.

### 4.1 Index definitions

The following indexes were added:

```sql
CREATE INDEX idx_impressions_time_video
ON impressions(occurred_at, video_id);

CREATE INDEX idx_f2_videos_creator_state
ON videos(creator_id, moderation_state);

CREATE INDEX idx_vs_reached_impression
ON viewing_segments(reached_end, impression_id);
```

The indexes were designed around the query filters and join conditions rather than adding indexes indiscriminately.

### 4.2 F1 — Plan before and after indexing

**Before:**

```text
SCAN i USING COVERING INDEX ix_impressions_video_time
SEARCH v USING INDEX sqlite_autoindex_videos_1 (video_id=?)
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR count(DISTINCT)
USE TEMP B-TREE FOR ORDER BY
```

**After:**

```text
SEARCH i USING COVERING INDEX idx_impressions_time_video (occurred_at>?)
SEARCH v USING INDEX sqlite_autoindex_videos_1 (video_id=?)
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR count(DISTINCT)
USE TEMP B-TREE FOR ORDER BY
```

The main change is that SQLite can search the new index using the `occurred_at` range condition instead of scanning the existing impressions index. The grouping, distinct-counting, and sorting operations remain unchanged.

**Observed timings:**

| Configuration | Execution time |
|---|---:|
| Without the new index | 20.000 s |
| With the new index | 2.354 s |

The observed query time decreased substantially, corresponding to an approximate speedup of:

\[
\frac{20.000}{2.354}\approx 8.50\times
\]

These are measured local timings, not a guarantee of the same speedup on other systems.

**Date-filter caveat:** The latest timestamp in the generated dataset was `2026-09-13T23:59:53Z`, while the experiment was conducted in October 2026. Consequently, the rolling seven-day query returned zero rows. I used a fixed cutoff of `2026-09-07` for diagnostic comparison. The zero-row result and the diagnostic timing should be interpreted in the context of this timestamp range.

### 4.3 F2 — Plan after indexing

The new composite index was intended to support the creator join and moderation-state condition together.

**Relevant lines from the plan after indexing:**

```text
SEARCH v USING INDEX idx_f2_videos_creator_state
(creator_id=? AND moderation_state=?) LEFT-JOIN
SEARCH i USING INDEX ix_impressions_video_time (video_id=?) LEFT-JOIN
SEARCH vs USING INDEX ix_viewing_segments_impression (impression_id=?) LEFT-JOIN
USE TEMP B-TREE FOR ORDER BY
```

SQLite uses the composite index for the videos lookup, applying both the creator and moderation-state conditions. The existing indexes continue to support the impressions and viewing-segments lookups.

F2 remained expensive in this dataset. The full query had previously taken approximately 1 hour, 59 minutes, and 9 seconds in one run; a count-wrapper experiment took approximately 1 hour, 28 minutes, and 31 seconds. These are not a controlled before-and-after pair, so they do not establish a reliable full-query speedup.

A smaller diagnostic lookup returned 18 rows in both tested cases, with observed timings of approximately 0.003 s and 0.002 s. This supports the correctness of that diagnostic comparison but should not be treated as a benchmark of the entire F2 query.

### 4.4 F12 — Plan after indexing

The index on `(reached_end, impression_id)` was intended to support both the completion filter and the subsequent lookup by impression ID.

**Before:**

```text
SCAN vs
SEARCH i USING INDEX sqlite_autoindex_impressions_1 (impression_id=?)
SEARCH r USING INDEX ix_recommendations_video (video_id=?)
SEARCH t USING INDEX sqlite_autoindex_turns_1 (turn_id=?)
SEARCH s USING INDEX sqlite_autoindex_sessions_1 (session_id=?)
USE TEMP B-TREE FOR DISTINCT
```

**After:**

```text
SEARCH vs USING COVERING INDEX idx_vs_reached_impression (reached_end=?)
SEARCH i USING INDEX sqlite_autoindex_impressions_1 (impression_id=?)
SEARCH r USING INDEX ix_recommendations_video (video_id=?)
SEARCH t USING INDEX sqlite_autoindex_turns_1 (turn_id=?)
SEARCH s USING INDEX sqlite_autoindex_sessions_1 (session_id=?)
USE TEMP B-TREE FOR DISTINCT
```

The important improvement in the plan is the change from scanning `viewing_segments` to searching the index for rows matching `reached_end = 1`. The remaining joins and the distinct operation are still present.

Both runs returned **210,602 rows**. The recorded timings were 1 minute 19 seconds without the new index and 2 minutes 13 seconds with it. Since these timings were not obtained under controlled, identical conditions, they do not establish that the index makes F12 slower. They do show that an improved-looking plan does not automatically guarantee a lower observed runtime in every experiment.

### 4.5 Index trade-offs

Indexes can reduce the amount of data SQLite needs to scan, but they also consume storage and add work during inserts, updates, and deletes. The new indexes should therefore be evaluated based on the queries they help, the workload's write activity, and their storage cost.

The composite index on viewing segments was preferred over an index on `reached_end` alone because it also contains `impression_id`, which is used in the following join.

---

## 5. Task 3 — Join Plans and Cost Analysis

This task examines how SQLite executes joins and compares simplified theoretical costs for different join algorithms.

### 5.1 Join 1 — Impressions and viewing segments

**Query:**

```sql
EXPLAIN QUERY PLAN
SELECT i.impression_id, i.video_id,
       vs.watch_seconds, vs.reached_end
FROM impressions AS i
JOIN viewing_segments AS vs
  ON vs.impression_id = i.impression_id;
```

**Observed plan:**

```text
SCAN vs
SEARCH i USING INDEX sqlite_autoindex_impressions_1 (impression_id=?)
```

SQLite scans viewing segments and looks up the matching impression using the primary-key index. This is an indexed nested-loop-style plan: for each row from the outer input, SQLite performs an indexed lookup in the other table.

The relevant table cardinalities are:

- Impressions: 15,000,000 rows
- Viewing segments: 7,350,347 rows

A naive nested-loop join without an index could require approximately:

\[
15,000,000\times7,350,347
\approx 1.103\times10^{14}
\]

tuple-pair comparisons. This is an illustrative worst-case comparison count, not the actual work performed by SQLite's indexed plan.

For comparison, a simplified sort-merge estimate is:

\[
N\log_2N+M\log_2M+(N+M)
\]

Using the two relation sizes gives approximately 547.6 million abstract work units. A simplified hash-join estimate is \(N+M\), or approximately 22.35 million row-processing units, assuming sufficient memory and ignoring implementation overhead.

These estimates are useful for understanding algorithmic differences, but their work units are not directly comparable to measured SQLite execution time.

### 5.2 Join 2 — Impressions and recommendations

**Query:**

```sql
EXPLAIN QUERY PLAN
SELECT i.impression_id, i.user_id,
       i.video_id, r.turn_id
FROM impressions AS i
JOIN recommendations AS r
  ON r.video_id = i.video_id;
```

**Observed plan:**

```text
SCAN r USING COVERING INDEX sqlite_autoindex_recommendations_3
SEARCH i USING INDEX ix_impressions_video_time (video_id=?)
```

SQLite scans the recommendations index and uses the existing impressions index to find matching records by video ID. The plan therefore uses an indexed lookup rather than comparing every recommendation against every impression.

### 5.3 Join order and intermediate results

The relevant table sizes in the session-related analysis were:

| Relation or join | Row count |
|---|---:|
| Sessions | 100,000 |
| Turns | 349,279 |
| Recommendations | 524,801 |
| Sessions joined with turns | 349,279 |
| Turns joined with recommendations | 524,801 |
| Full join result | 524,801 |

Starting with sessions and joining turns can produce an intermediate result of 349,279 rows. The observed SQLite plan for the related query instead began with recommendations, then looked up turns and sessions.

The smaller intermediate result alone does not prove that a join order is faster. The optimizer must also consider available indexes, selectivity, lookup costs, and the cost of later operations. SQLite's chosen plan is the actual plan reported by `EXPLAIN QUERY PLAN`; the alternative is a theoretical comparison rather than a measured improvement.

---

## 6. Task 4 — Predicate Pushdown

The original query joins turns with judge scores and user ratings, filters for helpfulness greater than 4 and a `thumbs_down` rating, and sorts by session and turn number.

### 6.1 Original query

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

### 6.2 Rewritten query with filters pushed down

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

The rewritten query applies each filter within its corresponding subquery. This expresses the intention to reduce the rows considered from `judge_scores` and `user_ratings` before joining them with turns.

### 6.3 Results and interpretation

Both versions returned **127 rows**.

| Version | Observed execution time |
|---|---:|
| Original query | 0.113 s |
| Rewritten query | 0.128 s |

The rewritten query was slightly slower in this run. This does not mean predicate pushdown is inherently worse. SQLite can transform equivalent SQL formulations into similar execution strategies, and the measured difference may reflect normal runtime variation.

The experiment demonstrates that rewriting SQL does not necessarily improve performance when the database optimizer already produces an effective plan.

**Execution-plan note:** The recorded experiment notes indicate that the two plans were effectively the same, but the exact line-by-line `EXPLAIN QUERY PLAN` output was not retained. Therefore, this document does not reproduce unverified plan text. The two queries can be checked directly in SQLite if exact output is required.

---

## 7. Overall Findings

The experiments highlighted several practical points about SQLite query optimisation:

1. **Index column order matters.** The index beginning with `occurred_at` allowed SQLite to search by the timestamp range in F1.
2. **Composite indexes can support multiple conditions.** The videos index supports the creator and moderation-state lookup in F2.
3. **Indexes can change the access path without removing later work.** F1 still requires grouping, distinct counting, and sorting after the index change.
4. **Execution plans and timings answer different questions.** A plan shows the selected operations, while a timing measures one execution under particular conditions.
5. **Query rewrites are not guaranteed to be faster.** The two predicate-pushdown versions returned the same number of rows and had similar recorded plans, with a small timing difference.
6. **Benchmark conditions matter.** The rolling timestamp window, result-fetching overhead, caching, and long-running queries can all affect observed timings.

Overall, the most convincing measured improvement was F1, where the timestamp index changed the plan from a scan to an indexed range search and the recorded runtime decreased substantially. For F2 and F12, the plans provide useful evidence of how SQLite uses the new indexes, but the available timing data is not sufficient to claim a controlled end-to-end speedup.

## 8. Reproducibility

To reproduce the analysis:

1. Use the database generated with the assignment's required scale.
2. Execute the original queries from `queries.sql` and record their baseline plans.
3. Apply the index definitions in `indexes.sql`.
4. Run `EXPLAIN QUERY PLAN` again for each query and compare the access paths.
5. Execute the original and rewritten Task 4 queries and compare their results.
6. Record timings together with the result counts and relevant database conditions.

The SQL scripts and inline comments in the repository provide the execution context for the experiments. Timings should be treated as environment-specific observations rather than guaranteed performance figures.
