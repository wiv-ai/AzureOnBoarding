-- Azure Synapse Setup for CSP Billing Exports (Single File with Overwrite)
-- This script handles both standard Azure and CSP billing formats

-- Create database if not exists
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics')
BEGIN
    CREATE DATABASE BillingAnalytics
END
GO

USE BillingAnalytics
GO

-- Drop existing views to recreate with updated schema
DROP VIEW IF EXISTS BillingData;
DROP VIEW IF EXISTS BillingDataCSP;
GO

-- ============================================
-- STANDARD AZURE BILLING VIEW (EA/Pay-As-You-Go)
-- For manual exports with overwrite (single file)
-- ============================================
CREATE VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK 'https://<storage_account>.blob.core.windows.net/<container>/billing-data/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2  -- Skip header row
)
WITH (
    -- Standard Azure billing columns
    [Date] NVARCHAR(100),
    ServiceFamily NVARCHAR(200),
    MeterCategory NVARCHAR(200),
    MeterSubCategory NVARCHAR(200),
    MeterName NVARCHAR(500),
    ResourceGroup NVARCHAR(200),
    ResourceLocation NVARCHAR(100),
    ConsumedService NVARCHAR(200),
    ResourceId NVARCHAR(1000),
    ChargeType NVARCHAR(100),
    PublisherType NVARCHAR(100),
    Quantity NVARCHAR(100),
    CostInBillingCurrency NVARCHAR(100),
    CostInUSD NVARCHAR(100),
    BillingCurrency NVARCHAR(10),
    SubscriptionName NVARCHAR(200),
    SubscriptionId NVARCHAR(100),  -- This exists in standard billing
    ProductName NVARCHAR(500),
    Frequency NVARCHAR(100),
    UnitOfMeasure NVARCHAR(100),
    Tags NVARCHAR(4000)
) AS BillingData;
GO

-- ============================================
-- CSP BILLING VIEW
-- For CSP-specific billing exports
-- ============================================
CREATE VIEW BillingDataCSP AS
SELECT *
FROM OPENROWSET(
    BULK 'https://<storage_account>.blob.core.windows.net/<container>/csp-billing-data/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2  -- Skip header row
)
WITH (
    -- CSP-specific columns (adjust based on your CSP provider's format)
    [Date] NVARCHAR(100),
    CustomerTenantId NVARCHAR(100),    -- CSP-specific
    CustomerName NVARCHAR(200),         -- CSP-specific
    CustomerDomain NVARCHAR(200),       -- CSP-specific
    SubscriptionId NVARCHAR(100),       -- Usually still present in CSP
    SubscriptionName NVARCHAR(200),
    SubscriptionDescription NVARCHAR(500),
    ServiceFamily NVARCHAR(200),
    MeterCategory NVARCHAR(200),
    MeterSubCategory NVARCHAR(200),
    MeterName NVARCHAR(500),
    ResourceGroup NVARCHAR(200),
    ResourceLocation NVARCHAR(100),
    ConsumedService NVARCHAR(200),
    ResourceId NVARCHAR(1000),
    ChargeType NVARCHAR(100),
    PublisherType NVARCHAR(100),
    Quantity DECIMAL(18,8),
    UnitPrice DECIMAL(18,8),           -- CSP might have unit pricing
    EffectiveUnitPrice DECIMAL(18,8),  -- CSP partner pricing
    ExtendedCost DECIMAL(18,8),        -- CSP extended cost
    CostInBillingCurrency DECIMAL(18,8),
    BillingCurrency NVARCHAR(10),
    PCToBCExchangeRate DECIMAL(18,8),  -- CSP exchange rates
    ResellerMpnId NVARCHAR(100),       -- CSP reseller info
    ProductName NVARCHAR(500),
    UnitOfMeasure NVARCHAR(100),
    BillingPeriod NVARCHAR(20),        -- CSP billing period
    Tags NVARCHAR(4000)
) AS CSPBillingData;
GO

-- ============================================
-- UNIFIED VIEW - Combines both formats
-- Normalizes differences between standard and CSP
-- ============================================
CREATE VIEW UnifiedBillingData AS
-- Standard Azure billing data
SELECT 
    [Date],
    NULL as CustomerTenantId,
    SubscriptionName as CustomerName,  -- Use subscription as customer proxy
    SubscriptionId,
    SubscriptionName,
    ServiceFamily,
    MeterCategory,
    MeterSubCategory,
    MeterName,
    ResourceGroup,
    ResourceLocation,
    ConsumedService,
    ResourceId,
    ChargeType,
    PublisherType,
    TRY_CAST(Quantity AS DECIMAL(18,8)) as Quantity,
    TRY_CAST(CostInBillingCurrency AS DECIMAL(18,8)) as CostInBillingCurrency,
    TRY_CAST(CostInUSD AS DECIMAL(18,8)) as CostInUSD,
    BillingCurrency,
    ProductName,
    UnitOfMeasure,
    Tags,
    'Standard' as BillingType
FROM BillingData
WHERE [Date] IS NOT NULL

UNION ALL

-- CSP billing data
SELECT 
    [Date],
    CustomerTenantId,
    CustomerName,
    SubscriptionId,
    SubscriptionName,
    ServiceFamily,
    MeterCategory,
    MeterSubCategory,
    MeterName,
    ResourceGroup,
    ResourceLocation,
    ConsumedService,
    ResourceId,
    ChargeType,
    PublisherType,
    Quantity,
    ExtendedCost as CostInBillingCurrency,
    ExtendedCost * PCToBCExchangeRate as CostInUSD,  -- Calculate USD if needed
    BillingCurrency,
    ProductName,
    UnitOfMeasure,
    Tags,
    'CSP' as BillingType
FROM BillingDataCSP
WHERE [Date] IS NOT NULL;
GO

-- ============================================
-- HELPER QUERIES
-- ============================================

-- Query to check if you have subscription IDs in your CSP data
-- Run this to verify your CSP export format:
/*
SELECT TOP 10 
    CustomerTenantId,
    CustomerName,
    SubscriptionId,
    SubscriptionName,
    COUNT(*) as RecordCount
FROM BillingDataCSP
GROUP BY CustomerTenantId, CustomerName, SubscriptionId, SubscriptionName
ORDER BY RecordCount DESC;
*/

-- Query to get total costs by customer (CSP) or subscription (Standard)
/*
SELECT 
    COALESCE(CustomerName, SubscriptionName) as Entity,
    BillingType,
    SUM(CostInBillingCurrency) as TotalCost,
    BillingCurrency,
    COUNT(*) as LineItems
FROM UnifiedBillingData
WHERE [Date] >= DATEADD(day, -30, GETDATE())
GROUP BY COALESCE(CustomerName, SubscriptionName), BillingType, BillingCurrency
ORDER BY TotalCost DESC;
*/

-- ============================================
-- NOTES ON CSP BILLING DIFFERENCES
-- ============================================
/*
1. CSP billing typically DOES include SubscriptionId
   - It's needed for resource-level tracking
   - Format might be different (GUID vs friendly name)

2. Additional CSP fields to consider:
   - CustomerTenantId: Azure AD tenant of the customer
   - ResellerMpnId: Microsoft Partner Network ID
   - Unit pricing and markup information
   - Partner earn credits (if applicable)

3. Single file with overwrite benefits:
   - No duplication issues
   - Simpler queries (no need to find latest)
   - Lower storage costs
   - Faster query performance

4. To adapt this script:
   - Replace <storage_account> with your actual storage account name
   - Replace <container> with your container name
   - Adjust column mappings based on your actual CSP export format
   - Test with SELECT TOP 100 * to verify column names
*/