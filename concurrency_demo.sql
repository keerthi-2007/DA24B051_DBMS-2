SELECT moderation_state
FROM videos
WHERE video_id = 'v_d8439725255f';
ROLLBACK;

UPDATE videos
SET moderation_state = 'pending'
WHERE video_id = 'v_d8439725255f';

SELECT video_id, moderation_state
FROM videos
WHERE video_id = 'v_d8439725255f';

PRAGMA busy_timeout;

PRAGMA journal_mode;

PRAGMA wal_checkpoint(PASSIVE);

BEGIN IMMEDIATE;

COMMIT;

UPDATE videos
SET moderation_state = 'live'
WHERE video_id = 'v_d8439725255f';

SELECT moderation_state
FROM videos
WHERE video_id = 'v_d8439725255f';


-- Task 5.3: SQLite write-lock experiment
-- Database: scrollsense_a2.db
-- Table: videos
-- Test video: v_d8439725255f
-- Original moderation_state: live
--
-- Connection A:
-- 1. BEGIN IMMEDIATE;
-- 2. UPDATE videos SET moderation_state = 'pending'
--    WHERE video_id = 'v_d8439725255f';
-- 3. Leave the transaction uncommitted.
--
-- Connection B:
-- 4. Execute BEGIN IMMEDIATE;
-- 5. Observed SQLITE_BUSY: database file is locked.
--
-- Connection A:
-- 6. COMMIT;
--
-- Connection B:
-- 7. Retry BEGIN IMMEDIATE; it succeeds after A commits.
-- 8. ROLLBACK;
--
-- Cleanup:
-- 9. Restore moderation_state to 'live'.
-- 10. Verify the final state is 'live'.
--
-- Result: SQLite permits only one active writer at a time.
-- BEGIN IMMEDIATE acquires the write reservation before
-- the transaction performs its updates.



SELECT moderation_state
FROM videos
WHERE video_id = 'v_d8439725255f';

UPDATE videos
SET moderation_state = 'pending'
WHERE video_id = 'v_d8439725255f';

UPDATE videos
SET moderation_state = 'live'
WHERE video_id = 'v_d8439725255f';

SELECT moderation_state
FROM videos
WHERE video_id = 'v_d8439725255f';

SELECT moderation_state
FROM videos
WHERE video_id = 'v_d8439725255f';


-- Task 5.2: Lost-update-style moderation experiment
-- Video: v_d8439725255f
--
-- 1. Connection A reads moderation_state = 'live'.
-- 2. Connection B reads moderation_state = 'live'.
-- 3. Connection A updates the state to 'pending'.
-- 4. Connection B updates the state to 'taken_down'
--    based on its earlier read.
-- 5. Final state observed: 'taken_down'.
--
-- This demonstrates a stale-decision overwrite:
-- Connection B's later write overwrites Connection A's
-- earlier update. The application-level decisions were
-- based on the same stale initial state.
--
-- Cleanup: restore the original state to 'live'.


SELECT video_id, moderation_state
FROM videos
WHERE video_id = 'v_d8439725255f';

UPDATE videos
SET moderation_state = 'taken_down'
WHERE video_id = 'v_d8439725255f';

SELECT moderation_state
FROM videos
WHERE video_id = 'v_d8439725255f';


--restore
UPDATE videos
SET moderation_state = 'live'
WHERE video_id = 'v_d8439725255f';

SELECT moderation_state
FROM videos
WHERE video_id = 'v_d8439725255f';


--task 5.3 checking
BEGIN IMMEDIATE;

SELECT moderation_state
FROM videos
WHERE video_id = 'v_d8439725255f';

UPDATE videos
SET moderation_state = 'taken_down'
WHERE video_id = 'v_d8439725255f';

SELECT moderation_state
FROM videos
WHERE video_id = 'v_d8439725255f';

--Now commit 
COMMIT;

```sql
-- ============================================================
-- FINAL EXECUTION GUIDE
-- Task 5: Concurrency, Schedules, and Isolation
-- ============================================================
--
-- PREREQUISITES
-- 1. Open the same scrollsense_a2.db file in two DBeaver
--    connections named Connection A and Connection B.
-- 2. Ensure both connections use SQLite WAL mode.
-- 3. Enable Auto-commit initially in both connections.
-- 4. The test video used below is v_d8439725255f.
--    Its original moderation_state is 'live'.
--
-- PART A: TASK 5.1 -- A1 T2 ISOLATION
-- Use the A1 G.3 T2 procedure documented in the report.
-- Connection A starts a transaction and inserts an uncommitted
-- moderation decision. While A's transaction is open, execute
-- the SELECT query in Connection B.
-- Verify that B sees the previously committed state rather than
-- A's uncommitted decision.
-- Finally, execute ROLLBACK in Connection A.
--
-- PART B: TASK 5.2 -- LOST UPDATE
-- Execute each statement separately, in this order:
-- 1. Connection A: SELECT the video's current moderation_state.
-- 2. Connection B: SELECT the same video's moderation_state.
-- 3. Connection A: UPDATE it to 'taken_down'.
-- 4. Connection B: UPDATE it to 'demoted'.
-- 5. Query the state and verify that it is 'demoted'.
-- These are separate autocommit statements. The final state
-- demonstrates the application-level lost update.
--
-- PART C: TASK 5.3 -- PREVENTION WITH BEGIN IMMEDIATE
-- 1. Restore the video's state to 'live'.
-- 2. Connection A: execute BEGIN IMMEDIATE.
-- 3. Connection A: SELECT the state, UPDATE it to 'taken_down',
--    and SELECT it again. Leave the transaction open.
-- 4. Connection B: attempt the competing UPDATE to 'demoted'.
-- 5. Record whether B waits or returns SQLITE_BUSY.
-- 6. Connection A: execute COMMIT.
-- 7. Connection B: retry its write only after reading the latest
--    state and deciding whether the update is still appropriate.
--
-- CLEANUP
-- Restore the test video's moderation_state to 'live' and verify:
--
-- SELECT video_id, moderation_state
-- FROM videos
-- WHERE video_id = 'v_d8439725255f';
--
-- Expected final state: live
--
-- IMPORTANT
-- Do not run all sections as one script. The concurrency tests
-- require statements to be executed manually and in order across
-- two separate connections. Keep Connection A's transaction open
-- at the specified points so Connection B can be tested.
-- ============================================================
```
