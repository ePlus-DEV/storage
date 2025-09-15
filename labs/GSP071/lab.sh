#!/bin/bash
# ====================================================================================
#  Google Cloud BigQuery Hands-on Lab Script
#  Author      : Nguyễn Ngọc Minh Hoàng (David)
#  Website     : https://eplus.dev
#  Description : End-to-end script for Qwiklabs BigQuery lab tasks
#  Copyright   : (c) 2025 Nguyễn Ngọc Minh Hoàng. All rights reserved.
#  License     : For educational/lab use only. Do not use on production systems.
# ====================================================================================

set -euo pipefail

# Colors
BOLD=$(tput bold || true); RESET=$(tput sgr0 || true)
GREEN=$(tput setaf 2 || true); YELLOW=$(tput setaf 3 || true)

banner(){ echo -e "\n${BOLD}${YELLOW}==> $*${RESET}\n"; }
done_msg(){ echo -e "${GREEN}✔ Completed${RESET}\n"; }

# Bản quyền
echo -e "${BOLD}Google Cloud BigQuery Hands-on Lab Script${RESET}"
echo "Author    : Nguyễn Ngọc Minh Hoàng (David)"
echo "Website   : https://eplus.dev"
echo "Copyright : (c) 2025 All rights reserved."
echo "--------------------------------------------"

# ================= Task 1 =================
banner "Task 1: Show schema of Shakespeare sample table"
bq show bigquery-public-data:samples.shakespeare >/dev/null
done_msg

# ================= Task 2 =================
banner "Task 2: Help command"
bq help query >/dev/null
bq help >/dev/null
done_msg

# ================= Task 3 =================
banner "Task 3a: Query substring 'raisin'"
bq query --use_legacy_sql=false \
'SELECT word, SUM(word_count) AS count
 FROM `bigquery-public-data`.samples.shakespeare
 WHERE word LIKE "%raisin%"
 GROUP BY word' >/dev/null
done_msg

banner "Task 3b: Query word 'huzzah'"
bq query --use_legacy_sql=false \
'SELECT word
 FROM `bigquery-public-data`.samples.shakespeare
 WHERE word = "huzzah"' >/dev/null
done_msg

# ================= Task 4 =================
banner "Task 4a: Create dataset 'babynames'"
bq mk babynames >/dev/null
done_msg

banner "Task 4b: Download & unzip baby names"
curl -s -LO http://www.ssa.gov/OACT/babynames/names.zip || wget -q http://www.ssa.gov/OACT/babynames/names.zip
unzip -o -q names.zip
done_msg

banner "Task 4c: Load yob2010.txt into table"
bq load babynames.names2010 yob2010.txt name:string,gender:string,count:integer >/dev/null
done_msg

# ================= Task 5 =================
banner "Task 5a: Query top 5 most popular girls names"
bq query "SELECT name,count FROM babynames.names2010 WHERE gender = 'F' ORDER BY count DESC LIMIT 5" >/dev/null
done_msg

banner "Task 5b: Query least common boys names"
bq query "SELECT name,count FROM babynames.names2010 WHERE gender = 'M' ORDER BY count ASC LIMIT 5" >/dev/null
done_msg

# ================= Task 6 =================
banner "Task 6: Quiz Quick Answers"
echo "Q1: Access BigQuery using → REST API, Command line tool, Web UI"
echo "Q2: CLI tool for BigQuery → bq"
done_msg

# ================= Task 7 =================
banner "Task 7: Wait for grader then remove dataset"
sleep 60
bq rm -r -f babynames >/dev/null
done_msg

echo -e "${GREEN}${BOLD}🎉 Lab script completed successfully!${RESET}"