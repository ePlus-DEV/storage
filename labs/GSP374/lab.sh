#!/bin/bash

# ============================================================
# GSP374 - Perform Predictive Data Analysis in BigQuery
# Full Challenge Lab Solution
# © ePlus.DEV
# ============================================================

set -e

# =========================
# COLORS
# =========================
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

BOLD_TEXT=$'\033[1m'
RESET_FORMAT=$'\033[0m'

clear

echo
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}       WELCOME TO ePlus.DEV CLOUD TUTORIAL${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}       GSP374 - Predictive Data Analysis in BigQuery${RESET_FORMAT}"
echo "${YELLOW_TEXT}                     © ePlus.DEV${RESET_FORMAT}"
echo

# ============================================================
# PROJECT
# ============================================================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"
fi

if [[ -z "$PROJECT_ID" ]]; then
    echo "${RED_TEXT}Unable to detect Project ID.${RESET_FORMAT}"
    exit 1
fi

echo "${GREEN_TEXT}Project ID:${RESET_FORMAT} $PROJECT_ID"
echo

# ============================================================
# LAB-SPECIFIC VALUES
#
# Current known public variant defaults:
# events545
# tags3name
# Goal midpoint: 90,55
# Field: 116x66
# GetShotDistanceToGoal545
# GetShotAngleToGoal545
# xg_logistic_reg_model_545
#
# If your lab shows different values, type them below.
# Press ENTER to use the displayed default.
# ============================================================

read -rp "Event table name [events545]: " INPUT
EVENT_TABLE="${INPUT:-events545}"

read -rp "Tags table name [tags3name]: " INPUT
TAG_TABLE="${INPUT:-tags3name}"

read -rp "Goal midpoint X [90]: " INPUT
GOAL_X="${INPUT:-90}"

read -rp "Goal midpoint Y [55]: " INPUT
GOAL_Y="${INPUT:-55}"

read -rp "Field X length [116]: " INPUT
FIELD_X="${INPUT:-116}"

read -rp "Field Y length [66]: " INPUT
FIELD_Y="${INPUT:-66}"

read -rp "Distance function [GetShotDistanceToGoal545]: " INPUT
DIST_FUNC="${INPUT:-GetShotDistanceToGoal545}"

read -rp "Angle function [GetShotAngleToGoal545]: " INPUT
ANGLE_FUNC="${INPUT:-GetShotAngleToGoal545}"

read -rp "Model name [xg_logistic_reg_model_545]: " INPUT
MODEL_NAME="${INPUT:-xg_logistic_reg_model_545}"

# Strip dataset prefix if user pasted soccer.xxxxxx
EVENT_TABLE="${EVENT_TABLE##*.}"
TAG_TABLE="${TAG_TABLE##*.}"
DIST_FUNC="${DIST_FUNC##*.}"
ANGLE_FUNC="${ANGLE_FUNC##*.}"
MODEL_NAME="${MODEL_NAME##*.}"

echo
echo "${CYAN_TEXT}${BOLD_TEXT}================ LAB CONFIGURATION ================${RESET_FORMAT}"
echo "Event table       : $EVENT_TABLE"
echo "Tags table        : $TAG_TABLE"
echo "Goal midpoint     : ($GOAL_X, $GOAL_Y)"
echo "Field dimensions  : ${FIELD_X} x ${FIELD_Y}"
echo "Distance function : soccer.$DIST_FUNC"
echo "Angle function    : soccer.$ANGLE_FUNC"
echo "Model             : soccer.$MODEL_NAME"
echo "${CYAN_TEXT}${BOLD_TEXT}===================================================${RESET_FORMAT}"
echo

# ============================================================
# CREATE / CHECK DATASET
# ============================================================

echo "${YELLOW_TEXT}${BOLD_TEXT}[SETUP] Checking soccer dataset...${RESET_FORMAT}"

if ! bq show "${PROJECT_ID}:soccer" >/dev/null 2>&1; then
    echo "Creating soccer dataset..."
    bq mk --dataset "${PROJECT_ID}:soccer"
else
    echo "${GREEN_TEXT}✓ soccer dataset already exists.${RESET_FORMAT}"
fi

# ============================================================
# BASE TABLES
# ============================================================

load_base_table() {
    local TABLE="$1"

    if bq show "${PROJECT_ID}:soccer.${TABLE}" >/dev/null 2>&1; then
        echo "${GREEN_TEXT}✓ soccer.${TABLE} already exists.${RESET_FORMAT}"
    else
        echo "${YELLOW_TEXT}Loading soccer.${TABLE}...${RESET_FORMAT}"

        bq load \
          --autodetect \
          --source_format=NEWLINE_DELIMITED_JSON \
          "${PROJECT_ID}:soccer.${TABLE}" \
          "gs://spls/bq-soccer-analytics/${TABLE}.json"
    fi
}

load_base_table competitions
load_base_table matches
load_base_table teams
load_base_table players

# ============================================================
# TASK 1
# DATA INGESTION
# ============================================================

echo
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT} TASK 1 - DATA INGESTION${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"

echo "${YELLOW_TEXT}Loading events table: soccer.${EVENT_TABLE}${RESET_FORMAT}"

bq load \
  --replace \
  --autodetect \
  --source_format=NEWLINE_DELIMITED_JSON \
  "${PROJECT_ID}:soccer.${EVENT_TABLE}" \
  "gs://spls/bq-soccer-analytics/events.json"

echo
echo "${YELLOW_TEXT}Loading tags table: soccer.${TAG_TABLE}${RESET_FORMAT}"

bq load \
  --replace \
  --autodetect \
  --source_format=CSV \
  "${PROJECT_ID}:soccer.${TAG_TABLE}" \
  "gs://spls/bq-soccer-analytics/tags2name.csv"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 1 COMPLETE${RESET_FORMAT}"

# ============================================================
# TASK 2
# PENALTY KICK SUCCESS RATE
# ============================================================

echo
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT} TASK 2 - PENALTY KICK SUCCESS RATE${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"

bq query \
--project_id="$PROJECT_ID" \
--use_legacy_sql=false \
"
SELECT
  playerId,
  (Players.firstName || ' ' || Players.lastName) AS playerName,
  COUNT(id) AS numPKAtt,
  SUM(IF(101 IN UNNEST(tags.id), 1, 0)) AS numPKGoals,

  SAFE_DIVIDE(
    SUM(IF(101 IN UNNEST(tags.id), 1, 0)),
    COUNT(id)
  ) AS PKSuccessRate

FROM
  \`${PROJECT_ID}.soccer.${EVENT_TABLE}\` Events

LEFT JOIN
  \`${PROJECT_ID}.soccer.players\` Players
ON
  Events.playerId = Players.wyId

WHERE
  eventName = 'Free Kick'
  AND subEventName = 'Penalty'

GROUP BY
  playerId,
  playerName

HAVING
  numPKAtt >= 5

ORDER BY
  PKSuccessRate DESC,
  numPKAtt DESC;
"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 2 COMPLETE${RESET_FORMAT}"

# ============================================================
# TASK 3
# SHOT DISTANCE ANALYSIS
# ============================================================

echo
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT} TASK 3 - SHOT DISTANCE ANALYSIS${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"

bq query \
--project_id="$PROJECT_ID" \
--use_legacy_sql=false \
"
WITH Shots AS
(
  SELECT
    *,

    /* Tag 101 = goal */
    (101 IN UNNEST(tags.id)) AS isGoal,

    /*
     * Convert 0-100 coordinates into estimated meters
     * using the values supplied by this challenge variant.
     */
    SQRT(
      POW(
        (${GOAL_X} - positions[ORDINAL(1)].x)
        * ${FIELD_X}/100,
        2
      )
      +
      POW(
        (${GOAL_Y} - positions[ORDINAL(1)].y)
        * ${FIELD_Y}/100,
        2
      )
    ) AS shotDistance

  FROM
    \`${PROJECT_ID}.soccer.${EVENT_TABLE}\`

  WHERE
    eventName = 'Shot'
    OR (
      eventName = 'Free Kick'
      AND subEventName IN ('Free kick shot', 'Penalty')
    )
)

SELECT
  ROUND(shotDistance, 0) AS ShotDistRound0,
  COUNT(*) AS numShots,
  SUM(IF(isGoal, 1, 0)) AS numGoals,
  AVG(IF(isGoal, 1, 0)) AS goalPct

FROM Shots

WHERE
  shotDistance <= 50

GROUP BY
  ShotDistRound0

ORDER BY
  ShotDistRound0;
"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 3 COMPLETE${RESET_FORMAT}"

# ============================================================
# TASK 4A
# SHOT DISTANCE FUNCTION
# ============================================================

echo
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT} TASK 4A - CREATE SHOT DISTANCE FUNCTION${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"

bq query \
--project_id="$PROJECT_ID" \
--use_legacy_sql=false \
"
CREATE OR REPLACE FUNCTION
\`${PROJECT_ID}.soccer.${DIST_FUNC}\`
(
  x INT64,
  y INT64
)

RETURNS FLOAT64

AS
(
  SQRT(
    POW(
      (${GOAL_X} - x) * ${FIELD_X}/100,
      2
    )
    +
    POW(
      (${GOAL_Y} - y) * ${FIELD_Y}/100,
      2
    )
  )
);
"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}✓ Distance function created: soccer.${DIST_FUNC}${RESET_FORMAT}"

# ============================================================
# TASK 4B
# SHOT ANGLE FUNCTION
# ============================================================

echo
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT} TASK 4B - CREATE SHOT ANGLE FUNCTION${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"

bq query --use_legacy_sql=false "
CREATE OR REPLACE FUNCTION \`soccer.${FUNC_2}\`(x INT64, y INT64)
RETURNS FLOAT64
AS (
 SAFE.ACOS(
   SAFE_DIVIDE(
     (
       (
         POW(${FIELD_X} - (x * ${FIELD_X}/100), 2)
         +
         POW(${FIELD_HALF_Y} + (7.32/2) - (y * ${FIELD_Y}/100), 2)
       )
       +
       (
         POW(${FIELD_X} - (x * ${FIELD_X}/100), 2)
         +
         POW(${FIELD_HALF_Y} - (7.32/2) - (y * ${FIELD_Y}/100), 2)
       )
       -
       POW(7.32, 2)
     ),
     (
       2
       *
       SQRT(
         POW(${FIELD_X} - (x * ${FIELD_X}/100), 2)
         +
         POW(${FIELD_HALF_Y} + 7.32/2 - (y * ${FIELD_Y}/100), 2)
       )
       *
       SQRT(
         POW(${FIELD_X} - (x * ${FIELD_X}/100), 2)
         +
         POW(${FIELD_HALF_Y} - 7.32/2 - (y * ${FIELD_Y}/100), 2)
       )
     )
   )
 ) * 180 / ACOS(-1)
);
"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}✓ Angle function created: soccer.${ANGLE_FUNC}${RESET_FORMAT}"

# ============================================================
# TASK 4C
# LOGISTIC REGRESSION MODEL
# ============================================================

echo
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT} TASK 4C - CREATE EXPECTED GOALS MODEL${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${YELLOW_TEXT}Training BigQuery ML model...${RESET_FORMAT}"
echo

bq query \
--project_id="$PROJECT_ID" \
--use_legacy_sql=false \
"
CREATE OR REPLACE MODEL
\`${PROJECT_ID}.soccer.${MODEL_NAME}\`

OPTIONS
(
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['isGoal']
)

AS

SELECT

  Events.subEventName AS shotType,

  /* Tag 101 = goal */
  (101 IN UNNEST(Events.tags.id)) AS isGoal,

  \`${PROJECT_ID}.soccer.${DIST_FUNC}\`
  (
    Events.positions[ORDINAL(1)].x,
    Events.positions[ORDINAL(1)].y
  ) AS shotDistance,

  \`${PROJECT_ID}.soccer.${ANGLE_FUNC}\`
  (
    Events.positions[ORDINAL(1)].x,
    Events.positions[ORDINAL(1)].y
  ) AS shotAngle

FROM
  \`${PROJECT_ID}.soccer.${EVENT_TABLE}\` Events

LEFT JOIN
  \`${PROJECT_ID}.soccer.matches\` Matches
ON
  Events.matchId = Matches.wyId

LEFT JOIN
  \`${PROJECT_ID}.soccer.competitions\` Competitions
ON
  Matches.competitionId = Competitions.wyId

WHERE

  /* Exclude World Cup from model training */
  Competitions.name != 'World Cup'

  AND

  (
    eventName = 'Shot'

    OR

    (
      eventName = 'Free Kick'
      AND subEventName IN (
        'Free kick shot',
        'Penalty'
      )
    )
  );
"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}✓ BigQuery ML model created: soccer.${MODEL_NAME}${RESET_FORMAT}"

# ============================================================
# MODEL EVALUATION - OPTIONAL BUT USEFUL
# ============================================================

echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Model evaluation:${RESET_FORMAT}"

bq query \
--project_id="$PROJECT_ID" \
--use_legacy_sql=false \
"
SELECT *
FROM ML.EVALUATE(
  MODEL \`${PROJECT_ID}.soccer.${MODEL_NAME}\`
);
"

# ============================================================
# TASK 5
# WORLD CUP PREDICTIONS
# ============================================================

echo
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT} TASK 5 - MAKE WORLD CUP PREDICTIONS${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"

bq query \
--project_id="$PROJECT_ID" \
--use_legacy_sql=false \
"
SELECT
  *

FROM
  ML.PREDICT
  (
    MODEL \`${PROJECT_ID}.soccer.${MODEL_NAME}\`,

    (
      SELECT

        Events.subEventName AS shotType,

        /* Tag 101 = goal */
        (101 IN UNNEST(Events.tags.id)) AS isGoal,

        \`${PROJECT_ID}.soccer.${DIST_FUNC}\`
        (
          Events.positions[ORDINAL(1)].x,
          Events.positions[ORDINAL(1)].y
        ) AS shotDistance,

        \`${PROJECT_ID}.soccer.${ANGLE_FUNC}\`
        (
          Events.positions[ORDINAL(1)].x,
          Events.positions[ORDINAL(1)].y
        ) AS shotAngle

      FROM
        \`${PROJECT_ID}.soccer.${EVENT_TABLE}\` Events

      LEFT JOIN
        \`${PROJECT_ID}.soccer.matches\` Matches
      ON
        Events.matchId = Matches.wyId

      LEFT JOIN
        \`${PROJECT_ID}.soccer.competitions\` Competitions
      ON
        Matches.competitionId = Competitions.wyId

      WHERE

        /* Only World Cup */
        Competitions.name = 'World Cup'

        AND

        /* All shot types, INCLUDING penalties */
        (
          eventName = 'Shot'

          OR

          (
            eventName = 'Free Kick'
            AND subEventName IN (
              'Free kick shot',
              'Penalty'
            )
          )
        )
    )
  );
"

# ============================================================
# FINAL VERIFICATION
# ============================================================

echo
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}                  ALL TASKS EXECUTED${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo

echo "${YELLOW_TEXT}Created resources:${RESET_FORMAT}"
echo

bq ls "${PROJECT_ID}:soccer"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}Expected checkpoints:${RESET_FORMAT}"
echo "${GREEN_TEXT}✓ Task 1 - Check tables are created${RESET_FORMAT}"
echo "${GREEN_TEXT}✓ Task 2 - Check penalty kick success rate${RESET_FORMAT}"
echo "${GREEN_TEXT}✓ Task 3 - Analyze shot distance${RESET_FORMAT}"
echo "${GREEN_TEXT}✓ Task 4A - Calculate shot distance${RESET_FORMAT}"
echo "${GREEN_TEXT}✓ Task 4B - Calculate shot angle${RESET_FORMAT}"
echo "${GREEN_TEXT}✓ Task 4C - Create BigQuery logistic regression model${RESET_FORMAT}"
echo "${GREEN_TEXT}✓ Task 5 - Make predictions from the model${RESET_FORMAT}"

echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}              © ePlus.DEV - LAB COMPLETED${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo