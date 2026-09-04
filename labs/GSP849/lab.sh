#!/bin/bash

# ============================================================
# ePlus.DEV - BigQuery Soccer Data Analysis Lab
# ============================================================

# ---------- COLORS ----------
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'
RESET=$'\033[0m'
BOLD=$'\033[1m'

clear

echo
echo "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
echo "${CYAN}${BOLD}        WELCOME TO ePlus.DEV CLOUD TUTORIAL                ${RESET}"
echo "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
echo
echo "${MAGENTA}${BOLD}        BigQuery Soccer Data Analysis Lab                  ${RESET}"
echo "${YELLOW}                  © ePlus.DEV${RESET}"
echo

# ============================================================
# PROJECT DETECTION
# ============================================================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    echo "${RED}✗ Could not detect current Project ID.${RESET}"
    exit 1
fi

echo "${GREEN}✓ Project ID : ${WHITE}${PROJECT_ID}${RESET}"

# ============================================================
# CHECK SOCCER DATASET
# ============================================================

echo
echo "${BLUE}${BOLD}Checking soccer dataset...${RESET}"

if ! bq show --project_id="$PROJECT_ID" "${PROJECT_ID}:soccer" >/dev/null 2>&1; then
    echo "${RED}✗ Dataset 'soccer' was not found in project:${RESET}"
    echo "${YELLOW}  $PROJECT_ID${RESET}"
    echo
    echo "${YELLOW}Make sure you are using the Qwiklabs student project.${RESET}"
    exit 1
fi

echo "${GREEN}✓ Dataset soccer found.${RESET}"

# Detect BigQuery dataset location
LOCATION=$(bq show \
    --project_id="$PROJECT_ID" \
    --format=prettyjson \
    "${PROJECT_ID}:soccer" 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("location",""))' 2>/dev/null)

if [[ -n "$LOCATION" ]]; then
    echo "${GREEN}✓ BigQuery location : ${WHITE}${LOCATION}${RESET}"
else
    echo "${YELLOW}! Could not detect dataset location. Continuing...${RESET}"
fi

run_query() {

    local TITLE="$1"
    local SQL="$2"

    echo
    echo "${CYAN}${BOLD}============================================================${RESET}"
    echo "${CYAN}${BOLD}${TITLE}${RESET}"
    echo "${CYAN}${BOLD}============================================================${RESET}"
    echo

    if [[ -n "$LOCATION" ]]; then
        bq query \
            --project_id="$PROJECT_ID" \
            --location="$LOCATION" \
            --use_legacy_sql=false \
            "$SQL"
    else
        bq query \
            --project_id="$PROJECT_ID" \
            --use_legacy_sql=false \
            "$SQL"
    fi

    if [[ $? -ne 0 ]]; then
        echo
        echo "${RED}✗ Query failed.${RESET}"
        exit 1
    fi

    echo
    echo "${GREEN}✓ Query completed successfully.${RESET}"
}

# ============================================================
# TASK 2
# Matches with the most goals
# ============================================================

QUERY_TASK2=$(cat <<'SQL'
SELECT
  date,
  label,
  (team1.score + team2.score) AS totalGoals
FROM
  `soccer.matches` Matches
LEFT JOIN
  `soccer.competitions` Competitions
ON
  Matches.competitionId = Competitions.wyId
WHERE
  status = 'Played'
  AND Competitions.name = 'Spanish first division'
ORDER BY
  totalGoals DESC,
  date DESC
SQL
)

run_query "[TASK 2] Matches with the most goals" "$QUERY_TASK2"

# ============================================================
# TASK 3
# Players with the most passes
# ============================================================

QUERY_TASK3=$(cat <<'SQL'
SELECT
  playerId,
  (Players.firstName || ' ' || Players.lastName) AS playerName,
  COUNT(id) AS numPasses
FROM
  `soccer.events` Events
LEFT JOIN
  `soccer.players` Players
ON
  Events.playerId = Players.wyId
WHERE
  eventName = 'Pass'
GROUP BY
  playerId,
  playerName
ORDER BY
  numPasses DESC
LIMIT 10
SQL
)

run_query "[TASK 3] Players with the most passes" "$QUERY_TASK3"

# ============================================================
# TASK 4
# Penalty kick success rate
# ============================================================

QUERY_TASK4=$(cat <<'SQL'
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
  `soccer.events` Events

LEFT JOIN
  `soccer.players` Players
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
  numPKAtt DESC
SQL
)

run_query "[TASK 4] Determine penalty kick success rate" "$QUERY_TASK4"

# ============================================================
# POP QUIZ
# Calculate answers automatically
# ============================================================

echo
echo "${MAGENTA}${BOLD}============================================================${RESET}"
echo "${MAGENTA}${BOLD}                    POP QUIZ ANSWERS                        ${RESET}"
echo "${MAGENTA}${BOLD}============================================================${RESET}"
echo

echo "${YELLOW}${BOLD}Question 1:${RESET}"
echo "How many Spanish first division matches achieved"
echo "the highest number of total goals?"
echo

QUIZ1=$(cat <<'SQL'
WITH matches_data AS (
  SELECT
    date,
    label,
    (team1.score + team2.score) AS totalGoals
  FROM
    `soccer.matches` Matches
  LEFT JOIN
    `soccer.competitions` Competitions
  ON
    Matches.competitionId = Competitions.wyId
  WHERE
    status = 'Played'
    AND Competitions.name = 'Spanish first division'
),
maximum AS (
  SELECT MAX(totalGoals) AS maxGoals
  FROM matches_data
)
SELECT
  COUNT(*) AS numberOfMatches
FROM matches_data
WHERE totalGoals = (SELECT maxGoals FROM maximum)
SQL
)

if [[ -n "$LOCATION" ]]; then
    bq query \
        --project_id="$PROJECT_ID" \
        --location="$LOCATION" \
        --use_legacy_sql=false \
        "$QUIZ1"
else
    bq query \
        --project_id="$PROJECT_ID" \
        --use_legacy_sql=false \
        "$QUIZ1"
fi

echo
echo "${YELLOW}${BOLD}Question 2:${RESET}"
echo "Which player attempted the most passes?"
echo

QUIZ2=$(cat <<'SQL'
SELECT
  (Players.firstName || ' ' || Players.lastName) AS playerName,
  COUNT(id) AS numPasses
FROM
  `soccer.events` Events
LEFT JOIN
  `soccer.players` Players
ON
  Events.playerId = Players.wyId
WHERE
  eventName = 'Pass'
GROUP BY
  playerName
ORDER BY
  numPasses DESC
LIMIT 1
SQL
)

if [[ -n "$LOCATION" ]]; then
    bq query \
        --project_id="$PROJECT_ID" \
        --location="$LOCATION" \
        --use_legacy_sql=false \
        "$QUIZ2"
else
    bq query \
        --project_id="$PROJECT_ID" \
        --use_legacy_sql=false \
        "$QUIZ2"
fi

echo
echo "${YELLOW}${BOLD}Question 3:${RESET}"
echo "How many players attempted at least 5 penalty kicks?"
echo

QUIZ3=$(cat <<'SQL'
WITH penalty_players AS (
  SELECT
    playerId,
    COUNT(id) AS numPKAtt
  FROM
    `soccer.events`
  WHERE
    eventName = 'Free Kick'
    AND subEventName = 'Penalty'
  GROUP BY
    playerId
  HAVING
    COUNT(id) >= 5
)

SELECT
  COUNT(*) AS numberOfPlayers
FROM
  penalty_players
SQL
)

if [[ -n "$LOCATION" ]]; then
    bq query \
        --project_id="$PROJECT_ID" \
        --location="$LOCATION" \
        --use_legacy_sql=false \
        "$QUIZ3"
else
    bq query \
        --project_id="$PROJECT_ID" \
        --use_legacy_sql=false \
        "$QUIZ3"
fi

# ============================================================
# COMPLETE
# ============================================================

echo
echo "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
echo "${GREEN}${BOLD}              ALL LAB QUERIES COMPLETED ✓                  ${RESET}"
echo "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
echo
echo "${CYAN}Now return to Google Skills Boost and click:${RESET}"
echo
echo "${WHITE}${BOLD}  ✓ Check my progress - Task 2${RESET}"
echo "${WHITE}${BOLD}  ✓ Check my progress - Task 3${RESET}"
echo "${WHITE}${BOLD}  ✓ Check my progress - Task 4${RESET}"
echo
echo "${MAGENTA}${BOLD}                    © ePlus.DEV${RESET}"
echo