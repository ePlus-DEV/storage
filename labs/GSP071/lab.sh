#!/bin/bash

# ============================================================
# GSP071 - BigQuery: Qwik Start - Command Line
# © ePlus.DEV
# ============================================================

BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

RESET_FORMAT=$'\033[0m'
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'

clear

# ============================================================
# HEADER
# ============================================================

echo "${CYAN_TEXT}${BOLD_TEXT}╔════════════════════════════════════════════════════════╗${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}        WELCOME TO ePlus.DEV CLOUD TUTORIAL             ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}╚════════════════════════════════════════════════════════╝${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}          GSP071 - BIGQUERY COMMAND LINE                ${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}                   © ePlus.DEV                           ${RESET_FORMAT}"
echo

# ============================================================
# DETECT PROJECT
# ============================================================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    echo "${RED_TEXT}${BOLD_TEXT}✗ Unable to detect Project ID.${RESET_FORMAT}"
    exit 1
fi

echo "${GREEN_TEXT}✓ Project ID : ${PROJECT_ID}${RESET_FORMAT}"
echo

# ============================================================
# TASK 1
# ============================================================

echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}[TASK 1] Examine Shakespeare table${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo

bq show bigquery-public-data:samples.shakespeare

echo
echo "${GREEN_TEXT}✓ Task 1 completed.${RESET_FORMAT}"
echo

# ============================================================
# TASK 2
# ============================================================

echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}[TASK 2] BigQuery CLI Help${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo

bq help query | head -n 30

echo
echo "${GREEN_TEXT}✓ Task 2 completed.${RESET_FORMAT}"
echo

# ============================================================
# TASK 3
# ============================================================

echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}[TASK 3] Query Shakespeare public dataset${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo

echo "${YELLOW_TEXT}${BOLD_TEXT}➜ Searching for substring: raisin${RESET_FORMAT}"
echo

bq query --use_legacy_sql=false \
'SELECT
   word,
   SUM(word_count) AS count
 FROM
   `bigquery-public-data.samples.shakespeare`
 WHERE
   word LIKE "%raisin%"
 GROUP BY
   word'

echo
echo "${GREEN_TEXT}✓ Raisin query completed.${RESET_FORMAT}"
echo

echo "${YELLOW_TEXT}${BOLD_TEXT}➜ Searching for word: huzzah${RESET_FORMAT}"
echo

bq query --use_legacy_sql=false \
'SELECT
   word
 FROM
   `bigquery-public-data.samples.shakespeare`
 WHERE
   word = "huzzah"'

echo
echo "${GREEN_TEXT}✓ Huzzah query completed.${RESET_FORMAT}"
echo

# ============================================================
# TASK 4 - DATASET
# ============================================================

echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}[TASK 4] Create babynames dataset${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo

if bq show "${PROJECT_ID}:babynames" >/dev/null 2>&1; then

    echo "${GREEN_TEXT}✓ Dataset babynames already exists.${RESET_FORMAT}"

else

    echo "${YELLOW_TEXT}➜ Creating dataset babynames...${RESET_FORMAT}"

    bq mk \
        --dataset \
        "${PROJECT_ID}:babynames"

    if [[ $? -ne 0 ]]; then
        echo "${RED_TEXT}✗ Failed to create babynames dataset.${RESET_FORMAT}"
        exit 1
    fi

    echo "${GREEN_TEXT}✓ Dataset babynames created.${RESET_FORMAT}"

fi

echo

# ============================================================
# DOWNLOAD DATA
# ============================================================

echo "${YELLOW_TEXT}${BOLD_TEXT}➜ Downloading baby names dataset...${RESET_FORMAT}"
echo

rm -f names.zip

wget \
    --quiet \
    --show-progress \
    -O names.zip \
    "https://www.ssa.gov/OACT/babynames/names.zip"

if [[ ! -s names.zip ]]; then
    echo "${RED_TEXT}✗ Failed to download names.zip.${RESET_FORMAT}"
    exit 1
fi

echo
echo "${GREEN_TEXT}✓ Dataset downloaded.${RESET_FORMAT}"
echo

# ============================================================
# EXTRACT
# ============================================================

echo "${YELLOW_TEXT}${BOLD_TEXT}➜ Extracting yob2010.txt...${RESET_FORMAT}"
echo

rm -f yob2010.txt

unzip -o -q names.zip yob2010.txt

if [[ ! -f yob2010.txt ]]; then
    echo "${RED_TEXT}✗ yob2010.txt not found.${RESET_FORMAT}"
    exit 1
fi

echo "${GREEN_TEXT}✓ yob2010.txt extracted.${RESET_FORMAT}"
echo

# ============================================================
# LOAD TABLE
# ============================================================

echo "${YELLOW_TEXT}${BOLD_TEXT}➜ Checking babynames.names2010...${RESET_FORMAT}"
echo

if bq show "${PROJECT_ID}:babynames.names2010" >/dev/null 2>&1; then

    echo "${GREEN_TEXT}✓ Table names2010 already exists.${RESET_FORMAT}"

else

    echo "${YELLOW_TEXT}➜ Loading yob2010.txt into BigQuery...${RESET_FORMAT}"
    echo

    bq load \
        --source_format=CSV \
        "${PROJECT_ID}:babynames.names2010" \
        yob2010.txt \
        name:string,gender:string,count:integer

    if [[ $? -ne 0 ]]; then
        echo "${RED_TEXT}✗ Failed to load table.${RESET_FORMAT}"
        exit 1
    fi

    echo
    echo "${GREEN_TEXT}✓ Table names2010 loaded successfully.${RESET_FORMAT}"

fi

echo

# ============================================================
# VERIFY TABLE
# ============================================================

echo "${YELLOW_TEXT}${BOLD_TEXT}➜ Current babynames tables:${RESET_FORMAT}"
echo

bq ls "${PROJECT_ID}:babynames"

echo

echo "${YELLOW_TEXT}${BOLD_TEXT}➜ names2010 table information:${RESET_FORMAT}"
echo

bq show "${PROJECT_ID}:babynames.names2010"

echo

# ============================================================
# TASK 5
# ============================================================

echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}[TASK 5] Query custom table${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo

echo "${YELLOW_TEXT}${BOLD_TEXT}➜ Top 5 most popular female names:${RESET_FORMAT}"
echo

bq query --use_legacy_sql=false \
"SELECT
    name,
    count
 FROM
    \`${PROJECT_ID}.babynames.names2010\`
 WHERE
    gender = 'F'
 ORDER BY
    count DESC
 LIMIT 5"

echo

echo "${YELLOW_TEXT}${BOLD_TEXT}➜ 5 least common male names:${RESET_FORMAT}"
echo

bq query --use_legacy_sql=false \
"SELECT
    name,
    count
 FROM
    \`${PROJECT_ID}.babynames.names2010\`
 WHERE
    gender = 'M'
 ORDER BY
    count ASC
 LIMIT 5"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}✓ Task 5 completed.${RESET_FORMAT}"
echo

# ============================================================
# WAIT FOR CHECK MY PROGRESS
# ============================================================

echo
echo "${YELLOW_TEXT}${BOLD_TEXT}╔════════════════════════════════════════════════════════╗${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}                 CHECKPOINT                             ${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}╚════════════════════════════════════════════════════════╝${RESET_FORMAT}"
echo

echo "${WHITE_TEXT}${BOLD_TEXT}Go back to the lab page and click:${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}  ✓ Check my progress - Raisin query${RESET_FORMAT}"
echo "${GREEN_TEXT}  ✓ Check my progress - Huzzah query${RESET_FORMAT}"
echo "${GREEN_TEXT}  ✓ Check my progress - Create babynames dataset${RESET_FORMAT}"
echo "${GREEN_TEXT}  ✓ Check my progress - Load names2010 table${RESET_FORMAT}"
echo "${GREEN_TEXT}  ✓ Check my progress - Query custom table${RESET_FORMAT}"
echo

echo "${YELLOW_TEXT}${BOLD_TEXT}DO NOT continue until all previous tasks are marked green.${RESET_FORMAT}"
echo

# ============================================================
# WAIT FOR USER
# ============================================================

while true; do

    read -rp "$(echo -e "${CYAN_TEXT}${BOLD_TEXT}Have all previous Check my progress tasks passed? Press Y to continue cleanup: ${RESET_FORMAT}")" ANSWER

    case "$ANSWER" in

        [Yy])

            echo
            echo "${GREEN_TEXT}${BOLD_TEXT}✓ Continuing to Task 7...${RESET_FORMAT}"
            break
            ;;

        [Nn])

            echo
            echo "${YELLOW_TEXT}Lab resources are being kept.${RESET_FORMAT}"
            echo "${YELLOW_TEXT}Check the grader again, then press Y when ready.${RESET_FORMAT}"
            echo
            ;;

        *)

            echo
            echo "${RED_TEXT}Please enter Y or N.${RESET_FORMAT}"
            echo
            ;;

    esac

done

# ============================================================
# TASK 7 - CLEANUP
# ============================================================

echo
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}[TASK 7] Remove babynames dataset${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo

echo "${RED_TEXT}${BOLD_TEXT}➜ Removing babynames dataset...${RESET_FORMAT}"
echo

bq rm \
    -r \
    -f \
    "${PROJECT_ID}:babynames"

if [[ $? -eq 0 ]]; then
    echo
    echo "${GREEN_TEXT}${BOLD_TEXT}✓ babynames dataset removed successfully.${RESET_FORMAT}"
else
    echo
    echo "${RED_TEXT}${BOLD_TEXT}✗ Failed to remove babynames dataset.${RESET_FORMAT}"
    exit 1
fi

# ============================================================
# LOCAL CLEANUP
# ============================================================

rm -f names.zip yob2010.txt

# ============================================================
# FINAL CHECKPOINT
# ============================================================

echo
echo "${GREEN_TEXT}${BOLD_TEXT}╔════════════════════════════════════════════════════════╗${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}            LAB EXECUTION COMPLETED                     ${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}╚════════════════════════════════════════════════════════╝${RESET_FORMAT}"
echo

echo "${YELLOW_TEXT}${BOLD_TEXT}➜ Go back to the lab and click:${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}${BOLD_TEXT}  Check my progress - Remove the babynames dataset${RESET_FORMAT}"
echo

echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}                       © ePlus.DEV                         ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo