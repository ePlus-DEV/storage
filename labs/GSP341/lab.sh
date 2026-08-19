#!/bin/bash

main() {
set -euo pipefail

# ============================================================
# COLORS
# ============================================================
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

clear

echo "${CYAN}${BOLD}"
echo "====================================================================="
echo "     Create ML Models with BigQuery ML: Challenge Lab - GSP341"
echo "                  © ePlus.DEV"
echo "====================================================================="
echo "${RESET}"

# ============================================================
# PROJECT
# ============================================================
PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"

if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "${RED}Could not detect Project ID.${RESET}"
  return 1
fi

gcloud config set project "$PROJECT_ID" --quiet >/dev/null

echo "${GREEN}Project ID : ${PROJECT_ID}${RESET}"

# ============================================================
# LOCATION
# ============================================================
echo
echo "${BLUE}[1/7] Detecting BigQuery dataset location...${RESET}"

LOCATION="$(
  bq show \
    --format=json \
    data-to-insights:ecommerce 2>/dev/null |
    python3 -c 'import sys,json; print(json.load(sys.stdin).get("location","US"))' \
    2>/dev/null || true
)"

LOCATION="${LOCATION:-US}"

echo "${GREEN}Location   : ${LOCATION}${RESET}"

# ============================================================
# ENABLE API
# ============================================================
echo
echo "${BLUE}[2/7] Enabling BigQuery API...${RESET}"

gcloud services enable bigquery.googleapis.com --quiet

echo "${GREEN}✓ BigQuery API ready.${RESET}"

# ============================================================
# DATASET
# ============================================================
echo
echo "${BLUE}[3/7] TASK 1 - Creating ecommerce dataset...${RESET}"

if bq show "${PROJECT_ID}:ecommerce" >/dev/null 2>&1; then
  echo "${YELLOW}Dataset ecommerce already exists.${RESET}"
else
  bq mk \
    --dataset \
    --location="$LOCATION" \
    "${PROJECT_ID}:ecommerce"

  echo "${GREEN}✓ Dataset ecommerce created.${RESET}"
fi

# ============================================================
# TASK 1 - MODEL 1
# ============================================================
echo
echo "${MAGENTA}============================================================${RESET}"
echo "${BLUE}[4/7] TASK 1 - Creating customer_classification_model${RESET}"
echo "${MAGENTA}============================================================${RESET}"

cat > /tmp/task1.sql <<'SQL'
CREATE OR REPLACE MODEL `ecommerce.customer_classification_model`
OPTIONS
(
  model_type = 'logistic_reg',
  labels = ['will_buy_on_return_visit']
)
AS

SELECT
  * EXCEPT(fullVisitorId)
FROM

(
  SELECT
    fullVisitorId,
    IFNULL(totals.bounces, 0) AS bounces,
    IFNULL(totals.timeOnSite, 0) AS time_on_site
  FROM
    `data-to-insights.ecommerce.web_analytics`
  WHERE
    totals.newVisits = 1
    AND date BETWEEN '20160801' AND '20170430'
)

JOIN

(
  SELECT
    fullvisitorid,
    IF(
      COUNTIF(
        totals.transactions > 0
        AND totals.newVisits IS NULL
      ) > 0,
      1,
      0
    ) AS will_buy_on_return_visit
  FROM
    `data-to-insights.ecommerce.web_analytics`
  GROUP BY
    fullvisitorid
)

USING (fullVisitorId);
SQL

bq query \
  --project_id="$PROJECT_ID" \
  --use_legacy_sql=false \
  < /tmp/task1.sql

echo "${GREEN}✓ customer_classification_model created.${RESET}"

# ============================================================
# TASK 2 - EVALUATE MODEL 1
# ============================================================
echo
echo "${MAGENTA}============================================================${RESET}"
echo "${BLUE}[5/7] TASK 2 - Evaluating customer_classification_model${RESET}"
echo "${MAGENTA}============================================================${RESET}"

cat > /tmp/task2.sql <<'SQL'
SELECT
  roc_auc,
  CASE
    WHEN roc_auc > .9 THEN 'good'
    WHEN roc_auc > .8 THEN 'fair'
    WHEN roc_auc > .7 THEN 'decent'
    WHEN roc_auc > .6 THEN 'not great'
    ELSE 'poor'
  END AS model_quality
FROM

ML.EVALUATE(
  MODEL `ecommerce.customer_classification_model`,
  (
    SELECT
      * EXCEPT(fullVisitorId)
    FROM

    (
      SELECT
        fullVisitorId,
        IFNULL(totals.bounces, 0) AS bounces,
        IFNULL(totals.timeOnSite, 0) AS time_on_site
      FROM
        `data-to-insights.ecommerce.web_analytics`
      WHERE
        totals.newVisits = 1
        AND date BETWEEN '20170501' AND '20170630'
    )

    JOIN

    (
      SELECT
        fullvisitorid,
        IF(
          COUNTIF(
            totals.transactions > 0
            AND totals.newVisits IS NULL
          ) > 0,
          1,
          0
        ) AS will_buy_on_return_visit
      FROM
        `data-to-insights.ecommerce.web_analytics`
      GROUP BY
        fullvisitorid
    )

    USING (fullVisitorId)
  )
);
SQL

bq query \
  --project_id="$PROJECT_ID" \
  --use_legacy_sql=false \
  < /tmp/task2.sql

echo "${GREEN}✓ customer_classification_model evaluated.${RESET}"

# ============================================================
# TASK 3 - IMPROVED MODEL
# ============================================================
echo
echo "${MAGENTA}============================================================${RESET}"
echo "${BLUE}[6/7] TASK 3 - Creating improved model${RESET}"
echo "${MAGENTA}============================================================${RESET}"

cat > /tmp/task3-create.sql <<'SQL'
CREATE OR REPLACE MODEL
  `ecommerce.improved_customer_classification_model`

OPTIONS
(
  model_type = 'logistic_reg',
  labels = ['will_buy_on_return_visit']
)

AS

WITH all_visitor_stats AS
(
  SELECT
    fullvisitorid,

    IF(
      COUNTIF(
        totals.transactions > 0
        AND totals.newVisits IS NULL
      ) > 0,
      1,
      0
    ) AS will_buy_on_return_visit

  FROM
    `data-to-insights.ecommerce.web_analytics`

  GROUP BY
    fullvisitorid
)

SELECT
  * EXCEPT(unique_session_id)

FROM
(
  SELECT
    CONCAT(
      fullvisitorid,
      CAST(visitId AS STRING)
    ) AS unique_session_id,

    will_buy_on_return_visit,

    MAX(
      CAST(
        h.eCommerceAction.action_type AS INT64
      )
    ) AS latest_ecommerce_progress,

    IFNULL(totals.bounces, 0) AS bounces,

    IFNULL(
      totals.timeOnSite,
      0
    ) AS time_on_site,

    IFNULL(
      totals.pageviews,
      0
    ) AS pageviews,

    trafficSource.source,
    trafficSource.medium,
    channelGrouping,

    device.deviceCategory,

    IFNULL(
      geoNetwork.country,
      ''
    ) AS country

  FROM
    `data-to-insights.ecommerce.web_analytics`,
    UNNEST(hits) AS h

  JOIN
    all_visitor_stats
  USING(fullvisitorid)

  WHERE
    totals.newVisits = 1

    AND date BETWEEN
      '20160801'
      AND '20170430'

  GROUP BY
    unique_session_id,
    will_buy_on_return_visit,
    bounces,
    time_on_site,
    totals.pageviews,
    trafficSource.source,
    trafficSource.medium,
    channelGrouping,
    device.deviceCategory,
    country
);
SQL

bq query \
  --project_id="$PROJECT_ID" \
  --use_legacy_sql=false \
  < /tmp/task3-create.sql

echo "${GREEN}✓ improved_customer_classification_model created.${RESET}"

# ============================================================
# TASK 3 - EVALUATE IMPROVED MODEL
# ============================================================
echo
echo "${CYAN}Evaluating improved_customer_classification_model...${RESET}"

cat > /tmp/task3-evaluate.sql <<'SQL'
SELECT
  roc_auc,

  CASE
    WHEN roc_auc > .9 THEN 'good'
    WHEN roc_auc > .8 THEN 'fair'
    WHEN roc_auc > .7 THEN 'decent'
    WHEN roc_auc > .6 THEN 'not great'
    ELSE 'poor'
  END AS model_quality

FROM

ML.EVALUATE(
  MODEL `ecommerce.improved_customer_classification_model`,

  (

    WITH all_visitor_stats AS
    (
      SELECT
        fullvisitorid,

        IF(
          COUNTIF(
            totals.transactions > 0
            AND totals.newVisits IS NULL
          ) > 0,
          1,
          0
        ) AS will_buy_on_return_visit

      FROM
        `data-to-insights.ecommerce.web_analytics`

      GROUP BY
        fullvisitorid
    )

    SELECT
      * EXCEPT(unique_session_id)

    FROM
    (
      SELECT
        CONCAT(
          fullvisitorid,
          CAST(visitId AS STRING)
        ) AS unique_session_id,

        will_buy_on_return_visit,

        MAX(
          CAST(
            h.eCommerceAction.action_type AS INT64
          )
        ) AS latest_ecommerce_progress,

        IFNULL(totals.bounces, 0) AS bounces,

        IFNULL(
          totals.timeOnSite,
          0
        ) AS time_on_site,

        IFNULL(
          totals.pageviews,
          0
        ) AS pageviews,

        trafficSource.source,
        trafficSource.medium,
        channelGrouping,

        device.deviceCategory,

        IFNULL(
          geoNetwork.country,
          ''
        ) AS country

      FROM
        `data-to-insights.ecommerce.web_analytics`,
        UNNEST(hits) AS h

      JOIN
        all_visitor_stats
      USING(fullvisitorid)

      WHERE
        totals.newVisits = 1

        AND date BETWEEN
          '20170501'
          AND '20170630'

      GROUP BY
        unique_session_id,
        will_buy_on_return_visit,
        bounces,
        time_on_site,
        totals.pageviews,
        trafficSource.source,
        trafficSource.medium,
        channelGrouping,
        device.deviceCategory,
        country
    )
  )
);
SQL

bq query \
  --project_id="$PROJECT_ID" \
  --use_legacy_sql=false \
  < /tmp/task3-evaluate.sql

echo "${GREEN}✓ improved_customer_classification_model evaluated.${RESET}"

# ============================================================
# TASK 4 - FINALIZED MODEL
# ============================================================
echo
echo "${MAGENTA}============================================================${RESET}"
echo "${BLUE}[7/7] TASK 4 - Creating finalized model + prediction${RESET}"
echo "${MAGENTA}============================================================${RESET}"

cat > /tmp/task4-create.sql <<'SQL'
CREATE OR REPLACE MODEL
  `ecommerce.finalized_classification_model`

OPTIONS
(
  model_type = 'logistic_reg',
  labels = ['will_buy_on_return_visit']
)

AS

WITH all_visitor_stats AS
(
  SELECT
    fullvisitorid,

    IF(
      COUNTIF(
        totals.transactions > 0
        AND totals.newVisits IS NULL
      ) > 0,
      1,
      0
    ) AS will_buy_on_return_visit

  FROM
    `data-to-insights.ecommerce.web_analytics`

  GROUP BY
    fullvisitorid
)

SELECT
  * EXCEPT(unique_session_id)

FROM
(
  SELECT
    CONCAT(
      fullvisitorid,
      CAST(visitId AS STRING)
    ) AS unique_session_id,

    will_buy_on_return_visit,

    MAX(
      CAST(
        h.eCommerceAction.action_type AS INT64
      )
    ) AS latest_ecommerce_progress,

    IFNULL(
      totals.bounces,
      0
    ) AS bounces,

    IFNULL(
      totals.timeOnSite,
      0
    ) AS time_on_site,

    IFNULL(
      totals.pageviews,
      0
    ) AS pageviews,

    trafficSource.source,
    trafficSource.medium,
    channelGrouping,

    device.deviceCategory,

    IFNULL(
      geoNetwork.country,
      ''
    ) AS country

  FROM
    `data-to-insights.ecommerce.web_analytics`,
    UNNEST(hits) AS h

  JOIN
    all_visitor_stats
  USING(fullvisitorid)

  WHERE
    totals.newVisits = 1

    AND date BETWEEN
      '20160801'
      AND '20170430'

  GROUP BY
    unique_session_id,
    will_buy_on_return_visit,
    bounces,
    time_on_site,
    totals.pageviews,
    trafficSource.source,
    trafficSource.medium,
    channelGrouping,
    device.deviceCategory,
    country
);
SQL

bq query \
  --project_id="$PROJECT_ID" \
  --use_legacy_sql=false \
  < /tmp/task4-create.sql

echo "${GREEN}✓ finalized_classification_model created.${RESET}"

# ============================================================
# TASK 4 - PREDICT JULY 2017
# ============================================================
echo
echo "${CYAN}Running ML.PREDICT for the final month...${RESET}"

cat > /tmp/task4-predict.sql <<'SQL'
SELECT
  *

FROM

ML.PREDICT(
  MODEL `ecommerce.finalized_classification_model`,

  (

    WITH all_visitor_stats AS
    (
      SELECT
        fullvisitorid,

        IF(
          COUNTIF(
            totals.transactions > 0
            AND totals.newVisits IS NULL
          ) > 0,
          1,
          0
        ) AS will_buy_on_return_visit

      FROM
        `data-to-insights.ecommerce.web_analytics`

      GROUP BY
        fullvisitorid
    )

    SELECT
      CONCAT(
        fullvisitorid,
        '-',
        CAST(visitId AS STRING)
      ) AS unique_session_id,

      will_buy_on_return_visit,

      MAX(
        CAST(
          h.eCommerceAction.action_type AS INT64
        )
      ) AS latest_ecommerce_progress,

      IFNULL(
        totals.bounces,
        0
      ) AS bounces,

      IFNULL(
        totals.timeOnSite,
        0
      ) AS time_on_site,

      IFNULL(
        totals.pageviews,
        0
      ) AS pageviews,

      trafficSource.source,
      trafficSource.medium,
      channelGrouping,

      device.deviceCategory,

      IFNULL(
        geoNetwork.country,
        ''
      ) AS country

    FROM
      `data-to-insights.ecommerce.web_analytics`,
      UNNEST(hits) AS h

    JOIN
      all_visitor_stats
    USING(fullvisitorid)

    WHERE
      totals.newVisits = 1

      AND date BETWEEN
        '20170701'
        AND '20170801'

    GROUP BY
      unique_session_id,
      will_buy_on_return_visit,
      bounces,
      time_on_site,
      totals.pageviews,
      trafficSource.source,
      trafficSource.medium,
      channelGrouping,
      device.deviceCategory,
      country
  )
)

ORDER BY
  predicted_will_buy_on_return_visit DESC;
SQL

bq query \
  --project_id="$PROJECT_ID" \
  --use_legacy_sql=false \
  --max_rows=20 \
  < /tmp/task4-predict.sql

echo
echo "${CYAN}${BOLD}"
echo "============================================================"
echo "               BIGQUERY ML LAB COMPLETE"
echo "============================================================"
echo "${RESET}"

echo "${GREEN}✓ TASK 1 - ecommerce dataset created"
echo "✓ TASK 1 - customer_classification_model created"
echo "✓ TASK 2 - customer_classification_model evaluated"
echo "✓ TASK 3 - improved_customer_classification_model created"
echo "✓ TASK 3 - improved model evaluated"
echo "✓ TASK 4 - finalized_classification_model created"
echo "✓ TASK 4 - ML.PREDICT executed"
echo "${RESET}"

echo "${YELLOW}Now click Check my progress for Task 1 → Task 4.${RESET}"
echo
echo "${CYAN}© ePlus.DEV${RESET}"
}

(
  set -euo pipefail
  main "$@"
)

STATUS=$?

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return "$STATUS"
else
  exit "$STATUS"
fi