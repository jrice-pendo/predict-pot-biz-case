-- ============================================================================
-- DIAGNOSTIC: Upcoming $ Available to Renew — Troubleshooting
-- ============================================================================
-- Customer: Pendo
-- Issue: Upcoming ARR total seems inflated
-- Hypothesis: Double counting, currency issues, or non-annualized values
--
-- All $ amounts converted to USD using SFDC CurrencyType table.
-- ARR field: Amount (on Opportunity)
--
-- Run these queries in order. Each one isolates a potential root cause.
-- ============================================================================


-- ============================================================================
-- DIAG 1: Baseline — What does the current Q7 return?
-- ============================================================================
-- [PURPOSE] Reproduce the exact Q7 result to confirm the number we're debugging

WITH fx_rates AS (
    SELECT IsoCode, ConversionRate
    FROM CurrencyType
    WHERE IsActive = TRUE
)
SELECT
    DATE_TRUNC('month', CAST(CloseDate AS DATE))      AS month,
    COUNT(DISTINCT o.Id)                               AS upcoming_count,
    COALESCE(SUM(TRY_CAST(o.Amount AS DOUBLE) / fx.ConversionRate), 0) AS upcoming_arr_usd
FROM Opportunity AS o
LEFT JOIN fx_rates AS fx ON o.CurrencyIsoCode = fx.IsoCode
WHERE o.Type = 'Renewals'
    AND o.IsClosed = FALSE
    AND CAST(o.CloseDate AS DATE) >= DATE_TRUNC('month', CURRENT_DATE)
    AND CAST(o.CloseDate AS DATE) < DATE_ADD('month', 12, DATE_TRUNC('month', CURRENT_DATE))
    AND o.Amount > 0
GROUP BY 1
ORDER BY 1
;


-- ============================================================================
-- DIAG 2: Check for duplicate Opportunities per Account
-- ============================================================================
-- [PURPOSE] If an account has multiple open renewal Opportunities, the ARR
--           gets summed for each one. This is the #1 cause of inflated totals.

WITH fx_rates AS (
    SELECT IsoCode, ConversionRate
    FROM CurrencyType
    WHERE IsActive = TRUE
)
SELECT
    o.AccountId,
    Account.Name                                       AS account_name,
    COUNT(DISTINCT o.Id)                               AS open_renewal_count,
    SUM(TRY_CAST(o.Amount AS DOUBLE) / fx.ConversionRate) AS total_arr_usd
FROM Opportunity AS o
LEFT JOIN fx_rates AS fx ON o.CurrencyIsoCode = fx.IsoCode
WHERE o.Type = 'Renewals'
    AND o.IsClosed = FALSE
    AND CAST(o.CloseDate AS DATE) >= DATE_TRUNC('month', CURRENT_DATE)
    AND CAST(o.CloseDate AS DATE) < DATE_ADD('month', 12, DATE_TRUNC('month', CURRENT_DATE))
    AND o.Amount > 0
GROUP BY 1, 2
HAVING COUNT(DISTINCT o.Id) > 1
ORDER BY open_renewal_count DESC
LIMIT 25
;


-- ============================================================================
-- DIAG 3: Check for abnormally large individual values
-- ============================================================================
-- [PURPOSE] Surface the top 20 opportunities by Amount to spot outliers —
--           e.g., total contract value instead of annual, or a single
--           massive deal skewing the total.

WITH fx_rates AS (
    SELECT IsoCode, ConversionRate
    FROM CurrencyType
    WHERE IsActive = TRUE
)
SELECT
    o.Id                                               AS opportunity_id,
    Account.Name                                       AS account_name,
    o.StageName,
    o.Amount,
    o.CurrencyIsoCode,
    ROUND(TRY_CAST(o.Amount AS DOUBLE) / fx.ConversionRate, 2) AS amount_usd,
    o.CloseDate
FROM Opportunity AS o
LEFT JOIN fx_rates AS fx ON o.CurrencyIsoCode = fx.IsoCode
WHERE o.Type = 'Renewals'
    AND o.IsClosed = FALSE
    AND CAST(o.CloseDate AS DATE) >= DATE_TRUNC('month', CURRENT_DATE)
    AND CAST(o.CloseDate AS DATE) < DATE_ADD('month', 12, DATE_TRUNC('month', CURRENT_DATE))
    AND o.Amount > 0
ORDER BY TRY_CAST(o.Amount AS DOUBLE) / fx.ConversionRate DESC
LIMIT 20
;


-- ============================================================================
-- DIAG 4: Currency check — are there multiple CurrencyIsoCode values?
-- ============================================================================
-- [PURPOSE] If the org is multi-currency, Amount might be in local currency
--           and summing USD + EUR + GBP without conversion inflates totals.

WITH fx_rates AS (
    SELECT IsoCode, ConversionRate
    FROM CurrencyType
    WHERE IsActive = TRUE
)
SELECT
    o.CurrencyIsoCode,
    fx.ConversionRate,
    COUNT(DISTINCT o.Id)                               AS opp_count,
    SUM(TRY_CAST(o.Amount AS DOUBLE))                  AS total_local_amount,
    SUM(TRY_CAST(o.Amount AS DOUBLE) / fx.ConversionRate) AS total_usd,
    AVG(TRY_CAST(o.Amount AS DOUBLE) / fx.ConversionRate) AS avg_usd
FROM Opportunity AS o
LEFT JOIN fx_rates AS fx ON o.CurrencyIsoCode = fx.IsoCode
WHERE o.Type = 'Renewals'
    AND o.IsClosed = FALSE
    AND CAST(o.CloseDate AS DATE) >= DATE_TRUNC('month', CURRENT_DATE)
    AND CAST(o.CloseDate AS DATE) < DATE_ADD('month', 12, DATE_TRUNC('month', CURRENT_DATE))
    AND o.Amount > 0
GROUP BY 1, 2
ORDER BY total_usd DESC
;


-- ============================================================================
-- DIAG 5: Aggregate Amount totals — local vs USD
-- ============================================================================
-- [PURPOSE] Compare the raw local-currency sum against the USD-converted sum.
--           A large gap means currency conversion is a significant factor.

WITH fx_rates AS (
    SELECT IsoCode, ConversionRate
    FROM CurrencyType
    WHERE IsActive = TRUE
)
SELECT
    'Totals' AS label,
    COUNT(DISTINCT o.Id)                               AS opp_count,
    SUM(TRY_CAST(o.Amount AS DOUBLE))                  AS sum_local_amount,
    SUM(TRY_CAST(o.Amount AS DOUBLE) / fx.ConversionRate) AS sum_usd,
    ROUND(
        SUM(TRY_CAST(o.Amount AS DOUBLE))
        / NULLIF(SUM(TRY_CAST(o.Amount AS DOUBLE) / fx.ConversionRate), 0),
        2
    )                                                  AS local_to_usd_ratio,
    AVG(TRY_CAST(o.Amount AS DOUBLE) / fx.ConversionRate) AS avg_usd
FROM Opportunity AS o
LEFT JOIN fx_rates AS fx ON o.CurrencyIsoCode = fx.IsoCode
WHERE o.Type = 'Renewals'
    AND o.IsClosed = FALSE
    AND CAST(o.CloseDate AS DATE) >= DATE_TRUNC('month', CURRENT_DATE)
    AND CAST(o.CloseDate AS DATE) < DATE_ADD('month', 12, DATE_TRUNC('month', CURRENT_DATE))
    AND o.Amount > 0
;


-- ============================================================================
-- DIAG 6: Distribution of Amount values (USD)
-- ============================================================================
-- [PURPOSE] Bucketed histogram to see if there's a bimodal distribution
--           (e.g., some records annualized, others not).

WITH fx_rates AS (
    SELECT IsoCode, ConversionRate
    FROM CurrencyType
    WHERE IsActive = TRUE
),
converted AS (
    SELECT
        o.Id,
        TRY_CAST(o.Amount AS DOUBLE) / fx.ConversionRate AS amount_usd
    FROM Opportunity AS o
    LEFT JOIN fx_rates AS fx ON o.CurrencyIsoCode = fx.IsoCode
    WHERE o.Type = 'Renewals'
        AND o.IsClosed = FALSE
        AND CAST(o.CloseDate AS DATE) >= DATE_TRUNC('month', CURRENT_DATE)
        AND CAST(o.CloseDate AS DATE) < DATE_ADD('month', 12, DATE_TRUNC('month', CURRENT_DATE))
        AND o.Amount > 0
)
SELECT
    CASE
        WHEN amount_usd < 1000 THEN '< $1K'
        WHEN amount_usd < 10000 THEN '$1K - $10K'
        WHEN amount_usd < 50000 THEN '$10K - $50K'
        WHEN amount_usd < 100000 THEN '$50K - $100K'
        WHEN amount_usd < 500000 THEN '$100K - $500K'
        WHEN amount_usd < 1000000 THEN '$500K - $1M'
        ELSE '$1M+'
    END                                                AS arr_bucket,
    COUNT(DISTINCT Id)                                 AS opp_count,
    SUM(amount_usd)                                    AS bucket_total_usd,
    ROUND(
        SUM(amount_usd) * 100.0
        / NULLIF((SELECT SUM(amount_usd) FROM converted), 0),
        1
    )                                                  AS pct_of_total
FROM converted
GROUP BY 1
ORDER BY MIN(amount_usd)
;


-- ============================================================================
-- DIAG 7: Same account appearing in multiple months?
-- ============================================================================
-- [PURPOSE] If an account has renewals in multiple months within the 12-month
--           window, that's legitimate (e.g., multiple products). But if it's
--           the same product renewing, it could mean duplicates.

WITH fx_rates AS (
    SELECT IsoCode, ConversionRate
    FROM CurrencyType
    WHERE IsActive = TRUE
)
SELECT
    o.AccountId,
    Account.Name                                       AS account_name,
    COUNT(DISTINCT DATE_TRUNC('month', CAST(o.CloseDate AS DATE))) AS months_with_renewals,
    COUNT(DISTINCT o.Id)                               AS total_opps,
    SUM(TRY_CAST(o.Amount AS DOUBLE) / fx.ConversionRate) AS total_arr_usd
FROM Opportunity AS o
LEFT JOIN fx_rates AS fx ON o.CurrencyIsoCode = fx.IsoCode
WHERE o.Type = 'Renewals'
    AND o.IsClosed = FALSE
    AND CAST(o.CloseDate AS DATE) >= DATE_TRUNC('month', CURRENT_DATE)
    AND CAST(o.CloseDate AS DATE) < DATE_ADD('month', 12, DATE_TRUNC('month', CURRENT_DATE))
    AND o.Amount > 0
GROUP BY 1, 2
HAVING COUNT(DISTINCT DATE_TRUNC('month', CAST(o.CloseDate AS DATE))) > 1
ORDER BY total_arr_usd DESC
LIMIT 25
;
