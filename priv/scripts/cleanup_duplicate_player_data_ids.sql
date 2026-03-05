-- Cleanup Duplicate playerDataId Rows
-- ====================================
-- Problem: Multiple player rows can share the same playerDataId (e.g. ESPN renamed
-- a player, creating a second DB row with the new name). The unique constraint on
-- (name, playerDataId) then prevents the sync from updating the stale row.
--
-- Strategy: For each duplicated playerDataId, keep the BEST row and delete the rest.
-- Priority for "best":
--   1. Owned (non-null leagueTeamId) — preserves fantasy team ownership
--   2. Most recently modified (dateModified DESC) — freshest data
--   3. id DESC — deterministic tiebreaker
-- The next ESPN sync will update the kept row's name/meta to the current ESPN values.
--
-- Usage: Run against both prod and staging schemas.
--   psql -h <host> -p 5438 -U <user> -d <db> -f priv/scripts/cleanup_duplicate_player_data_ids.sql

-- Step 1: Preview — show all duplicate groups (DRY RUN)
SELECT
  "playerDataId",
  COUNT(*) AS row_count,
  array_agg(id ORDER BY ("leagueTeamId" IS NOT NULL) DESC, "dateModified" DESC) AS ids,
  array_agg(name ORDER BY ("leagueTeamId" IS NOT NULL) DESC, "dateModified" DESC) AS names,
  array_agg("dateModified" ORDER BY ("leagueTeamId" IS NOT NULL) DESC, "dateModified" DESC) AS dates_modified,
  array_agg("leagueTeamId" ORDER BY ("leagueTeamId" IS NOT NULL) DESC, "dateModified" DESC) AS owner_ids
FROM player
WHERE "playerDataId" IS NOT NULL
GROUP BY "playerDataId"
HAVING COUNT(*) > 1
ORDER BY row_count DESC;

-- Step 2: Preview — show delete candidates with trade item references (DRY RUN)
-- Rows with trade_item_count > 0 need their trade_item rows reassigned to the
-- keeper before deletion, otherwise those trades will silently lose items.
WITH ranked AS (
  SELECT
    id,
    name,
    "playerDataId",
    "dateModified",
    "leagueTeamId",
    ROW_NUMBER() OVER (
      PARTITION BY "playerDataId"
      ORDER BY ("leagueTeamId" IS NOT NULL) DESC, "dateModified" DESC, id DESC
    ) AS rn
  FROM player
  WHERE "playerDataId" IS NOT NULL
),
candidates AS (
  SELECT ranked.id, ranked.name, ranked."playerDataId", ranked."dateModified",
         ranked."leagueTeamId", ranked.rn
  FROM ranked
  WHERE ranked.rn > 1
    AND ranked."playerDataId" IN (
      SELECT "playerDataId"
      FROM player
      WHERE "playerDataId" IS NOT NULL
      GROUP BY "playerDataId"
      HAVING COUNT(*) > 1
    )
)
SELECT
  c.id,
  c.name,
  c."playerDataId",
  c."dateModified",
  c."leagueTeamId",
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
GROUP BY c.id, c.name, c."playerDataId", c."dateModified", c."leagueTeamId", c.rn
ORDER BY trade_item_count DESC, c."playerDataId", c.rn;

-- Step 3: Preview — full detail of which rows WOULD be deleted (DRY RUN)
WITH ranked AS (
  SELECT
    id,
    name,
    "playerDataId",
    "dateModified",
    "leagueTeamId",
    ROW_NUMBER() OVER (
      PARTITION BY "playerDataId"
      ORDER BY ("leagueTeamId" IS NOT NULL) DESC, "dateModified" DESC, id DESC
    ) AS rn
  FROM player
  WHERE "playerDataId" IS NOT NULL
)
SELECT id, name, "playerDataId", "dateModified", "leagueTeamId", rn,
       CASE WHEN rn = 1 THEN 'KEEP' ELSE 'WOULD DELETE' END AS action
FROM ranked
WHERE "playerDataId" IN (
  SELECT "playerDataId"
  FROM player
  WHERE "playerDataId" IS NOT NULL
  GROUP BY "playerDataId"
  HAVING COUNT(*) > 1
)
ORDER BY "playerDataId", rn;

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
--   SELECT id, "playerDataId",
--     ROW_NUMBER() OVER (
--       PARTITION BY "playerDataId"
--       ORDER BY ("leagueTeamId" IS NOT NULL) DESC, "dateModified" DESC, id DESC
--     ) AS rn
--   FROM player
--   WHERE "playerDataId" IS NOT NULL
-- ),
-- dupes AS (
--   SELECT "playerDataId" AS pdid FROM player
--   WHERE "playerDataId" IS NOT NULL
--   GROUP BY "playerDataId" HAVING COUNT(*) > 1
-- ),
-- keepers AS (
--   SELECT id AS keeper_id, "playerDataId"
--   FROM ranked WHERE rn = 1 AND "playerDataId" IN (SELECT pdid FROM dupes)
-- ),
-- duplicates AS (
--   SELECT r.id AS dup_id, k.keeper_id
--   FROM ranked r
--   JOIN keepers k ON r."playerDataId" = k."playerDataId"
--   WHERE r.rn > 1
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
--   SELECT id, "playerDataId",
--     ROW_NUMBER() OVER (
--       PARTITION BY "playerDataId"
--       ORDER BY ("leagueTeamId" IS NOT NULL) DESC, "dateModified" DESC, id DESC
--     ) AS rn
--   FROM player
--   WHERE "playerDataId" IS NOT NULL
-- ),
-- dupes AS (
--   SELECT "playerDataId" AS pdid FROM player
--   WHERE "playerDataId" IS NOT NULL
--   GROUP BY "playerDataId" HAVING COUNT(*) > 1
-- ),
-- keepers AS (
--   SELECT id AS keeper_id, "playerDataId"
--   FROM ranked WHERE rn = 1 AND "playerDataId" IN (SELECT pdid FROM dupes)
-- ),
-- duplicates AS (
--   SELECT r.id AS dup_id, k.keeper_id
--   FROM ranked r
--   JOIN keepers k ON r."playerDataId" = k."playerDataId"
--   WHERE r.rn > 1
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
--   SELECT
--     id,
--     "playerDataId",
--     ROW_NUMBER() OVER (
--       PARTITION BY "playerDataId"
--       ORDER BY ("leagueTeamId" IS NOT NULL) DESC, "dateModified" DESC, id DESC
--     ) AS rn
--   FROM player
--   WHERE "playerDataId" IS NOT NULL
-- ),
-- to_delete AS (
--   SELECT ranked.id
--   FROM ranked
--   WHERE ranked.rn > 1
--     AND ranked."playerDataId" IN (
--       SELECT "playerDataId"
--       FROM player
--       WHERE "playerDataId" IS NOT NULL
--       GROUP BY "playerDataId"
--       HAVING COUNT(*) > 1
--     )
-- )
-- DELETE FROM player
-- WHERE id IN (SELECT id FROM to_delete);
--
-- -- Verify: should return 0 rows
-- SELECT "playerDataId", COUNT(*)
-- FROM player
-- WHERE "playerDataId" IS NOT NULL
-- GROUP BY "playerDataId"
-- HAVING COUNT(*) > 1;
--
-- -- Verify: no orphaned trade_item references after delete
-- SELECT COUNT(*) AS final_orphan_check
-- FROM trade_item ti
-- LEFT JOIN player p ON p.id = ti."tradeItemId"
-- WHERE ti."tradeItemType" = '1' AND p.id IS NULL;
--
-- COMMIT;
