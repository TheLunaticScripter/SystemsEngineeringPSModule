# Prod SQL, SENTRIS, SharePoint 2013 Deployment Script

# Author: John Snow aka. The Lunatic Scripter aka. Lord Commander of the Knights Watch the North with remember

$allServers = @()
$sqlsouthservers = @()
$SPservers = @()


$sqlsouthservers += [PSCustomObject]@{Name="N93-SQL2012-N1";NumCpu=8;Memory=8;Product="SQL 2012";IPAddress="10.0.3.4";DNSServers="10.0.3.2","10.0.3.3"}
$sqlsouthservers += [PSCustomObject]@{Name="N93-SQL2012-N2";NumCpu=8;Memory=8;Product="SQL 2012";IPAddress="10.0.3.5";DNSServers="10.0.3.2","10.0.3.3"}
$sqlsouthservers += [PSCustomObject]@{Name="N93-SQL2012-N3";NumCpu=8;Memory=8;Product="SQL 2012";IPAddress="10.0.3.6";DNSServers="10.0.3.2","10.0.3.3"}
$SPservers += [PSCustomObject]@{Name="N93-SP2013-APP1";NumCpu=4;Memory=8;Product="SharePoint";IPAddress="10.0.3.9";DNSServers="10.0.3.2","10.0.3.3"}
$SPservers += [PSCustomObject]@{Name="N93-SP2013-IDX1";NumCpu=4;Memory=8;Product="SharePoint";IPAddress="10.0.3.10";DNSServers="10.0.3.2","10.0.3.3"}
$SPservers += [PSCustomObject]@{Name="N93-SP2013-WFE1";NumCpu=4;Memory=8;Product="SharePoint";IPAddress="10.0.3.11";DNSServers="10.0.3.2","10.0.3.3"}
$SPservers += [PSCustomObject]@{Name="N93-SP2013-WFE2";NumCpu=4;Memory=8;Product="SharePoint";IPAddress="10.0.3.12";DNSServers="10.0.3.2","10.0.3.3"}

$allServers += $sqlsouthservers
$allServers += $SPservers

$ConfigDataDir = '\\test\admin\share\System Engineering Module\Testing'
$SysMod = '\\test\admin\Share\System Engineering Module\Testing\SystemEngineering.psm1'

$DomainCred = (Get-Credential -Message "Domain Join Credentials.")
$LocalCred = (Get-Credential -Message "Local Credentials.")
Import-Module $SysMod

# Build SQL Servers
Write-Host "Building SQL Servers . . . " -ForegroundColor Green
Build-VirtualServer -ServerName $sqlsouthservers.Name `
                    -Service "Databases" `
                    -Site South `
                    -ConfigDataBaseDir $ConfigDataDir `
                    -SysEngModulePath $SysMod `
                    -MemoryGB $sqlsouthservers[0].Memory `
                    -NumCPU $sqlsouthservers[0].NumCpu `
                    -JoinDomain:$true `
                    -DomainCredential $DomainCred `
                    -LocalCredential $LocalCred `
                    -DataStore "DataStore3" `
                    -AddDisk:$true `
                    -DiskSizeGB 80 `
                    -DriveLetter E `
                    -DriveLabel "Database"

# Build SharePoint Servers
Write-Host "Building SharePoint Server . . . ." -ForegroundColor Green
Build-VirtualServer -ServerName $SPservers.Name `
                    -Service "SharePoint" `
                    -Site South `
                    -ConfigDataBaseDir $ConfigDataDir `
                    -SysEngModulePath $SysMod `
                    -MemoryGB $SPservers[0].Memory `
                    -NumCPU $SPservers[0].NumCpu `
                    -DataStore "DataStore1" `
                    -JoinDomain:$true `
                    -DomainCredential $DomainCred `
                    -LocalCredential $LocalCred `
                    -AddDisk:$true `
                    -DiskSizeGB 80 `
                    -DriveLetter E `
                    -DriveLabel "SP DATA"



# Add Backups Disk to SQL
Write-Host "Adding Backup disks to SQL servers" -ForegroundColor Green
foreach($server in $sqlsouthservers){
    Add-CustomVMDisk -VMName $server.Name `
                     -DataStore "DataStore3" `
                     -DiskSize 100 `
                     -DriveLetter F `
                     -DriveLabel "Backups" `
                     -ConfigDataBaseDirectory $ConfigDataDir `
                     -DriveNumber 2  
}

# Set IP Addresses to Static for Norht Servers
Write-Host "Setting Server ip address per configuration document . . . " -ForegroundColor Green
foreach($s in $allServers){
    Invoke-Command -ComputerName $s.Name -ScriptBlock {$s = $Using:s; $adapter = Get-NetAdapter | where {$_.AdminStatus -eq "Up"}; If(($adapter | Get-NetIPConfiguration).IPv4Address.IPAddress){$adapter | Remove-NetIPAddress -AddressFamily IPv4 -Confirm:$false}; if(($adapter | Get-NetIPConfiguration).Ipv4DefaultGateway){$adapter | Remove-NetRoute -AddressFamily IPv4 -Confirm:$false};$adapter | New-NetIPAddress -AddressFamily IPv4 -IPAddress $s.IPAddress -PrefixLength 24 -DefaultGateway '10.0.3.254';$adapter | Set-DnsClientServerAddress -ServerAddresses $s.DNSServers} -InDisconnectedSession
}


# Prompt User to Install SQL on all servers

Read-host -Prompt "Begin SQL Server installations please click enter when finished."


