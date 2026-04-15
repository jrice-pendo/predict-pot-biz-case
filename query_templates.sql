-- ============================================================================
-- PENDO PREDICT POT — Parameterized Query Templates (Athena / Presto SQL)
-- ============================================================================
-- These queries use {{PLACEHOLDERS}} from the customer_config_template.json.
-- Before running, replace each {{PLACEHOLDER}} with the customer's actual
-- field names, object names, and filter conditions.
--
-- Dialect: Athena (Presto/Trino). Key syntax notes:
--   Date math:     DATE_ADD('month', -12, DATE_TRUNC('month', CURRENT_DATE))
--   Date diff:     DATE_DIFF('month', start_date, end_date)
--   Date trunc:    DATE_TRUNC('month', some_date)
--   Safe cast:     TRY_CAST(value AS BIGINT)
--   String match:  LOWER(field) LIKE '%test%'  (no ILIKE in Presto)
--   Division:      Use NULLIF(denominator, 0) to prevent divide-by-zero
--   Types:         CAST join keys to the same type before joining
--
-- CURRENCY CONVERSION:
--   Queries that sum/avg dollar amounts include a fx_rates CTE that converts
--   from the record's CurrencyIsoCode to USD. The CTE uses the SFDC
--   CurrencyType object (IsoCode → ConversionRate). ConversionRate in SFDC
--   is the multiplier to convert FROM the corporate currency TO the local
--   currency, so we divide by it to get back to USD.
--   Formula: amount_usd = local_amount / ConversionRate
--
--   Placeholder: {{CURRENCY_ISO_CODE}} — the field on Opportunity holding
--   the ISO currency code (e.g., CurrencyIsoCode).
-- ============================================================================


-- ============================================================================
-- QUERY 1: DATA READINESS — Account & Opportunity Landscape
-- Dashboard fields: SFDC_TOTAL_ACCOUNTS, SFDC_TOTAL_OPPS, TOTAL_ACCOUNTS
-- ============================================================================
-- [PURPOSE] Count total SFDC accounts and opportunities to establish
--           the size and shape of the customer's CRM data.

SELECT
    COUNT(DISTINCT a.id)                              AS sfdc_total_accounts,
    COUNT(DISTINCT o.{{OPPORTUNITY_ID}})              AS sfdc_total_opps,
    COUNT(DISTINCT CASE
        WHEN o.{{IS_RENEWAL}}
        THEN a.id
    END)                                              AS accounts_with_renewals

FROM {{ACCOUNT_TABLE}} AS a
LEFT JOIN {{RENEWAL_TABLE}} AS o
    ON CAST(o.{{ACCOUNT_ID}} AS VARCHAR)
     = CAST(a.id AS VARCHAR)
    -- [NOTE] CAST both sides to VARCHAR to prevent type mismatch on join

WHERE 1 = 1
    {{EXCLUDE_CONDITIONS}}
;


-- ============================================================================
-- QUERY 2: DATA READINESS — Historical Churn Count & Time Window
-- Dashboard fields: TOTAL_CHURNS, DATA_MONTHS, CLOSED_RENEWALS_PRIOR_YEAR
-- ============================================================================
-- [PURPOSE] Validate model readiness: enough churns (>= 200) and enough
--           history (>= 12 months). These are hard thresholds for Predict.

SELECT
    -- [NOTE] Total churns across ALL available history, not just the lookback
    COUNT(DISTINCT CASE
        WHEN {{IS_CHURN}}
        THEN {{OPPORTUNITY_ID}}
    END)                                              AS total_churns,

    -- [NOTE] Data window = months between earliest and latest closed renewal
    DATE_DIFF(
        'month',
        MIN(CAST({{CLOSE_DATE}} AS DATE)),
        MAX(CAST({{CLOSE_DATE}} AS DATE))
    )                                                 AS data_months,

    -- [NOTE] Closed renewals within the prior-12-month window only
    COUNT(DISTINCT CASE
        WHEN CAST({{CLOSE_DATE}} AS DATE)
             >= DATE_ADD('month', -12, DATE_TRUNC('month', CURRENT_DATE))
        THEN {{OPPORTUNITY_ID}}
    END)                                              AS closed_renewals_prior_year

FROM {{RENEWAL_TABLE}}
WHERE {{IS_RENEWAL}}
    AND {{IS_CLOSED}}
    {{EXCLUDE_CONDITIONS}}
;


-- ============================================================================
-- QUERY 3: DATA READINESS — ARR Field Coverage
-- Dashboard fields: ARR_POPULATED_RATE
-- ============================================================================
-- [PURPOSE] Check what percentage of renewal records have a non-null,
--           non-zero ARR value. Low coverage means dollar-based analyses
--           will be unreliable.
-- [NOTE] No currency conversion needed — this is a coverage check, not a sum.

SELECT
    ROUND(
        COUNT(DISTINCT CASE
            WHEN TRY_CAST({{ARR_FIELD}} AS DOUBLE) IS NOT NULL
                AND TRY_CAST({{ARR_FIELD}} AS DOUBLE) > 0
            THEN {{OPPORTUNITY_ID}}
        END) * 100.0
        / NULLIF(COUNT(DISTINCT {{OPPORTUNITY_ID}}), 0),
        1
    )                                                 AS arr_populated_rate

FROM {{RENEWAL_TABLE}}
WHERE {{IS_RENEWAL}}
    AND {{IS_CLOSED}}
    AND CAST({{CLOSE_DATE}} AS DATE)
        >= DATE_ADD('month', -12, DATE_TRUNC('month', CURRENT_DATE))
    {{EXCLUDE_CONDITIONS}}
;


-- ============================================================================
-- QUERY 4: RENEWALS & CHURNS BY MONTH (Prior 12 Months)
-- Dashboard fields: Chart data for renewals/churns count + ARR
-- ============================================================================
-- [PURPOSE] Monthly breakdown of renewal outcomes for the EDA section.
--           Feeds both the count chart and the ARR chart.
-- [NOTE] ARR amounts converted to USD via CurrencyType conversion rates.

WITH fx_rates AS (
    SELECT IsoCode, ConversionRate
    FROM CurrencyType
    WHERE IsActive = TRUE
)

SELECT
    DATE_TRUNC('month', CAST(o.{{CLOSE_DATE}} AS DATE)) AS month,

    -- Counts
    COUNT(DISTINCT CASE
        WHEN o.{{IS_RENEWAL_WON}}
        THEN o.{{OPPORTUNITY_ID}}
    END)                                              AS renewals_count,

    COUNT(DISTINCT CASE
        WHEN o.{{IS_CHURN}}
        THEN o.{{OPPORTUNITY_ID}}
    END)                                              AS churns_count,

    -- ARR (USD)
    COALESCE(SUM(CASE
        WHEN o.{{IS_RENEWAL_WON}}
        THEN TRY_CAST(o.{{ARR_FIELD}} AS DOUBLE) / fx.ConversionRate
    END), 0)                                          AS renewals_arr,

    COALESCE(SUM(CASE
        WHEN o.{{IS_CHURN}}
        THEN TRY_CAST(o.{{ARR_FIELD}} AS DOUBLE) / fx.ConversionRate
    END), 0)                                          AS churns_arr

FROM {{RENEWAL_TABLE}} AS o
LEFT JOIN fx_rates AS fx
    ON o.{{CURRENCY_ISO_CODE}} = fx.IsoCode
WHERE o.{{IS_RENEWAL}}
    AND o.{{IS_CLOSED}}
    AND CAST(o.{{CLOSE_DATE}} AS DATE)
        >= DATE_ADD('month', -12, DATE_TRUNC('month', CURRENT_DATE))
    {{EXCLUDE_CONDITIONS}}
GROUP BY 1
ORDER BY 1
;


-- ============================================================================
-- QUERY 5: CHURN RATE BY MONTH
-- Dashboard fields: Chart data for churn rate trend line
-- ============================================================================
-- [PURPOSE] Monthly logo churn rate = churns / (churns + renewals).
--           Computes the rate in a CTE to keep the logic clean.

WITH monthly AS (
    -- [PURPOSE] Aggregate renewal outcomes by month
    SELECT
        DATE_TRUNC('month', CAST({{CLOSE_DATE}} AS DATE))
                                                      AS month,
        COUNT(DISTINCT CASE
            WHEN {{IS_RENEWAL_WON}}
            THEN {{OPPORTUNITY_ID}}
        END)                                          AS renewals,

        COUNT(DISTINCT CASE
            WHEN {{IS_CHURN}}
            THEN {{OPPORTUNITY_ID}}
        END)                                          AS churns

    FROM {{RENEWAL_TABLE}}
    WHERE {{IS_RENEWAL}}
        AND {{IS_CLOSED}}
        AND CAST({{CLOSE_DATE}} AS DATE)
            >= DATE_ADD('month', -12, DATE_TRUNC('month', CURRENT_DATE))
        {{EXCLUDE_CONDITIONS}}
    GROUP BY 1
)

SELECT
    month,
    renewals,
    churns,
    -- [NOTE] Protected against division by zero with NULLIF
    ROUND(
        churns * 100.0 / NULLIF(churns + renewals, 0),
        1
    )                                                 AS churn_rate_pct

FROM monthly
ORDER BY month
;


-- ============================================================================
-- QUERY 6: PRIOR YEAR SUMMARY METRICS
-- Dashboard fields: PRIOR_YEAR_RENEWALS_COUNT, PRIOR_YEAR_CHURNS_COUNT,
--                   AVG_ARR, PRIOR_YEAR_CHURN_RATE
-- ============================================================================
-- [PURPOSE] Aggregate stats across the full prior-year window.
--           These populate KPI cards and feed the ROI calculation.
-- [NOTE] ARR amounts converted to USD via CurrencyType conversion rates.

WITH fx_rates AS (
    SELECT IsoCode, ConversionRate
    FROM CurrencyType
    WHERE IsActive = TRUE
)

SELECT
    COUNT(DISTINCT CASE
        WHEN o.{{IS_RENEWAL_WON}}
        THEN o.{{OPPORTUNITY_ID}}
    END)                                              AS prior_year_renewals_count,

    COUNT(DISTINCT CASE
        WHEN o.{{IS_CHURN}}
        THEN o.{{OPPORTUNITY_ID}}
    END)                                              AS prior_year_churns_count,

    -- [NOTE] AVG across all closed renewals (won + lost) for representative ARR in USD
    ROUND(
        AVG(TRY_CAST(o.{{ARR_FIELD}} AS DOUBLE) / fx.ConversionRate),
        0
    )                                                 AS avg_arr,

    -- [NOTE] Annual churn rate = churns / total closed renewals
    ROUND(
        COUNT(DISTINCT CASE
            WHEN o.{{IS_CHURN}}
            THEN o.{{OPPORTUNITY_ID}}
        END) * 100.0
        / NULLIF(COUNT(DISTINCT o.{{OPPORTUNITY_ID}}), 0),
        1
    )                                                 AS prior_year_churn_rate

FROM {{RENEWAL_TABLE}} AS o
LEFT JOIN fx_rates AS fx
    ON o.{{CURRENCY_ISO_CODE}} = fx.IsoCode
WHERE o.{{IS_RENEWAL}}
    AND o.{{IS_CLOSED}}
    AND CAST(o.{{CLOSE_DATE}} AS DATE)
        >= DATE_ADD('month', -12, DATE_TRUNC('month', CURRENT_DATE))
    {{EXCLUDE_CONDITIONS}}
;


-- ============================================================================
-- QUERY 7: UPCOMING RENEWALS (Next 12 Months)
-- Dashboard fields: Chart data for upcoming renewals + UPCOMING_RENEWALS_DOLLAR
-- ============================================================================
-- [PURPOSE] Pipeline of open renewals by month — the denominator for the
--           "what's at stake" calculation.
-- [NOTE] ARR amounts converted to USD via CurrencyType conversion rates.

WITH fx_rates AS (
    SELECT IsoCode, ConversionRate
    FROM CurrencyType
    WHERE IsActive = TRUE
)

SELECT
    DATE_TRUNC('month', CAST(o.{{RENEWAL_DATE}} AS DATE))
                                                      AS month,
    COUNT(DISTINCT o.{{OPPORTUNITY_ID}})              AS upcoming_count,
    COALESCE(
        SUM(TRY_CAST(o.{{ARR_FIELD}} AS DOUBLE) / fx.ConversionRate),
        0
    )                                                 AS upcoming_arr

FROM {{RENEWAL_TABLE}} AS o
LEFT JOIN fx_rates AS fx
    ON o.{{CURRENCY_ISO_CODE}} = fx.IsoCode
WHERE o.{{IS_RENEWAL}}
    AND o.{{IS_OPEN_RENEWAL}}
    AND CAST(o.{{RENEWAL_DATE}} AS DATE) >= DATE_TRUNC('month', CURRENT_DATE)
    AND CAST(o.{{RENEWAL_DATE}} AS DATE)
        < DATE_ADD('month', 12, DATE_TRUNC('month', CURRENT_DATE))
    {{EXCLUDE_CONDITIONS}}
GROUP BY 1
ORDER BY 1
;


-- ============================================================================
-- QUERY 8: BUSINESS CASE — Estimated Churn & ROI Calculations
-- Dashboard fields: ESTIMATED_CHURN_DOLLAR, ESTIMATED_CHURN_ACCOUNTS,
--                   ROI_CONSERVATIVE_*, ROI_BENCHMARK_*
-- ============================================================================
-- [PURPOSE] Combine prior-year churn rate with upcoming renewal pipeline to
--           project churn and compute Predict's value at 1pp and 2pp
--           reduction scenarios.
-- [NOTE] This query depends on the same base data as Queries 6 and 7.
--        Combined here into a single CTE chain for convenience.
-- [NOTE] All ARR amounts converted to USD via CurrencyType conversion rates.

WITH fx_rates AS (
    SELECT IsoCode, ConversionRate
    FROM CurrencyType
    WHERE IsActive = TRUE
),

prior_year AS (
    -- [PURPOSE] Compute churn rate and average ARR (USD) from closed renewals
    SELECT
        COUNT(DISTINCT CASE
            WHEN o.{{IS_CHURN}}
            THEN o.{{OPPORTUNITY_ID}}
        END) * 1.0
        / NULLIF(COUNT(DISTINCT o.{{OPPORTUNITY_ID}}), 0)
                                                      AS churn_rate,

        ROUND(
            AVG(TRY_CAST(o.{{ARR_FIELD}} AS DOUBLE) / fx.ConversionRate),
            0
        )                                             AS avg_arr

    FROM {{RENEWAL_TABLE}} AS o
    LEFT JOIN fx_rates AS fx
        ON o.{{CURRENCY_ISO_CODE}} = fx.IsoCode
    WHERE o.{{IS_RENEWAL}}
        AND o.{{IS_CLOSED}}
        AND CAST(o.{{CLOSE_DATE}} AS DATE)
            >= DATE_ADD('month', -12, DATE_TRUNC('month', CURRENT_DATE))
        {{EXCLUDE_CONDITIONS}}
),

upcoming AS (
    -- [PURPOSE] Count and sum upcoming open renewals (USD)
    SELECT
        COUNT(DISTINCT o.{{OPPORTUNITY_ID}})          AS upcoming_count,
        COALESCE(
            SUM(TRY_CAST(o.{{ARR_FIELD}} AS DOUBLE) / fx.ConversionRate),
            0
        )                                             AS upcoming_dollar

    FROM {{RENEWAL_TABLE}} AS o
    LEFT JOIN fx_rates AS fx
        ON o.{{CURRENCY_ISO_CODE}} = fx.IsoCode
    WHERE o.{{IS_RENEWAL}}
        AND o.{{IS_OPEN_RENEWAL}}
        AND CAST(o.{{RENEWAL_DATE}} AS DATE) >= DATE_TRUNC('month', CURRENT_DATE)
        AND CAST(o.{{RENEWAL_DATE}} AS DATE)
            < DATE_ADD('month', 12, DATE_TRUNC('month', CURRENT_DATE))
        {{EXCLUDE_CONDITIONS}}
)

SELECT
    -- Churn projection
    ROUND(u.upcoming_count * p.churn_rate)            AS estimated_churn_accounts,
    ROUND(u.upcoming_dollar * p.churn_rate)           AS estimated_churn_dollar,

    -- Conservative case: 1 percentage point reduction
    ROUND(u.upcoming_count * 0.01)                    AS roi_conservative_renewals_saved,
    ROUND(u.upcoming_count * 0.01 * p.avg_arr)       AS roi_conservative_annual,
    ROUND(u.upcoming_count * 0.01 * p.avg_arr / 12)  AS roi_conservative_monthly,

    -- Benchmark case: 2 percentage point reduction
    ROUND(u.upcoming_count * 0.02)                    AS roi_benchmark_renewals_saved,
    ROUND(u.upcoming_count * 0.02 * p.avg_arr)       AS roi_benchmark_annual,
    ROUND(u.upcoming_count * 0.02 * p.avg_arr / 12)  AS roi_benchmark_monthly

FROM prior_year AS p
CROSS JOIN upcoming AS u
;


-- ============================================================================
-- QUERY 9: PENDO — Account Match Rate
-- Dashboard fields: PENDO_SFDC_MATCH_RATE, PENDO_SUBSCRIPTIONS
-- ============================================================================
-- [PURPOSE] Measure how well Pendo subscriptions map to SFDC accounts
SELECT
    COUNT(DISTINCT ps.id)     AS pendo_subscriptions,

    ROUND(
        COUNT(DISTINCT CASE
            WHEN ps.salesforce__account__c IS NOT NULL
            THEN ps.id
        END) * 100.0
        / NULLIF(
            COUNT(DISTINCT ps.id),
            0
          ),
        1
    )                                                 AS pendo_sfdc_match_rate

FROM pendo.AccountMetadata AS ps
;


-- ============================================================================
-- QUERY 10: PENDO — Active Accounts & Event Volume by Month
-- Dashboard fields: Charts for Pendo accounts + event types,
--                   PENDO_ACTIVE_ACCOUNTS, PENDO_PAGE_VIEWS,
--                   PENDO_TRACK_EVENTS, PENDO_FEATURE_EVENTS,
--                   PENDO_TOTAL_EVENTS
-- [PURPOSE] Monthly breakdown of Pendo usage to show product data depth
SELECT
    DATE_TRUNC('month', CAST(Date AS DATE))
                                                      AS month,
    COUNT(DISTINCT AccountId)        AS active_accounts,
    SUM(NumEvents) as total_events,
    sum(NumMinutes) as total_minutes,
    count(distinct VisitorId) as total_visitors
FROM pendo.AllEvents
WHERE CAST(date AS DATE)
    >= DATE_ADD('month', -12, DATE_TRUNC('month', CURRENT_DATE))
GROUP BY 1
ORDER BY 1
;


-- ============================================================================
-- VALIDATION
-- ============================================================================
-- Sanity checks to run after populating the dashboard:
--
-- 1. Total renewals + churns ~ closed_renewals_prior_year
--    (Query 2 vs Query 6)
--
-- 2. SUM of monthly renewals_count (Query 4)
--    ~ prior_year_renewals_count (Query 6)
--
-- 3. SUM of monthly churns_count (Query 4)
--    ~ prior_year_churns_count (Query 6)
--
-- 4. Churn rate from Query 5 monthly avg
--    ~ prior_year_churn_rate from Query 6
--
-- 5. upcoming_renewals_dollar = SUM of upcoming_arr from Query 7
--
-- 6. estimated_churn_dollar ~ upcoming_dollar * churn_rate
--    (sanity check Query 8)
--
-- 7. pendo_subscriptions > 0 and match_rate > 0
--    (Query 9 — if 0, the ID mapping is broken)
--
-- Known edge cases:
-- - Athena treats NULL != NULL in JOINs — ensure join keys are NOT NULL
--   or handle with COALESCE
-- - TRY_CAST returns NULL for unparseable values — check for data quality
--   issues if ARR counts seem low
-- - Customers with mid-year SFDC migrations may have a gap in history
-- - Multi-year contracts may appear as a single large renewal, skewing avg_arr
-- - Some customers track downsells separately from churns — confirm with CE
-- - Presto DATE_ADD month arithmetic can shift end-of-month dates — e.g.,
--   DATE_ADD('month', -1, DATE '2026-03-31') = '2026-02-28'
--
-- Assumptions:
-- - ARR field represents annualized revenue (not total contract value)
-- - Churn = complete loss of the account (not partial downsell)
-- - One Opportunity per renewal event per account (no duplicates)
-- - All date fields are castable to DATE without timezone issues
