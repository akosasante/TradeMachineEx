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

-- Step 2: Preview — show which rows WOULD be deleted (DRY RUN)
-- Only minor league rows with rn > 1 are candidates for deletion.
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

-- Step 3: DELETE minor league duplicates (UNCOMMENT TO RUN)
-- BEGIN;
--
-- WITH ranked AS (
--   SELECT
--     id,
--     TRIM(name) AS trimmed_name,
--     league,
--     ROW_NUMBER() OVER (
--       PARTITION BY TRIM(name)
--       ORDER BY
--         (league = '1') DESC,
--         ("playerDataId" IS NOT NULL) DESC,
--         (meta IS NOT NULL) DESC,
--         ("leagueTeamId" IS NOT NULL) DESC,
--         "dateModified" DESC,
--         id DESC
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
-- COMMIT;
