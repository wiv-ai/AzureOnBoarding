-- Run this in Synapse Studio connected to 'master' database first
-- Step 1: Create the database (run in master)
CREATE DATABASE BillingAnalytics;
GO

-- Step 2: Switch to the new database
USE BillingAnalytics;
GO

-- Step 3: Create master key for encryption
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!';
GO

-- Step 4: Create database user for the service principal
CREATE USER [554b11c1-18f9-46b5-a096-30e0a2cfae6f] FROM EXTERNAL PROVIDER;
GO

-- Step 5: Grant necessary permissions
ALTER ROLE db_datareader ADD MEMBER [554b11c1-18f9-46b5-a096-30e0a2cfae6f];
ALTER ROLE db_datawriter ADD MEMBER [554b11c1-18f9-46b5-a096-30e0a2cfae6f];
ALTER ROLE db_ddladmin ADD MEMBER [554b11c1-18f9-46b5-a096-30e0a2cfae6f];
GO

-- Step 6: Verify the setup
SELECT DB_NAME() as CurrentDatabase;
SELECT name, type_desc, authentication_type_desc 
FROM sys.database_principals 
WHERE name = '554b11c1-18f9-46b5-a096-30e0a2cfae6f';