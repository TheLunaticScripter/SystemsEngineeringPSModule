@{
    Nodes = @(
        @{
            NodeName = "VSphere1"
            Role = "VSphere"
            ADSite = "Test-Site1"
        }
        @{
            NodeName = "VSphere2"
            Role = "VSphere"
            ADSite = "Test-Site2"
        }
    )
    Common = @{
        BaselineOSTemplateName = "2012R2 Baseline 2_3_2016"
        BaselineOSCustomization = "2012 R2 Baseline Customization NO NIC"
        DomainName = "test.local"
        DefaultMemory = 4
        DefaultCPU = 1
    }
    Site2 = @{
        SiteCode = "SITE2"
        DefaultDataStore = "DataStore1"
        DefaultNetwork = "TEST NETWORK"
    }
    Site1 = @{
        SiteCode = "SITE1"
        DefaultDataStore = "DataStore_112"
        DefaultNetwork = "TEST NETWORK"
    }
    SQLConfig = @{
        DatabaseDriveLetter = "E"
        DatabaseDriveSizeGB = 40
        DatabaseDriveLabel = "Databases"
        VMMemory = 8
        VMCPUs = 8
        
    }

}