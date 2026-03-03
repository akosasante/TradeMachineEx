-- Cleanup Duplicate playerDataId Rows
-- ====================================
-- Problem: Multiple player rows can share the same playerDataId (e.g. ESPN renamed
-- a player, creating a second DB row with the new name). The unique constraint on
-- (name, playerDataId) then prevents the sync from updating the stale row.
--
-- Strategy: For each duplicated playerDataId, keep the most recently modified row
-- and delete the rest. This is safe because:
--   1. The kept row has the freshest data (latest dateModified)
--   2. Deleted rows are stale duplicates that would be re-synced to the kept row anyway
--
-- Usage: Run against both prod and staging schemas.
--   \set target_schema 'public'   -- or 'staging'
--   \i priv/scripts/cleanup_duplicate_player_data_ids.sql
--
-- Or via psql directly:
--   psql -h <host> -p 5438 -U <user> -d <db> -f priv/scripts/cleanup_duplicate_player_data_ids.sql

-- Step 1: Preview — show all duplicate groups (DRY RUN)
SELECT
  "playerDataId",
  COUNT(*) AS row_count,
  array_agg(id ORDER BY "dateModified" DESC) AS ids,
  array_agg(name ORDER BY "dateModified" DESC) AS names,
  array_agg("dateModified" ORDER BY "dateModified" DESC) AS dates_modified,
  array_agg("leagueTeamId" ORDER BY "dateModified" DESC) AS owner_ids
FROM player
WHERE "playerDataId" IS NOT NULL
GROUP BY "playerDataId"
HAVING COUNT(*) > 1
ORDER BY row_count DESC;

-- Step 2: Preview — show which rows WOULD be deleted (DRY RUN)
-- The subquery keeps the row with the latest dateModified per playerDataId.
-- Ties are broken by id to be deterministic.
WITH ranked AS (
  SELECT
    id,
    name,
    "playerDataId",
    "dateModified",
    "leagueTeamId",
    ROW_NUMBER() OVER (
      PARTITION BY "playerDataId"
      ORDER BY "dateModified" DESC, id DESC
    ) AS rn
  FROM player
  WHERE "playerDataId" IS NOT NULL
)
SELECT id, name, "playerDataId", "dateModified", "leagueTeamId"
FROM ranked
WHERE rn > 1
  AND "playerDataId" IN (
    SELECT "playerDataId"
    FROM player
    WHERE "playerDataId" IS NOT NULL
    GROUP BY "playerDataId"
    HAVING COUNT(*) > 1
  )
ORDER BY "playerDataId", "dateModified" DESC;

-- Step 3: DELETE the duplicates (UNCOMMENT TO RUN)
-- BEGIN;
--
-- WITH ranked AS (
--   SELECT
--     id,
--     "playerDataId",
--     ROW_NUMBER() OVER (
--       PARTITION BY "playerDataId"
--       ORDER BY "dateModified" DESC, id DESC
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
