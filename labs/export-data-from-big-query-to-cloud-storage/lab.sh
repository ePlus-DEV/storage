#!/bin/bash
# © Copyright ePlus.DEV
# BigQuery Bracketology - Full Auto (no "Press Enter" prompts)
# ------------------------------------------------------------

set -euo pipefail

# Avoid pager blocking (e.g., less/more)
export PAGER=cat
export LESS="-FRSX"

# ---------------- Colors ----------------
BLACK="$(tput setaf 0 || true)"
RED="$(tput setaf 1 || true)"
GREEN="$(tput setaf 2 || true)"
YELLOW="$(tput setaf 3 || true)"
BLUE="$(tput setaf 4 || true)"
MAGENTA="$(tput setaf 5 || true)"
CYAN="$(tput setaf 6 || true)"
WHITE="$(tput setaf 7 || true)"

BG_BLACK="$(tput setab 0 || true)"
BG_RED="$(tput setab 1 || true)"
BG_GREEN="$(tput setab 2 || true)"
BG_YELLOW="$(tput setab 3 || true)"
BG_BLUE="$(tput setab 4 || true)"
BG_MAGENTA="$(tput setab 5 || true)"
BG_CYAN="$(tput setab 6 || true)"
BG_WHITE="$(tput setab 7 || true)"

BOLD="$(tput bold || true)"
RESET="$(tput sgr0 || true)"

# ---------------- Helpers ----------------
banner() {
  echo "${BG_MAGENTA}${BOLD}© Copyright ePlus.DEV${RESET}"
  echo "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

info()  { echo "${BLUE}${BOLD}➜${RESET} $*"; }
ok()    { echo "${GREEN}${BOLD}✔${RESET} $*"; }
warn()  { echo "${YELLOW}${BOLD}⚠${RESET} $*"; }
fail()  { echo "${RED}${BOLD}✖${RESET} $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { fail "Missing command: $1"; exit 1; }
}

# ---------------- Start ----------------
banner
echo "${YELLOW}${BOLD}Starting${RESET} ${GREEN}${BOLD}Execution - ePlus.DEV${RESET}"

require_cmd bq

# Resolve PROJECT_ID safely (Cloud Shell uses DEVSHELL_PROJECT_ID; other shells might not)
PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"
if [[ -z "${PROJECT_ID}" ]]; then
  warn "DEVSHELL_PROJECT_ID is empty."
  read -rp "Enter your GCP Project ID: " PROJECT_ID
fi

info "Using PROJECT_ID: ${BOLD}${PROJECT_ID}${RESET}"

# Ensure bq uses the right project for all commands
BQ=(bq --quiet --project_id="${PROJECT_ID}")

# Create dataset (idempotent-ish: if exists, ignore error)
info "Creating dataset: bracketology"
if "${BQ[@]}" mk --dataset "${PROJECT_ID}:bracketology" >/dev/null 2>&1; then
  ok "Dataset created."
else
  warn "Dataset may already exist (continuing)."
fi

# ---------------- Queries ----------------

info "Query 1: games per tournament by season"
"${BQ[@]}" query --use_legacy_sql=false "
SELECT
  season,
  COUNT(*) as games_per_tournament
FROM \`bigquery-public-data.ncaa_basketball.mbb_historical_tournament_games\`
GROUP BY season
ORDER BY season
"

info "Query 2: build labeled outcomes (win/loss) rows"
"${BQ[@]}" query --use_legacy_sql=false "
-- create a row for the winning team
SELECT
  season,
  round,
  days_from_epoch,
  game_date,
  day,
  'win' AS label,
  win_seed AS seed,
  win_market AS market,
  win_name AS name,
  win_alias AS alias,
  win_school_ncaa AS school_ncaa,
  lose_seed AS opponent_seed,
  lose_market AS opponent_market,
  lose_name AS opponent_name,
  lose_alias AS opponent_alias,
  lose_school_ncaa AS opponent_school_ncaa
FROM \`bigquery-public-data.ncaa_basketball.mbb_historical_tournament_games\`
UNION ALL
-- create a separate row for the losing team
SELECT
  season,
  round,
  days_from_epoch,
  game_date,
  day,
  'loss' AS label,
  lose_seed AS seed,
  lose_market AS market,
  lose_name AS name,
  lose_alias AS alias,
  lose_school_ncaa AS school_ncaa,
  win_seed AS opponent_seed,
  win_market AS opponent_market,
  win_name AS opponent_name,
  win_alias AS opponent_alias,
  win_school_ncaa AS opponent_school_ncaa
FROM \`bigquery-public-data.ncaa_basketball.mbb_historical_tournament_games\`;
"

info "Query 3: train baseline model bracketology.ncaa_model"
"${BQ[@]}" query --use_legacy_sql=false "
CREATE OR REPLACE MODEL \`bracketology.ncaa_model\`
OPTIONS ( model_type='logistic_reg') AS
SELECT
  season,
  'win' AS label,
  win_seed AS seed,
  win_school_ncaa AS school_ncaa,
  lose_seed AS opponent_seed,
  lose_school_ncaa AS opponent_school_ncaa
FROM \`bigquery-public-data.ncaa_basketball.mbb_historical_tournament_games\`
WHERE season <= 2017
UNION ALL
SELECT
  season,
  'loss' AS label,
  lose_seed AS seed,
  lose_school_ncaa AS school_ncaa,
  win_seed AS opponent_seed,
  win_school_ncaa AS opponent_school_ncaa
FROM \`bigquery-public-data.ncaa_basketball.mbb_historical_tournament_games\`
WHERE season <= 2017
"

info "Query 4: weights + evaluate + predictions table (baseline)"
"${BQ[@]}" query --use_legacy_sql=false "
SELECT category, weight
FROM UNNEST((
  SELECT category_weights
  FROM ML.WEIGHTS(MODEL \`bracketology.ncaa_model\`)
  WHERE processed_input = 'seed'
))
ORDER BY weight DESC;

SELECT * FROM ML.EVALUATE(MODEL \`bracketology.ncaa_model\`);

CREATE OR REPLACE TABLE \`bracketology.predictions\` AS
SELECT * FROM ML.PREDICT(
  MODEL \`bracketology.ncaa_model\`,
  (SELECT * FROM \`data-to-insights.ncaa.2018_tournament_results\`)
);
"

info "Query 5: create training table with engineered features + updated model"
"${BQ[@]}" query --use_legacy_sql=false "
CREATE OR REPLACE TABLE \`bracketology.training_new_features\` AS
WITH outcomes AS (
  SELECT
    season,
    'win' AS label,
    win_seed AS seed,
    win_school_ncaa AS school_ncaa,
    lose_seed AS opponent_seed,
    lose_school_ncaa AS opponent_school_ncaa
  FROM \`bigquery-public-data.ncaa_basketball.mbb_historical_tournament_games\` t
  WHERE season >= 2014
  UNION ALL
  SELECT
    season,
    'loss' AS label,
    lose_seed AS seed,
    lose_school_ncaa AS school_ncaa,
    win_seed AS opponent_seed,
    win_school_ncaa AS opponent_school_ncaa
  FROM \`bigquery-public-data.ncaa_basketball.mbb_historical_tournament_games\` t
  WHERE season >= 2014
  UNION ALL
  SELECT
    season,
    label,
    seed,
    school_ncaa,
    opponent_seed,
    opponent_school_ncaa
  FROM \`data-to-insights.ncaa.2018_tournament_results\`
)
SELECT
  o.season,
  label,
  seed,
  school_ncaa,
  team.pace_rank,
  team.poss_40min,
  team.pace_rating,
  team.efficiency_rank,
  team.pts_100poss,
  team.efficiency_rating,
  opponent_seed,
  opponent_school_ncaa,
  opp.pace_rank AS opp_pace_rank,
  opp.poss_40min AS opp_poss_40min,
  opp.pace_rating AS opp_pace_rating,
  opp.efficiency_rank AS opp_efficiency_rank,
  opp.pts_100poss AS opp_pts_100poss,
  opp.efficiency_rating AS opp_efficiency_rating,
  opp.pace_rank - team.pace_rank AS pace_rank_diff,
  opp.poss_40min - team.poss_40min AS pace_stat_diff,
  opp.pace_rating - team.pace_rating AS pace_rating_diff,
  opp.efficiency_rank - team.efficiency_rank AS eff_rank_diff,
  opp.pts_100poss - team.pts_100poss AS eff_stat_diff,
  opp.efficiency_rating - team.efficiency_rating AS eff_rating_diff
FROM outcomes AS o
LEFT JOIN \`data-to-insights.ncaa.feature_engineering\` AS team
  ON o.school_ncaa = team.team AND o.season = team.season
LEFT JOIN \`data-to-insights.ncaa.feature_engineering\` AS opp
  ON o.opponent_school_ncaa = opp.team AND o.season = opp.season;

CREATE OR REPLACE MODEL \`bracketology.ncaa_model_updated\`
OPTIONS ( model_type='logistic_reg') AS
SELECT
  season,
  label,
  poss_40min,
  pace_rank,
  pace_rating,
  opp_poss_40min,
  opp_pace_rank,
  opp_pace_rating,
  pace_rank_diff,
  pace_stat_diff,
  pace_rating_diff,
  pts_100poss,
  efficiency_rank,
  efficiency_rating,
  opp_pts_100poss,
  opp_efficiency_rank,
  opp_efficiency_rating,
  eff_rank_diff,
  eff_stat_diff,
  eff_rating_diff
FROM \`bracketology.training_new_features\`
WHERE season BETWEEN 2014 AND 2017;
"

info "Query 6: evaluate updated model + 2018 predictions + narratives"
"${BQ[@]}" query --use_legacy_sql=false "
SELECT * FROM ML.EVALUATE(MODEL \`bracketology.ncaa_model_updated\`);

CREATE OR REPLACE TABLE \`bracketology.ncaa_2018_predictions\` AS
SELECT *
FROM ML.PREDICT(
  MODEL \`bracketology.ncaa_model_updated\`,
  (SELECT * FROM \`bracketology.training_new_features\` WHERE season = 2018)
);

SELECT
  CONCAT(
    school_ncaa, ' was predicted to ',
    IF(predicted_label='loss','lose','win'), ' ',
    CAST(ROUND(p.prob,2)*100 AS STRING),
    '% but ',
    IF(n.label='loss','lost','won')
  ) AS narrative,
  predicted_label,
  n.label,
  ROUND(p.prob,2) AS probability,
  season,
  seed,
  school_ncaa,
  pace_rank,
  efficiency_rank,
  opponent_seed,
  opponent_school_ncaa,
  opp_pace_rank,
  opp_efficiency_rank
FROM \`bracketology.ncaa_2018_predictions\` AS n,
UNNEST(predicted_label_probs) AS p
WHERE predicted_label <> n.label
  AND p.prob > .75
ORDER BY prob DESC;
"

info "Query 7: upsets + build 2019 tournament possible matchups + 2019 predictions"
"${BQ[@]}" query --use_legacy_sql=false "
SELECT
  CONCAT(
    opponent_school_ncaa, ' (', opponent_seed, ') was ',
    CAST(ROUND(ROUND(p.prob,2)*100,2) AS STRING),
    '% predicted to upset ',
    school_ncaa, ' (', seed, ') and did!'
  ) AS narrative,
  predicted_label,
  n.label,
  ROUND(p.prob,2) AS probability,
  season,
  seed,
  school_ncaa,
  pace_rank,
  efficiency_rank,
  opponent_seed,
  opponent_school_ncaa,
  opp_pace_rank,
  opp_efficiency_rank,
  (CAST(opponent_seed AS INT64) - CAST(seed AS INT64)) AS seed_diff
FROM \`bracketology.ncaa_2018_predictions\` AS n,
UNNEST(predicted_label_probs) AS p
WHERE predicted_label = 'loss'
  AND predicted_label = n.label
  AND p.prob >= .55
  AND (CAST(opponent_seed AS INT64) - CAST(seed AS INT64)) > 2
ORDER BY (CAST(opponent_seed AS INT64) - CAST(seed AS INT64)) DESC;

CREATE OR REPLACE TABLE \`bracketology.ncaa_2019_tournament\` AS
WITH team_seeds_all_possible_games AS (
  SELECT
    NULL AS label,
    team.school_ncaa AS school_ncaa,
    team.seed AS seed,
    opp.school_ncaa AS opponent_school_ncaa,
    opp.seed AS opponent_seed
  FROM \`data-to-insights.ncaa.2019_tournament_seeds\` AS team
  CROSS JOIN \`data-to-insights.ncaa.2019_tournament_seeds\` AS opp
  WHERE team.school_ncaa <> opp.school_ncaa
),
add_in_2018_season_stats AS (
  SELECT
    team_seeds_all_possible_games.*,
    (SELECT AS STRUCT * FROM \`data-to-insights.ncaa.feature_engineering\`
      WHERE school_ncaa = team AND season = 2018) AS team,
    (SELECT AS STRUCT * FROM \`data-to-insights.ncaa.feature_engineering\`
      WHERE opponent_school_ncaa = team AND season = 2018) AS opp
  FROM team_seeds_all_possible_games
)
SELECT
  label,
  2019 AS season,
  seed,
  school_ncaa,
  team.pace_rank,
  team.poss_40min,
  team.pace_rating,
  team.efficiency_rank,
  team.pts_100poss,
  team.efficiency_rating,
  opponent_seed,
  opponent_school_ncaa,
  opp.pace_rank AS opp_pace_rank,
  opp.poss_40min AS opp_poss_40min,
  opp.pace_rating AS opp_pace_rating,
  opp.efficiency_rank AS opp_efficiency_rank,
  opp.pts_100poss AS opp_pts_100poss,
  opp.efficiency_rating AS opp_efficiency_rating,
  opp.pace_rank - team.pace_rank AS pace_rank_diff,
  opp.poss_40min - team.poss_40min AS pace_stat_diff,
  opp.pace_rating - team.pace_rating AS pace_rating_diff,
  opp.efficiency_rank - team.efficiency_rank AS eff_rank_diff,
  opp.pts_100poss - team.pts_100poss AS eff_stat_diff,
  opp.efficiency_rating - team.efficiency_rating AS eff_rating_diff
FROM add_in_2018_season_stats;

CREATE OR REPLACE TABLE \`bracketology.ncaa_2019_tournament_predictions\` AS
SELECT *
FROM ML.PREDICT(
  MODEL \`bracketology.ncaa_model_updated\`,
  (SELECT * FROM \`bracketology.ncaa_2019_tournament\`)
);
"

# Optional: baseline predictions table again (kept from your original script)
info "Query 8 (optional): rebuild bracketology.predictions (baseline)"
"${BQ[@]}" query --use_legacy_sql=false "
CREATE OR REPLACE TABLE \`bracketology.predictions\` AS
SELECT * FROM ML.PREDICT(
  MODEL \`bracketology.ncaa_model\`,
  (SELECT * FROM \`data-to-insights.ncaa.2018_tournament_results\`)
);
"

# Optional: rebuild 2018 predictions with full columns (kept from your original script)
info "Query 9 (optional): rebuild bracketology.ncaa_2018_predictions with full columns"
"${BQ[@]}" query --use_legacy_sql=false "
CREATE OR REPLACE TABLE \`bracketology.ncaa_2018_predictions\` AS
SELECT *
FROM ML.PREDICT(
  MODEL \`bracketology.ncaa_model_updated\`,
  (
    SELECT *
    FROM \`bracketology.training_new_features\`
    WHERE season = 2018
  )
);
"

ok "All BigQuery steps completed."

echo "${RED}${BOLD}Congratulations${RESET} ${WHITE}${BOLD}for${RESET} ${GREEN}${BOLD}Completing the Lab !!! - ePlus.DEV${RESET}"
