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
echo "${MAGENTA}${BOLD}          BigQuery Soccer Data Analysis Lab                ${RESET}"
echo "${YELLOW}                     © ePlus.DEV${RESET}"
echo

# ============================================================
# DETECT PROJECT
# ============================================================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    echo "${RED}${BOLD}✗ Unable to detect Project ID.${RESET}"
    exit 1
fi

echo "${GREEN}✓ Project ID : ${WHITE}${PROJECT_ID}${RESET}"

# ============================================================
# CHECK DATASET
# ============================================================

echo
echo "${BLUE}${BOLD}Checking soccer dataset...${RESET}"

if ! bq show "${PROJECT_ID}:soccer" >/dev/null 2>&1; then
    echo "${RED}✗ Dataset soccer was not found.${RESET}"
    echo "${YELLOW}Make sure you are using the correct Qwiklabs project.${RESET}"
    exit 1
fi

echo "${GREEN}✓ Dataset soccer found.${RESET}"

# ============================================================
# DETECT BIGQUERY LOCATION
# ============================================================

LOCATION=$(bq show \
    --format=prettyjson \
    "${PROJECT_ID}:soccer" 2>/dev/null |
    python3 -c '
import json,sys
try:
    print(json.load(sys.stdin).get("location",""))
except:
    print("")
' 2>/dev/null)

if [[ -n "$LOCATION" ]]; then
    echo "${GREEN}✓ Location   : ${WHITE}${LOCATION}${RESET}"
else
    echo "${YELLOW}! Could not detect dataset location.${RESET}"
fi

# ============================================================
# RUN QUERY FUNCTION
# ============================================================

run_query() {

    local TASK="$1"
    local SQL="$2"

    echo
    echo "${CYAN}${BOLD}============================================================${RESET}"
    echo "${CYAN}${BOLD}${TASK}${RESET}"
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
        echo "${RED}${BOLD}✗ ${TASK} failed.${RESET}"
        exit 1
    fi

    echo
    echo "${GREEN}${BOLD}✓ ${TASK} completed successfully.${RESET}"
}

# ============================================================
# [1/3] TASK 2 - MATCHES WITH THE MOST GOALS
# ============================================================

TASK2_SQL=$(cat <<'SQL'
SELECT
 date,
 label,
 (team1.score + team2.score) AS totalGoals
FROM
 `soccer.matches` Matches
LEFT JOIN
 `soccer.competitions` Competitions ON
   Matches.competitionId = Competitions.wyId
WHERE
 status = 'Played' AND
 Competitions.name = 'Spanish first division'
ORDER BY
 totalGoals DESC, date DESC
SQL
)

run_query "[1/3] TASK 2 - MATCHES WITH THE MOST GOALS" "$TASK2_SQL"

# ============================================================
# [2/3] TASK 3 - PLAYERS WITH THE MOST PASSES
# ============================================================

TASK3_SQL=$(cat <<'SQL'
SELECT
 playerId,
 (Players.firstName || ' ' || Players.lastName) AS playerName,
 COUNT(id) AS numPasses

FROM
 `soccer.events` Events

LEFT JOIN
 `soccer.players` Players ON
   Events.playerId = Players.wyId

WHERE
 eventName = 'Pass'

GROUP BY
 playerId, playerName

ORDER BY
 numPasses DESC

LIMIT 10
SQL
)

run_query "[2/3] TASK 3 - PLAYERS WITH THE MOST PASSES" "$TASK3_SQL"

# ============================================================
# [3/3] TASK 4 - PENALTY KICK SUCCESS RATE
# ============================================================

TASK4_SQL=$(cat <<'SQL'
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
 `soccer.players` Players ON
   Events.playerId = Players.wyId

WHERE
 eventName = 'Free Kick' AND
 subEventName = 'Penalty'

GROUP BY
 playerId, playerName

HAVING
 numPkAtt >= 5

ORDER BY
 PKSuccessRate DESC, numPKAtt DESC
SQL
)

run_query "[3/3] TASK 4 - PENALTY KICK SUCCESS RATE" "$TASK4_SQL"

# ============================================================
# COMPLETE
# ============================================================

echo
echo
echo "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
echo "${GREEN}${BOLD}              ALL LAB TASKS COMPLETED ✓                    ${RESET}"
echo "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
echo
echo "${WHITE}${BOLD}Completed processes:${RESET}"
echo
echo "${GREEN}✓ [1/3] Task 2 - totalGoals DESC, date DESC${RESET}"
echo "${GREEN}✓ [2/3] Task 3 - numPasses DESC${RESET}"
echo "${GREEN}✓ [3/3] Task 4 - PKSuccessRate DESC${RESET}"
echo
echo "${YELLOW}${BOLD}Now return to Google Skills Boost and click Check my progress.${RESET}"
echo
echo "${MAGENTA}${BOLD}                     © ePlus.DEV${RESET}"
echo