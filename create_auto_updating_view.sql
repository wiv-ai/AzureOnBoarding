-- ======================================================================
-- CREATE AUTO-UPDATING BILLING VIEW
-- This view automatically includes all months' data
-- ======================================================================

-- Drop existing view
DROP VIEW IF EXISTS BillingData;
GO

-- Create view that includes ALL date ranges automatically
CREATE VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK 'https://billingstorage26612.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport;
GO

-- Test the view
SELECT COUNT(*) as TotalRows FROM BillingData;
GO

-- ======================================================================
-- ALTERNATIVE: Create a view that only shows current month
-- ======================================================================
/*
CREATE VIEW CurrentMonthBilling AS
WITH CurrentMonth AS (
    SELECT 
        FORMAT(GETDATE(), 'yyyyMM01') as MonthStart,
        FORMAT(EOMONTH(GETDATE()), 'yyyyMMdd') as MonthEnd
)
SELECT *
FROM OPENROWSET(
    BULK 'https://billingstorage26612.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport
WHERE filepath(1) LIKE CONCAT((SELECT MonthStart FROM CurrentMonth), '%');
GO
*/

-- ======================================================================
-- NOTES:
-- ======================================================================
-- With the wildcard pattern '/*/*.csv':
-- - Automatically includes August 2025: /20250801-20250831/*.csv
-- - Automatically includes September 2025: /20250901-20250930/*.csv
-- - Automatically includes October 2025: /20251001-20251031/*.csv
-- - And so on...
--
-- The view will ALWAYS show the latest data because:
-- 1. OPENROWSET reads directly from blob storage (not cached)
-- 2. partitionData=true in export config means files are overwritten
-- 3. Each query execution reads the current state of the files
-- ======================================================================