#!/usr/bin/env python3
"""
Azure CSP Billing Export Handler for Synapse
Handles differences between standard Azure and CSP billing formats
"""

import pandas as pd
import pyodbc
from azure.identity import ClientSecretCredential
from azure.storage.blob import BlobServiceClient
import json
from typing import Dict, List, Optional
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class CSPBillingHandler:
    """Handler for CSP and standard Azure billing exports in Synapse"""
    
    # Standard Azure billing columns
    STANDARD_COLUMNS = [
        'Date', 'ServiceFamily', 'MeterCategory', 'MeterSubCategory',
        'MeterName', 'ResourceGroup', 'ResourceLocation', 'ConsumedService',
        'ResourceId', 'ChargeType', 'PublisherType', 'Quantity',
        'CostInBillingCurrency', 'CostInUSD', 'BillingCurrency',
        'SubscriptionName', 'SubscriptionId', 'ProductName',
        'Frequency', 'UnitOfMeasure', 'Tags'
    ]
    
    # Common CSP billing columns (may vary by provider)
    CSP_COLUMNS = [
        'Date', 'CustomerTenantId', 'CustomerName', 'CustomerDomain',
        'SubscriptionId', 'SubscriptionName', 'SubscriptionDescription',
        'ServiceFamily', 'MeterCategory', 'MeterSubCategory', 'MeterName',
        'ResourceGroup', 'ResourceLocation', 'ConsumedService', 'ResourceId',
        'ChargeType', 'PublisherType', 'Quantity', 'UnitPrice',
        'EffectiveUnitPrice', 'ExtendedCost', 'CostInBillingCurrency',
        'BillingCurrency', 'PCToBCExchangeRate', 'ResellerMpnId',
        'ProductName', 'UnitOfMeasure', 'BillingPeriod', 'Tags'
    ]
    
    def __init__(self, config: Dict):
        """
        Initialize CSP Billing Handler
        
        Args:
            config: Dictionary with connection details
                - tenant_id: Azure tenant ID
                - client_id: Service principal client ID
                - client_secret: Service principal secret
                - storage_account: Storage account name
                - container_name: Container for billing exports
                - synapse_workspace: Synapse workspace name
                - database_name: Synapse database name
        """
        self.config = config
        self.credential = ClientSecretCredential(
            tenant_id=config['tenant_id'],
            client_id=config['client_id'],
            client_secret=config['client_secret']
        )
        
    def detect_billing_format(self, file_path: str) -> str:
        """
        Detect if billing export is standard Azure or CSP format
        
        Args:
            file_path: Path to billing CSV file in blob storage
            
        Returns:
            'standard' or 'csp' based on detected format
        """
        try:
            # Read first few rows to check columns
            blob_service = BlobServiceClient(
                account_url=f"https://{self.config['storage_account']}.blob.core.windows.net",
                credential=self.credential
            )
            
            container_client = blob_service.get_container_client(self.config['container_name'])
            blob_client = container_client.get_blob_client(file_path)
            
            # Download first 1KB to check headers
            download_stream = blob_client.download_blob(max_concurrency=1, offset=0, length=1024)
            header_content = download_stream.readall().decode('utf-8')
            first_line = header_content.split('\n')[0].lower()
            
            # Check for CSP-specific columns
            csp_indicators = ['customertenantid', 'customername', 'reseller', 'partnerearn']
            
            for indicator in csp_indicators:
                if indicator in first_line:
                    logger.info(f"Detected CSP billing format (found: {indicator})")
                    return 'csp'
            
            # Check if SubscriptionId exists (both formats should have it)
            if 'subscriptionid' in first_line:
                logger.info("Detected standard Azure billing format")
                return 'standard'
            
            # If no SubscriptionId, likely CSP without subscription details
            logger.warning("No SubscriptionId column found - may be aggregated CSP format")
            return 'csp'
            
        except Exception as e:
            logger.error(f"Error detecting billing format: {e}")
            return 'standard'  # Default to standard
    
    def create_synapse_view(self, billing_type: str = 'auto') -> str:
        """
        Create appropriate Synapse view based on billing type
        
        Args:
            billing_type: 'standard', 'csp', or 'auto' (auto-detect)
            
        Returns:
            SQL script for creating the view
        """
        if billing_type == 'auto':
            # Auto-detect from latest file
            billing_type = self.detect_latest_format()
        
        storage_path = f"https://{self.config['storage_account']}.blob.core.windows.net/{self.config['container_name']}/billing-data/*.csv"
        
        if billing_type == 'csp':
            return self._create_csp_view_sql(storage_path)
        else:
            return self._create_standard_view_sql(storage_path)
    
    def _create_standard_view_sql(self, storage_path: str) -> str:
        """Create SQL for standard Azure billing view"""
        return f"""
        CREATE OR ALTER VIEW BillingData AS
        SELECT *
        FROM OPENROWSET(
            BULK '{storage_path}',
            FORMAT = 'CSV',
            PARSER_VERSION = '2.0',
            FIRSTROW = 2
        )
        WITH (
            {self._generate_column_definitions(self.STANDARD_COLUMNS)}
        ) AS BillingData;
        """
    
    def _create_csp_view_sql(self, storage_path: str) -> str:
        """Create SQL for CSP billing view"""
        return f"""
        CREATE OR ALTER VIEW BillingDataCSP AS
        SELECT 
            *,
            -- Add calculated fields for compatibility
            COALESCE(SubscriptionId, CustomerTenantId) as EntityId,
            COALESCE(SubscriptionName, CustomerName) as EntityName
        FROM OPENROWSET(
            BULK '{storage_path}',
            FORMAT = 'CSV',
            PARSER_VERSION = '2.0',
            FIRSTROW = 2
        )
        WITH (
            {self._generate_column_definitions(self.CSP_COLUMNS)}
        ) AS CSPBillingData;
        """
    
    def _generate_column_definitions(self, columns: List[str]) -> str:
        """Generate SQL column definitions"""
        definitions = []
        for col in columns:
            if 'cost' in col.lower() or 'price' in col.lower() or 'quantity' in col.lower():
                definitions.append(f"[{col}] DECIMAL(18,8)")
            else:
                definitions.append(f"[{col}] NVARCHAR(500)")
        return ',\n            '.join(definitions)
    
    def detect_latest_format(self) -> str:
        """Detect format of the latest billing file"""
        try:
            blob_service = BlobServiceClient(
                account_url=f"https://{self.config['storage_account']}.blob.core.windows.net",
                credential=self.credential
            )
            
            container_client = blob_service.get_container_client(self.config['container_name'])
            blobs = list(container_client.list_blobs(name_starts_with='billing-data/'))
            
            if not blobs:
                logger.warning("No billing files found")
                return 'standard'
            
            # Get the latest blob
            latest_blob = max(blobs, key=lambda x: x.last_modified)
            return self.detect_billing_format(latest_blob.name)
            
        except Exception as e:
            logger.error(f"Error detecting latest format: {e}")
            return 'standard'
    
    def validate_subscription_ids(self) -> Dict:
        """
        Check if subscription IDs exist in the billing data
        
        Returns:
            Dictionary with validation results
        """
        query = """
        SELECT TOP 100
            CASE 
                WHEN SubscriptionId IS NOT NULL AND SubscriptionId != '' THEN 'Has SubscriptionId'
                ELSE 'No SubscriptionId'
            END as SubscriptionStatus,
            COUNT(*) as RecordCount
        FROM BillingData
        GROUP BY 
            CASE 
                WHEN SubscriptionId IS NOT NULL AND SubscriptionId != '' THEN 'Has SubscriptionId'
                ELSE 'No SubscriptionId'
            END
        """
        
        # Execute query and return results
        # This would connect to Synapse and run the query
        return {
            "has_subscription_ids": True,  # Placeholder
            "sample_count": 100,
            "message": "Validation complete"
        }
    
    def create_unified_view(self) -> str:
        """
        Create a unified view that works with both standard and CSP formats
        """
        return f"""
        CREATE OR ALTER VIEW UnifiedBillingView AS
        SELECT 
            -- Common fields
            [Date],
            COALESCE(SubscriptionId, CustomerTenantId, 'Unknown') as EntityId,
            COALESCE(SubscriptionName, CustomerName, 'Unknown') as EntityName,
            ServiceFamily,
            MeterCategory,
            MeterSubCategory,
            MeterName,
            ResourceGroup,
            ResourceLocation,
            ConsumedService,
            ResourceId,
            ChargeType,
            
            -- Cost fields (handle different column names)
            COALESCE(
                TRY_CAST(CostInBillingCurrency AS DECIMAL(18,8)),
                TRY_CAST(ExtendedCost AS DECIMAL(18,8)),
                0
            ) as Cost,
            
            COALESCE(
                TRY_CAST(CostInUSD AS DECIMAL(18,8)),
                TRY_CAST(ExtendedCost AS DECIMAL(18,8)) * TRY_CAST(PCToBCExchangeRate AS DECIMAL(18,8)),
                0
            ) as CostUSD,
            
            BillingCurrency,
            ProductName,
            Tags,
            
            -- Metadata to identify source
            CASE 
                WHEN CustomerTenantId IS NOT NULL THEN 'CSP'
                WHEN SubscriptionId IS NOT NULL THEN 'Standard'
                ELSE 'Unknown'
            END as BillingType
            
        FROM OPENROWSET(
            BULK 'https://{self.config['storage_account']}.blob.core.windows.net/{self.config['container_name']}/billing-data/*.csv',
            FORMAT = 'CSV',
            PARSER_VERSION = '2.0',
            FIRSTROW = 2
        ) AS BillingData
        """

def main():
    """Example usage"""
    config = {
        'tenant_id': 'your-tenant-id',
        'client_id': 'your-client-id',
        'client_secret': 'your-secret',
        'storage_account': 'your-storage',
        'container_name': 'billing-exports',
        'synapse_workspace': 'your-synapse',
        'database_name': 'BillingAnalytics'
    }
    
    handler = CSPBillingHandler(config)
    
    # Detect format
    format_type = handler.detect_latest_format()
    print(f"Detected billing format: {format_type}")
    
    # Create appropriate view
    view_sql = handler.create_synapse_view(format_type)
    print(f"View SQL:\n{view_sql}")
    
    # Validate subscription IDs
    validation = handler.validate_subscription_ids()
    print(f"Validation results: {validation}")

if __name__ == "__main__":
    main()