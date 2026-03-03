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

-- Step 2: Preview — show which rows WOULD be deleted (DRY RUN)
-- Keeps owned rows over unowned, then most recently modified. The first row in
-- each partition (rn=1) is the keeper; all others (rn>1) would be deleted.
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
SELECT id, name, "playerDataId", "dateModified", "leagueTeamId",
       'WOULD DELETE' AS action
FROM ranked
WHERE rn > 1
  AND "playerDataId" IN (
    SELECT "playerDataId"
    FROM player
    WHERE "playerDataId" IS NOT NULL
    GROUP BY "playerDataId"
    HAVING COUNT(*) > 1
  )
ORDER BY "playerDataId", rn;

-- Step 3: DELETE the duplicates (UNCOMMENT TO RUN)
-- BEGIN;
--
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
-- COMMIT;
