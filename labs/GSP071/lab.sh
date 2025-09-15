#!/bin/bash
# ====================================================================================
#  Google Cloud BigQuery Hands-on Lab Script
#  Author      : Nguyễn Ngọc Minh Hoàng (David)
#  Website     : https://eplus.dev
#  Description : Full automation script for Qwiklabs BigQuery lab tasks
#  Copyright   : (c) 2025 David. All rights reserved.
#  License     : For educational/lab use only. Do not use on production systems.
# ====================================================================================

set -euo pipefail

# ========== Debug mode with line number ==========
export PS4='+ [Line ${LINENO}] '
set -x

# ================= Colors =================
BOLD=$(tput bold || true); RESET=$(tput sgr0 || true)
GREEN=$(tput setaf 2 || true); YELLOW=$(tput setaf 3 || true)

banner(){ echo -e "\n${BOLD}${YELLOW}==> $*${RESET}\n"; }

# ================= Project & Auth =================
banner "Check active account & project"
gcloud auth list
gcloud config list project

# ================= Task 1. Examine table =================
banner "Task 1: Show schema of Shakespeare sample table"
bq show bigquery-public-data:samples.shakespeare

# ================= Task 2. Help command =================
banner "Task 2: Explore bq help commands"
bq help query
bq help | head -20

# ================= Task 3. Queries against Shakespeare =================
banner "Task 3: Query substring 'raisin'"
bq query --use_legacy_sql=false \
'SELECT word, SUM(word_count) AS count
 FROM `bigquery-public-data`.samples.shakespeare
 WHERE word LIKE "%raisin%"
 GROUP BY word'

banner "Task 3b: Query word 'huzzah' (expect no results)"
bq query --use_legacy_sql=false \
'SELECT word
 FROM `bigquery-public-data`.samples.shakespeare
 WHERE word = "huzzah"'

# ================= Task 4. Create dataset =================
banner "Task 4: Create dataset 'babynames'"
bq mk babynames
bq ls

# ================= Task 4b. Load data =================
banner "Download and unzip baby names dataset"
wget -q http://www.ssa.gov/OACT/babynames/names.zip
unzip -o names.zip
ls yob2010.txt

banner "Load yob2010.txt into babynames.names2010"
bq load babynames.names2010 yob2010.txt name:string,gender:string,count:integer
bq ls babynames
bq show babynames.names2010

# ================= Task 5. Run queries =================
banner "Task 5a: Top 5 most popular girls names (2010)"
bq query "SELECT name,count FROM babynames.names2010 WHERE gender='F' ORDER BY count DESC LIMIT 5"

banner "Task 5b: Least common boys names (2010)"
bq query "SELECT name,count FROM babynames.names2010 WHERE gender='M' ORDER BY count ASC LIMIT 5"

# ================= Task 6. Quiz notes =================
banner "Task 6: Quiz Quick Answers"
echo "Q1: Access BigQuery using → REST API, Command line tool, Web UI"
echo "Q2: CLI tool for BigQuery → bq"

# ================= Task 7. Clean up =================
banner "Task 7: Remove babynames dataset"
bq rm -r -f babynames

echo -e "\n${GREEN}${BOLD}✔ Lab script completed successfully!${RESET}\n"