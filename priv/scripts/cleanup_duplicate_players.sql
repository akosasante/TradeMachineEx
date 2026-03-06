-- Cleanup Duplicate Players (consolidated)
-- =========================================
-- Handles two cases in a single pass:
--   A) Minor leaguer duplicates a major leaguer who has a playerDataId
--      → delete the minor leaguer (the major league row is canonical)
--   B) Multiple minor leaguers share the same name
--      → keep the best one, delete the rest
--
-- Uses TRIM() on name comparisons because some Google Sheet imports
-- leave trailing whitespace (e.g. "Korey Lee " vs "Korey Lee").
--
-- Only minor league rows (league='2') are ever deleted. Major league rows
-- are never touched.
--
-- Priority for ranking (best row = rn 1, kept):
--   1. Major league (league='1') with playerDataId — canonical ESPN record
--   2. Major league without playerDataId — still the promoted record
--   3. Has playerDataId (non-null) — already reconciled with ESPN
--   4. Has non-null meta — has sheet or ESPN data attached
--   5. Is owned (non-null leagueTeamId) — on a fantasy team
--   6. Most recently modified (dateModified DESC) — freshest data
--   7. id DESC — deterministic tiebreaker
--
-- Usage: Run against both prod and staging schemas.
--   psql -h <host> -p 5438 -U <user> -d <db> -f priv/scripts/cleanup_duplicate_players.sql

-- Step 0: Fix trailing/leading whitespace in player names (UNCOMMENT TO RUN)
-- BEGIN;
-- UPDATE player SET name = TRIM(name) WHERE name != TRIM(name);
-- COMMIT;

-- Step 1: Preview — show all duplicate name groups (DRY RUN)
SELECT
  TRIM(name) AS trimmed_name,
  COUNT(*) AS row_count,
  array_agg(league ORDER BY
    (league = '1') DESC,
    ("playerDataId" IS NOT NULL) DESC,
    (meta IS NOT NULL) DESC,
    ("leagueTeamId" IS NOT NULL) DESC,
    "dateModified" DESC,
    id DESC
  ) AS leagues,
  array_agg(id ORDER BY
    (league = '1') DESC,
    ("playerDataId" IS NOT NULL) DESC,
    (meta IS NOT NULL) DESC,
    ("leagueTeamId" IS NOT NULL) DESC,
    "dateModified" DESC,
    id DESC
  ) AS ids,
  array_agg("playerDataId" ORDER BY
    (league = '1') DESC,
    ("playerDataId" IS NOT NULL) DESC,
    (meta IS NOT NULL) DESC,
    ("leagueTeamId" IS NOT NULL) DESC,
    "dateModified" DESC,
    id DESC
  ) AS player_data_ids,
  array_agg("leagueTeamId" ORDER BY
    (league = '1') DESC,
    ("playerDataId" IS NOT NULL) DESC,
    (meta IS NOT NULL) DESC,
    ("leagueTeamId" IS NOT NULL) DESC,
    "dateModified" DESC,
    id DESC
  ) AS owner_ids
FROM player
GROUP BY TRIM(name)
HAVING COUNT(*) > 1
ORDER BY row_count DESC, trimmed_name;

-- Step 2: Preview — show delete candidates with trade item references (DRY RUN)
-- Rows with trade_item_count > 0 need their trade_item rows reassigned to the
-- keeper before deletion, otherwise those trades will silently lose items.
WITH ranked AS (
  SELECT
    id,
    TRIM(name) AS trimmed_name,
    league,
    ROW_NUMBER() OVER (
      PARTITION BY TRIM(name)
      ORDER BY
        (league = '1') DESC,
        ("playerDataId" IS NOT NULL) DESC,
        (meta IS NOT NULL) DESC,
        ("leagueTeamId" IS NOT NULL) DESC,
        "dateModified" DESC,
        id DESC
    ) AS rn
  FROM player
),
candidates AS (
  SELECT ranked.id, ranked.trimmed_name, ranked.rn
  FROM ranked
  WHERE ranked.rn > 1
    AND ranked.league = '2'
    AND ranked.trimmed_name IN (
      SELECT TRIM(name) FROM player
      GROUP BY TRIM(name) HAVING COUNT(*) > 1
    )
)
SELECT
  c.id,
  c.trimmed_name,
  c.rn,
  COUNT(ti.id) AS trade_item_count,
  CASE
    WHEN COUNT(ti.id) > 0 THEN 'HAS TRADES - REVIEW'
    ELSE 'SAFE TO DELETE'
  END AS status
FROM candidates c
LEFT JOIN trade_item ti
  ON ti."tradeItemId" = c.id
  AND ti."tradeItemType" = '1'
GROUP BY c.id, c.trimmed_name, c.rn
ORDER BY trade_item_count DESC, c.trimmed_name;

-- Step 3: Preview — full detail of which rows WOULD be deleted (DRY RUN)
WITH ranked AS (
  SELECT
    id,
    name,
    TRIM(name) AS trimmed_name,
    league,
    "playerDataId",
    meta IS NOT NULL AS has_meta,
    "leagueTeamId",
    "dateModified",
    ROW_NUMBER() OVER (
      PARTITION BY TRIM(name)
      ORDER BY
        (league = '1') DESC,
        ("playerDataId" IS NOT NULL) DESC,
        (meta IS NOT NULL) DESC,
        ("leagueTeamId" IS NOT NULL) DESC,
        "dateModified" DESC,
        id DESC
    ) AS rn
  FROM player
)
SELECT id, name, trimmed_name, league, "playerDataId", has_meta,
       "leagueTeamId", "dateModified", rn,
       CASE
         WHEN rn = 1 THEN 'KEEP'
         WHEN league = '1' THEN 'KEEP (major)'
         ELSE 'WOULD DELETE'
       END AS action
FROM ranked
WHERE trimmed_name IN (
  SELECT TRIM(name) FROM player
  GROUP BY TRIM(name) HAVING COUNT(*) > 1
)
ORDER BY trimmed_name, rn;

-- Step 4: REASSIGN trade items + DELETE duplicates (UNCOMMENT TO RUN)
-- This handles trade_item references automatically:
--   4a) Deletes duplicate trade_items where the keeper already appears in the same trade
--       (avoids unique constraint violation on tradeId+tradeItemId+type+sender+recipient)
--   4b) Reassigns remaining trade_items from duplicate players to their keepers
--   4c) Verifies no orphaned trade_item references remain
--   4d) Deletes the duplicate player rows
--
-- BEGIN;
--
-- -- 4a: Delete conflicting trade_items (keeper already in same trade slot)
-- WITH ranked AS (
--   SELECT id, TRIM(name) AS trimmed_name, league,
--     ROW_NUMBER() OVER (
--       PARTITION BY TRIM(name)
--       ORDER BY (league = '1') DESC, ("playerDataId" IS NOT NULL) DESC,
--         (meta IS NOT NULL) DESC, ("leagueTeamId" IS NOT NULL) DESC,
--         "dateModified" DESC, id DESC
--     ) AS rn
--   FROM player
-- ),
-- dupes AS (
--   SELECT TRIM(name) AS tn FROM player GROUP BY TRIM(name) HAVING COUNT(*) > 1
-- ),
-- keepers AS (
--   SELECT id AS keeper_id, trimmed_name
--   FROM ranked WHERE rn = 1 AND trimmed_name IN (SELECT tn FROM dupes)
-- ),
-- duplicates AS (
--   SELECT r.id AS dup_id, k.keeper_id
--   FROM ranked r
--   JOIN keepers k ON r.trimmed_name = k.trimmed_name
--   WHERE r.rn > 1 AND r.league = '2'
-- )
-- DELETE FROM trade_item
-- WHERE id IN (
--   SELECT dup_ti.id
--   FROM trade_item dup_ti
--   JOIN duplicates d ON dup_ti."tradeItemId" = d.dup_id AND dup_ti."tradeItemType" = '1'
--   JOIN trade_item keeper_ti
--     ON keeper_ti."tradeId" = dup_ti."tradeId"
--     AND keeper_ti."tradeItemId" = d.keeper_id
--     AND keeper_ti."tradeItemType" = dup_ti."tradeItemType"
--     AND keeper_ti."senderId" = dup_ti."senderId"
--     AND keeper_ti."recipientId" = dup_ti."recipientId"
-- );
--
-- -- 4b: Reassign remaining trade_items from duplicates to keepers
-- WITH ranked AS (
--   SELECT id, TRIM(name) AS trimmed_name, league,
--     ROW_NUMBER() OVER (
--       PARTITION BY TRIM(name)
--       ORDER BY (league = '1') DESC, ("playerDataId" IS NOT NULL) DESC,
--         (meta IS NOT NULL) DESC, ("leagueTeamId" IS NOT NULL) DESC,
--         "dateModified" DESC, id DESC
--     ) AS rn
--   FROM player
-- ),
-- dupes AS (
--   SELECT TRIM(name) AS tn FROM player GROUP BY TRIM(name) HAVING COUNT(*) > 1
-- ),
-- keepers AS (
--   SELECT id AS keeper_id, trimmed_name
--   FROM ranked WHERE rn = 1 AND trimmed_name IN (SELECT tn FROM dupes)
-- ),
-- duplicates AS (
--   SELECT r.id AS dup_id, k.keeper_id
--   FROM ranked r
--   JOIN keepers k ON r.trimmed_name = k.trimmed_name
--   WHERE r.rn > 1 AND r.league = '2'
-- )
-- UPDATE trade_item
-- SET "tradeItemId" = d.keeper_id
-- FROM duplicates d
-- WHERE trade_item."tradeItemId" = d.dup_id
--   AND trade_item."tradeItemType" = '1';
--
-- -- 4c: Verify no orphaned trade_item references (should return 0)
-- SELECT COUNT(*) AS orphan_check
-- FROM trade_item ti
-- LEFT JOIN player p ON p.id = ti."tradeItemId"
-- WHERE ti."tradeItemType" = '1' AND p.id IS NULL;
--
-- -- 4d: Delete the duplicate player rows
-- WITH ranked AS (
--   SELECT id, TRIM(name) AS trimmed_name, league,
--     ROW_NUMBER() OVER (
--       PARTITION BY TRIM(name)
--       ORDER BY (league = '1') DESC, ("playerDataId" IS NOT NULL) DESC,
--         (meta IS NOT NULL) DESC, ("leagueTeamId" IS NOT NULL) DESC,
--         "dateModified" DESC, id DESC
--     ) AS rn
--   FROM player
-- ),
-- to_delete AS (
--   SELECT ranked.id
--   FROM ranked
--   WHERE ranked.rn > 1
--     AND ranked.league = '2'
--     AND ranked.trimmed_name IN (
--       SELECT TRIM(name) FROM player
--       GROUP BY TRIM(name) HAVING COUNT(*) > 1
--     )
-- )
-- DELETE FROM player
-- WHERE id IN (SELECT id FROM to_delete);
--
-- -- Verify: no minor league dupes of major leaguers
-- SELECT TRIM(m.name), COUNT(*)
-- FROM player m
-- JOIN player mn ON TRIM(m.name) = TRIM(mn.name) AND m.id != mn.id
-- WHERE m.league = '1' AND mn.league = '2' AND m."playerDataId" IS NOT NULL
-- GROUP BY TRIM(m.name);
--
-- -- Verify: no duplicate minor leaguers
-- SELECT TRIM(name), COUNT(*)
-- FROM player
-- WHERE league = '2'
-- GROUP BY TRIM(name)
-- HAVING COUNT(*) > 1;
--
-- -- Verify: no orphaned trade_item references after delete
-- SELECT COUNT(*) AS final_orphan_check
-- FROM trade_item ti
-- LEFT JOIN player p ON p.id = ti."tradeItemId"
-- WHERE ti."tradeItemType" = '1' AND p.id IS NULL;
--
-- COMMIT;
