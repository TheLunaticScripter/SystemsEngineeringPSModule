# Install SQL Script each server

# Run this script locally to install sql and failover cluster on SQL servers

$SysMod = '\\test\admins\share\System Engineering Module\Testing\SystemEngineering.psm1'

Import-Module $SysMod

Install-StandardSQL -SQLSourceDir '\\sccm\Software$\Sources\SQL2012SP3' `
                    -NetFx3SourceDir '\\sccm\Software$\Sources\sxs' `
                    -SQLSvcAcct "test.local\sqlsvc" `
                    -SQLSvcAcctPassword 'super_secure_password' `
                    -StartingSQLConfigINI '\\sccm\software$\sources\SourceSQLConfig.ini' `
                    -MaxSQLMemoryinKB 6348



Write-Host "Installing Clustering . . . "
Install-WindowsFeature -Name "Failover-Clustering","RSAT-Clustering","RSAT-Clustering-CmdInterface" -IncludeAllSubFeature


$CluserTest = Get-Cluster -Name "SQL12-Cluster" -ErrorAction SilentlyContinue

if($env:COMPUTERNAME -eq "N93-SQL2012-N1"){
    if($CluserTest.Count -eq 0){
        Write-Host "Create Cluster"
        New-Cluster -Name "SQL12-Cluster" -Node $env:COMPUTERNAME -StaticAddress "10.0.3.132" -NoStorage -Force
    }
}
else{
    Write-Host "Adding Node to Cluster . . . "
    Add-ClusterNode $env:COMPUTERNAME -Cluster "SQL12-Cluster" -NoStorage
    $nodeName = $env:USERDNSDOMAIN + "\" + $env:COMPUTERNAME + '$'
}

# Set Host record TTL
if((Get-ClusterResource "Cluster Name" | Get-ClusterParameter | where{$_.Name -eq "HostRecordTTL"}).Value -ne 300){
    "Setting Cluster Host Record TTL . . ."
    Get-ClusterResource "Cluster Name" | Set-ClusterParameter HostRecordTTL 300
}

# Set Publish PTR Record to 1
if((Get-ClusterResource "Cluster Name" | Get-ClusterParameter | where{$_.Name -eq "PublishPTRRecords"}).Value -ne 1){
    "Setting Cluster Publish PTR Records . . . "
    Get-ClusterResource "Cluster Name" | Set-ClusterParameter PublishPTRRecords 1
}


# Enable SQL Alwayson

Import-Module 'C:\Program Files (x86)\Microsoft SQL Server\110\Tools\PowerShell\Modules\SQLPS'

cd \sql\$env:COMPUTERNAME\DEFAULT
if((Get-Item .).IsHadrEnabled -eq $false){
    Write-Host "Enabling SQL Always On Availablity Groups"
    Enable-SqlAlwaysOn -Path "SQLSERVER:\SQL\$env:COMPUTERNAME\DEFAULT" -Force 
}

Restart-Computer