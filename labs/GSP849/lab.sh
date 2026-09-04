#!/bin/bash

# ============================================================
# ePlus.DEV - BigQuery Soccer Data Analysis
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
    echo
    echo "${YELLOW}Make sure you are using the Qwiklabs student project.${RESET}"
    exit 1
fi

echo "${GREEN}✓ Dataset soccer found.${RESET}"

# ============================================================
# DETECT DATASET LOCATION
# ============================================================

LOCATION=$(bq show \
    --format=prettyjson \
    "${PROJECT_ID}:soccer" 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("location",""))' \
    2>/dev/null)

if [[ -n "$LOCATION" ]]; then
    echo "${GREEN}✓ Location   : ${WHITE}${LOCATION}${RESET}"
fi

# ============================================================
# FUNCTION - RUN QUERY
# ============================================================

run_bq_query() {

    local SQL="$1"

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

    RESULT=$?

    if [[ $RESULT -ne 0 ]]; then
        echo
        echo "${RED}${BOLD}✗ Query failed.${RESET}"
        exit 1
    fi
}

# ============================================================
# FUNCTION - WAIT FOR CHECK
# ============================================================

wait_for_check() {

    local TASK="$1"

    echo
    echo "${GREEN}${BOLD}✓ ${TASK} query completed.${RESET}"
    echo
    echo "${YELLOW}${BOLD}============================================================${RESET}"
    echo "${YELLOW}${BOLD}IMPORTANT:${RESET}"
    echo
    echo "${WHITE}1. Go back to Google Skills Boost.${RESET}"
    echo "${WHITE}2. Click ${GREEN}${BOLD}Check my progress${RESET}${WHITE} for ${TASK}.${RESET}"
    echo "${WHITE}3. Wait until the task shows completed.${RESET}"
    echo
    echo "${YELLOW}DO NOT continue before checking the task.${RESET}"
    echo "${YELLOW}${BOLD}============================================================${RESET}"
    echo

    while true; do

        read -r -p "After ${TASK} is completed, enter Y to continue: " ANSWER

        case "$ANSWER" in
            [Yy])
                echo
                break
                ;;
            *)
                echo "${YELLOW}Please check the task first, then enter Y.${RESET}"
                ;;
        esac

    done
}

# ============================================================
# TASK 2
# Matches with the most goals
# ============================================================

echo
echo "${CYAN}${BOLD}============================================================${RESET}"
echo "${CYAN}${BOLD} TASK 2 - MATCHES WITH THE MOST GOALS${RESET}"
echo "${CYAN}${BOLD}============================================================${RESET}"
echo

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

echo "${YELLOW}Running the exact Task 2 lab query...${RESET}"
echo

run_bq_query "$TASK2_SQL"

wait_for_check "TASK 2"

# ============================================================
# TASK 3
# Players with the most passes
# ============================================================

echo
echo "${CYAN}${BOLD}============================================================${RESET}"
echo "${CYAN}${BOLD} TASK 3 - PLAYERS WITH THE MOST PASSES${RESET}"
echo "${CYAN}${BOLD}============================================================${RESET}"
echo

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

echo "${YELLOW}Running the exact Task 3 lab query...${RESET}"
echo

run_bq_query "$TASK3_SQL"

wait_for_check "TASK 3"

# ============================================================
# TASK 4
# Penalty kick success rate
# ============================================================

echo
echo "${CYAN}${BOLD}============================================================${RESET}"
echo "${CYAN}${BOLD} TASK 4 - PENALTY KICK SUCCESS RATE${RESET}"
echo "${CYAN}${BOLD}============================================================${RESET}"
echo

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

echo "${YELLOW}Running the exact Task 4 lab query...${RESET}"
echo

run_bq_query "$TASK4_SQL"

# ============================================================
# TASK 4 CHECK
# ============================================================

echo
echo "${GREEN}${BOLD}✓ TASK 4 query completed.${RESET}"
echo
echo "${YELLOW}${BOLD}============================================================${RESET}"
echo "${WHITE}Go back to Google Skills Boost and click:${RESET}"
echo
echo "${GREEN}${BOLD}     Check my progress - TASK 4${RESET}"
echo
echo "${YELLOW}${BOLD}============================================================${RESET}"

# ============================================================
# COMPLETE
# ============================================================

echo
echo
echo "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
echo "${GREEN}${BOLD}              ALL REQUIRED QUERIES COMPLETED                ${RESET}"
echo "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
echo
echo "${MAGENTA}${BOLD}                     © ePlus.DEV${RESET}"
echo