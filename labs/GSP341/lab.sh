#!/bin/bash

# ============================================================
# BigQuery ML Challenge Lab
# © ePlus.DEV
# ============================================================

main() {

# ------------------------------------------------------------
# COLORS
# ------------------------------------------------------------
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
echo "======================================================================"
echo "             BIGQUERY ML CHALLENGE LAB"
echo "                     © ePlus.DEV"
echo "======================================================================"
echo "${RESET}"

# ------------------------------------------------------------
# PROJECT
# ------------------------------------------------------------
PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"

if [[ -z "$PROJECT_ID" ]]; then
    PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
fi

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    echo "${RED}ERROR: Could not detect Project ID.${RESET}"
    return 1
fi

gcloud config set project "$PROJECT_ID" --quiet >/dev/null 2>&1

echo "${GREEN}Project ID : ${PROJECT_ID}${RESET}"
echo "${GREEN}Location   : US${RESET}"

# ------------------------------------------------------------
# ENABLE API
# ------------------------------------------------------------
echo
echo "${BLUE}[1/8] Enabling BigQuery API${RESET}"
echo "----------------------------------------------------------------------"

gcloud services enable bigquery.googleapis.com --quiet

echo "${GREEN}✓ BigQuery API enabled.${RESET}"

# ------------------------------------------------------------
# TASK 1 - DATASET
# ------------------------------------------------------------
echo
echo "${BLUE}[2/8] TASK 1 - Creating ecommerce dataset${RESET}"
echo "----------------------------------------------------------------------"

if bq show "${PROJECT_ID}:ecommerce" >/dev/null 2>&1; then
    echo "${YELLOW}Dataset ecommerce already exists.${RESET}"
else
    bq mk \
        --dataset \
        --location=US \
        "${PROJECT_ID}:ecommerce"

    echo "${GREEN}✓ Dataset ecommerce created.${RESET}"
fi

# ------------------------------------------------------------
# TASK 1 - CUSTOMER CLASSIFICATION MODEL
# ------------------------------------------------------------
echo
echo "${BLUE}[3/8] TASK 1 - Creating customer_classification_model${RESET}"
echo "----------------------------------------------------------------------"

bq query \
--project_id="$PROJECT_ID" \
--location=US \
--use_legacy_sql=false \
--nouse_cache \
'
CREATE OR REPLACE MODEL `ecommerce.customer_classification_model`
OPTIONS
(
    model_type = "logistic_reg",
    labels = ["will_buy_on_return_visit"]
)
AS

SELECT
    * EXCEPT(fullVisitorId)

FROM

(
    SELECT
        fullVisitorId,

        IFNULL(
            totals.bounces,
            0
        ) AS bounces,

        IFNULL(
            totals.timeOnSite,
            0
        ) AS time_on_site

    FROM
        `data-to-insights.ecommerce.web_analytics`

    WHERE
        totals.newVisits = 1

        AND date BETWEEN
            "20160801"
            AND "20170430"
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

USING(fullVisitorId);
'

if [[ $? -ne 0 ]]; then
    echo "${RED}✗ Failed to create customer_classification_model.${RESET}"
    return 1
fi

echo "${GREEN}✓ customer_classification_model created.${RESET}"

# ------------------------------------------------------------
# TASK 2 - EVALUATE FIRST MODEL
# ------------------------------------------------------------
echo
echo "${BLUE}[4/8] TASK 2 - Evaluating customer_classification_model${RESET}"
echo "----------------------------------------------------------------------"

bq query \
--project_id="$PROJECT_ID" \
--location=US \
--use_legacy_sql=false \
--nouse_cache \
'
SELECT
    roc_auc,

    CASE
        WHEN roc_auc > .9 THEN "good"
        WHEN roc_auc > .8 THEN "fair"
        WHEN roc_auc > .7 THEN "decent"
        WHEN roc_auc > .6 THEN "not great"
        ELSE "poor"
    END AS model_quality

FROM

ML.EVALUATE
(
    MODEL `ecommerce.customer_classification_model`,

    (
        SELECT
            * EXCEPT(fullVisitorId)

        FROM

        (
            SELECT
                fullVisitorId,

                IFNULL(
                    totals.bounces,
                    0
                ) AS bounces,

                IFNULL(
                    totals.timeOnSite,
                    0
                ) AS time_on_site

            FROM
                `data-to-insights.ecommerce.web_analytics`

            WHERE
                totals.newVisits = 1

                AND date BETWEEN
                    "20170501"
                    AND "20170630"
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

        USING(fullVisitorId)
    )
);
'

if [[ $? -ne 0 ]]; then
    echo "${RED}✗ Failed to evaluate first model.${RESET}"
    return 1
fi

echo "${GREEN}✓ customer_classification_model evaluated.${RESET}"

# ------------------------------------------------------------
# TASK 3 - IMPROVED MODEL
# ------------------------------------------------------------
echo
echo "${BLUE}[5/8] TASK 3 - Creating improved_customer_classification_model${RESET}"
echo "----------------------------------------------------------------------"

bq query \
--project_id="$PROJECT_ID" \
--location=US \
--use_legacy_sql=false \
--nouse_cache \
'
CREATE OR REPLACE MODEL
    `ecommerce.improved_customer_classification_model`

OPTIONS
(
    model_type = "logistic_reg",
    labels = ["will_buy_on_return_visit"]
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
                h.eCommerceAction.action_type
                AS INT64
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
            ""
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
            "20160801"
            AND "20170430"

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
'

if [[ $? -ne 0 ]]; then
    echo "${RED}✗ Failed to create improved model.${RESET}"
    return 1
fi

echo "${GREEN}✓ improved_customer_classification_model created.${RESET}"

# ------------------------------------------------------------
# TASK 3 - EVALUATE IMPROVED MODEL
# ------------------------------------------------------------
echo
echo "${BLUE}[6/8] TASK 3 - Evaluating improved model${RESET}"
echo "----------------------------------------------------------------------"

bq query \
--project_id="$PROJECT_ID" \
--location=US \
--use_legacy_sql=false \
--nouse_cache \
'
SELECT

    roc_auc,

    CASE
        WHEN roc_auc > .9 THEN "good"
        WHEN roc_auc > .8 THEN "fair"
        WHEN roc_auc > .7 THEN "decent"
        WHEN roc_auc > .6 THEN "not great"
        ELSE "poor"
    END AS model_quality

FROM

ML.EVALUATE
(
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
                        h.eCommerceAction.action_type
                        AS INT64
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

                totals.pageviews,

                trafficSource.source,

                trafficSource.medium,

                channelGrouping,

                device.deviceCategory,

                IFNULL(
                    geoNetwork.country,
                    ""
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
                    "20170501"
                    AND "20170630"

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
'

if [[ $? -ne 0 ]]; then
    echo "${RED}✗ Failed to evaluate improved model.${RESET}"
    return 1
fi

echo "${GREEN}✓ improved_customer_classification_model evaluated.${RESET}"

# ------------------------------------------------------------
# TASK 4 - FINALIZED MODEL
# ------------------------------------------------------------
echo
echo "${BLUE}[7/8] TASK 4 - Creating finalized_classification_model${RESET}"
echo "----------------------------------------------------------------------"

bq query \
--project_id="$PROJECT_ID" \
--location=US \
--use_legacy_sql=false \
--nouse_cache \
'
CREATE OR REPLACE MODEL
    `ecommerce.finalized_classification_model`

OPTIONS
(
    model_type = "logistic_reg",
    labels = ["will_buy_on_return_visit"]
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
                h.eCommerceAction.action_type
                AS INT64
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
            ""
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
            "20160801"
            AND "20170430"

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
'

if [[ $? -ne 0 ]]; then
    echo "${RED}✗ Failed to create finalized model.${RESET}"
    return 1
fi

echo "${GREEN}✓ finalized_classification_model created.${RESET}"

# ------------------------------------------------------------
# VERIFY FINALIZED MODEL
# ------------------------------------------------------------
echo
echo "${CYAN}Verifying finalized model...${RESET}"

if bq show \
    --model \
    "${PROJECT_ID}:ecommerce.finalized_classification_model" \
    >/dev/null 2>&1
then
    echo "${GREEN}✓ finalized_classification_model exists.${RESET}"
else
    echo "${RED}✗ finalized_classification_model not found.${RESET}"
    return 1
fi

# ------------------------------------------------------------
# TASK 4 - PREDICT JULY 2017
# IMPORTANT:
# This query intentionally follows the lab prediction query.
# ------------------------------------------------------------
echo
echo "${BLUE}[8/8] TASK 4 - Predicting returning purchasers${RESET}"
echo "----------------------------------------------------------------------"
echo "${YELLOW}Running ML.PREDICT on July 2017 data...${RESET}"
echo

bq query \
--project_id="$PROJECT_ID" \
--location=US \
--use_legacy_sql=false \
--nouse_cache \
--max_rows=30 \
'
SELECT
    *

FROM

ML.PREDICT
(
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
                "-",
                CAST(visitId AS STRING)
            ) AS unique_session_id,

            will_buy_on_return_visit,

            MAX(
                CAST(
                    h.eCommerceAction.action_type
                    AS INT64
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

            totals.pageviews,

            trafficSource.source,

            trafficSource.medium,

            channelGrouping,

            device.deviceCategory,

            IFNULL(
                geoNetwork.country,
                ""
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
                "20170701"
                AND "20170801"

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
'

TASK4_STATUS=$?

echo

if [[ $TASK4_STATUS -ne 0 ]]; then
    echo "${RED}"
    echo "======================================================================"
    echo " TASK 4 ML.PREDICT FAILED"
    echo "======================================================================"
    echo "${RESET}"

    return 1
fi

echo "${GREEN}✓ ML.PREDICT query completed successfully.${RESET}"

# ------------------------------------------------------------
# SHOW MODELS
# ------------------------------------------------------------
echo
echo "${BLUE}Checking created models...${RESET}"
echo "----------------------------------------------------------------------"

bq ls --models "${PROJECT_ID}:ecommerce"

# ------------------------------------------------------------
# COMPLETE
# ------------------------------------------------------------
echo
echo "${CYAN}${BOLD}"
echo "======================================================================"
echo "                 BIGQUERY ML LAB COMPLETE"
echo "======================================================================"
echo "${RESET}"

echo "${GREEN}✓ TASK 1 - ecommerce dataset"
echo "✓ TASK 1 - customer_classification_model"
echo "✓ TASK 2 - ML.EVALUATE first model"
echo "✓ TASK 3 - improved_customer_classification_model"
echo "✓ TASK 3 - ML.EVALUATE improved model"
echo "✓ TASK 4 - finalized_classification_model"
echo "✓ TASK 4 - ML.PREDICT July 2017"
echo "${RESET}"

echo "${YELLOW}${BOLD}Now click Check my progress for Task 1 → Task 4.${RESET}"

echo
echo "${CYAN}© ePlus.DEV${RESET}"
echo

}

# ============================================================
# RUN WITHOUT KILLING CLOUD SHELL WHEN SOURCED
# ============================================================
main
STATUS=$?

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return "$STATUS"
else
    exit "$STATUS"
fi