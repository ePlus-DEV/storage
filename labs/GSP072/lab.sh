#!/usr/bin/env bash

# ePlus.DEV console banner. Presentation only; see repository LICENSE (Unlicense).
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
  _eplus_cyan=$'\033[1;36m'
  _eplus_yellow=$'\033[0;33m'
  _eplus_reset=$'\033[0m'
else
  _eplus_cyan='' _eplus_yellow='' _eplus_reset=''
fi
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
printf '%s\n' "${_eplus_cyan} ePlus.DEV - Starting Execution | GSP072 - BigQuery${_eplus_reset}"
printf '%s\n' "${_eplus_yellow} Copyright (c) 2026 ePlus.DEV | Unlicense${_eplus_reset}"
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
unset _eplus_cyan _eplus_yellow _eplus_reset

bq query --use_legacy_sql=false \
"
#standardSQL
SELECT
 weight_pounds, state, year, gestation_weeks
FROM
 \`bigquery-public-data.samples.natality\`
ORDER BY weight_pounds DESC LIMIT 10;
"

bq mk babynames

bq load --autodetect --source_format=CSV babynames.names_2014 gs://spls/gsp072/baby-names/yob2014.txt name:string,gender:string,count:integer

bq query --use_legacy_sql=false \
"
#standardSQL
SELECT
 name, count
FROM
 \`babynames.names_2014\`
WHERE
 gender = 'M'
ORDER BY count DESC LIMIT 5;
"