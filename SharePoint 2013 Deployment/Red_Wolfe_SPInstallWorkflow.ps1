workflow Install-SharePoint{

    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Computers,
        [Parameter(Mandatory=$true)]
        [string]$SPSource,
        [Parameter(Mandatory=$true)]
        [string]$NetFx3Source,
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential]$DomainCred,
        [Parameter(Mandatory=$true)]
        [SecureString]$FarmPassPhrase,
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential]$SetupAcct,
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential]$FarmAcct,
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential]$ServiceAppAcct,
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential]$UserProfileAcct,
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential]$ServiceAcct,
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential]$CacheAcct,
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential]$SearchAcct,
        [Parameter(Mandatory=$true)]
        [string]$DBServer
    )
  
    Enable-WSManCredSSP -Role Client -DelegateComputer $Computers -Force
    
    #Disable loopback check on server
    Write-Output "Disabling internal loopback check"
    $regPath = "HKLM:\System\CurrentControlSet\Control\Lsa"
    $key = "DisableLoopbackCheck"
    if (test-path $regPath) {
        $keyValue = (Get-ItemProperty $regPath).$key
        if ($keyValue -ne $null){
            Set-ItemProperty -Path $regPath -Name $key -Value "1"
        }
        else{
            $loopback = New-ItemProperty $regPath -Name $key -Value "1" -PropertyType dword
        }
    }
    else {
        $loopback = New-ItemProperty $regPath -Name $key -Value "1" -PropertyType dword
    }
    

    # Install SharePoint 2013 Pre-Reqs and Binaries on all Servers
    
    foreach -Parallel ($computer in $computers){
    
        # Add sp13.setup to local Admins
        $username = "sp13.setup"
        $username1 = "sp13.farm"
        $username2 = "sp13.search"
        [string]$domainName = ([ADSI]'').name
        InlineScript{
            ([ADSI]"WinNT://$Using:computer/Administrators,group").Add("WinNT://$Using:domainName/$Using:username,user")
            ([ADSI]"WinNT://$Using:computer/Administrators,group").Add("WinNT://$Using:domainName/$Using:username1,user")
            ([ADSI]"WinNT://N93-SP2013-IDX1/Administrators,group").Add("WinNT://$Using:domainName/$Using:username2,user")
        }

        Install-WindowsFeature -Name 'Net-Framework-Core','Web-Server','Web-WebServer','Web-Common-Http','Web-Static-Content','Web-Default-Doc','Web-Dir-Browsing','Web-Http-Errors','Web-App-Dev','Web-Asp-Net','Web-Net-Ext','Web-ISAPI-Ext','Web-ISAPI-Filter','Web-Health','Web-Http-Logging','Web-Log-Libraries','Web-Request-Monitor','Web-Http-Tracing','Web-Security','Web-Basic-Auth','Web-Windows-Auth','Web-Filtering','Web-Digest-Auth','Web-Performance','Web-Stat-Compression','Web-Dyn-Compression','Web-Mgmt-Tools','Web-Mgmt-Console','Web-Mgmt-Compat','Web-Metabase','Application-Server','AS-Web-Support','AS-TCP-Port-Sharing','AS-WAS-Support','AS-HTTP-Activation','AS-TCP-Activation','AS-Named-Pipes','AS-Net-Framework','WAS','WAS-Process-Model','WAS-NET-Environment','WAS-Config-APIs','Web-Lgcy-Scripting','Windows-Identity-Foundation','Server-Media-Foundation','Xps-Viewer' -Source $NetFx3Source -Restart:$false -ComputerName $computer

        Restart-Computer -Wait -PSComputerName $computer

        Sleep 60
        
        InlineScript{
            Invoke-Command -ComputerName $Using:computer -ScriptBlock {Enable-WSManCredSSP -Role Server -Force}
            $ScriptBlock = {
                param(
                    $SPSource
                )
                 Write-Output $SPSource
                 $PreReqSource = "$SPSource\PrerequisiteInstaller.exe"
                 Write-Output $PreReqSource
                 cmd /c $PreReqSource /SQLNCli:"$SPSource\PrerequisiteInstallerFiles\sqlncli.msi" /IDFX:"$SPSource\PrerequisiteInstallerFiles\Windows6.1-KB974405-x64.msu" /IDFX11:"$SPSource\PrerequisiteInstallerFiles\MicrosoftIdentityExtensions-64.msi" /Sync:"$SPSource\PrerequisiteInstallerFiles\Synchronization.msi" /AppFabric:"$SPSource\PrerequisiteInstallerFiles\WindowsServerAppFabricSetup_x64.exe" /KB2671763:"$SPSource\PrerequisiteInstallerFiles\AppFabric1.1-RTM-KB2671763-x64-ENU.exe" /MSIPCClient:"$SPSource\PrerequisiteInstallerFiles\setup_msipc_x64.msi" /WCFDataServices:"$SPSource\PrerequisiteInstallerFiles\WcfDataServices.exe" /WCFDataServices56:"$SPSource\PrerequisiteInstallerFiles\WcfDataServices56.exe" /unattended
            }
            Invoke-Command -ComputerName $Using:computer -ScriptBlock $ScriptBlock -ArgumentList $Using:SPSource -Authentication Credssp -Credential $Using:DomainCred
        }
        
        Sleep 60

        Restart-Computer -Wait -PSComputerName $computer

        InlineScript{
            $SPSource = $Using:SPSource
            Invoke-Command -ComputerName $Using:computer -ScriptBlock {param($SPSource); cmd /c "$SPSource\setup.exe" /config "$SPSource\SPCustomConfig.xml"} -ArgumentList $Using:SPSource -Authentication Credssp -Credential $Using:DomainCred
        }
    }
    
    
    # Create Farm and Join other servers to the Farm

    foreach ($c in $Computers){
        If($c -like "*APP1*"){
            InlineScript{
                $ScriptBlock = {
                    param(
                        $passphrase,
                        $farmcred,
                        $DBName,
                        $DBServer,
                        $DBAdminContent
                    )
                    Add-PSSnapin Microsoft.SharePoint.PowerShell -WarningAction SilentlyContinue
                    New-SPConfigurationDatabase -DatabaseName $DBName `
                                                -DatabaseServer $DBServer `
                                                -AdministrationContentDatabaseName $DBAdminContent `
                                                -Passphrase $passphrase `
                                                -FarmCredentials $farmcred `
                                                -SkipRegisterAsDistributedCacheHost

                    New-SPCentralAdministration -Port "12345" -WindowsAuthProvider "NTLM"

                    # Install Services
                    Install-SPHelpCollection -All      
                    Initialize-SPResourceSecurity
                    Install-SPService
                    Install-SPFeature -AllExistingFeatures -Force
                    Install-SPApplicationContent
                }

                Invoke-Command -ComputerName $Using:c -ScriptBlock $ScriptBlock -ArgumentList $Using:FarmPassPhrase,$Using:FarmAcct,"SP13_Config",$Using:DBServer,"SP13_Admin_Content" -Authentication Credssp -Credential $Using:SetupAcct
            }
        }
        else{
            InlineScript{
                [SecureString]$passphrase = $Using:FarmPassPhrase
                [string]$DBServer = $Using:DBServer
                [string]$DBName = "SP13_Config"
                $ScriptBlock = {
                    param($DBServer,$DBName,$passphrase)
                    Add-PSSnapin Microsoft.SharePoint.PowerShell -WarningAction SilentlyContinue
                    Connect-SPConfigurationDatabase -DatabaseServer $DBServer -DatabaseName $DBName -Passphrase $passphrase

                    # Install Services
                    Install-SPHelpCollection -All      
                    Initialize-SPResourceSecurity
                    Install-SPService
                    Install-SPFeature -AllExistingFeatures -Force
                    Install-SPApplicationContent
                }

                Invoke-Command -ComputerName $Using:c -ScriptBlock $ScriptBlock -ArgumentList $DBServer,$DBName,$passphrase -Authentication Credssp -Credential $Using:SetupAcct
            }
        }
    }

    foreach -Parallel ($computer in $Computers){
        inlineScript{
        $computer = $using:computer
        $Service = Get-Service -ComputerName $computer -Name "SPTimerv4"
        if ($Service.Status -eq "Stopped"){
            Write-Output "Timer Service stopped on server $computer"
            $Service | Start-Service  
        }
        else {
            Write-Output "Timer Service is Running on $computer" 
        }
        }
    }

    # Add SP Amdinistrators group to Farm Admins
    InlineScript{
        
        $ScriptBlock = {
            param(
                $ServiceAppAcct,
                $UserProfileAcct,
                $ServiceAcct,
                $CacheAcct,
                $SearchAcct
            )
            
            #Add SharePoint PowerShell snap-in
            Add-PSSnapin microsoft.sharepoint.powershell

            ##### Set Local Variables
            #Set Admins who will be granted shell access
            $ShellUsers = $env:USERDNSDOMAIN + "\" + "SPAdmins"

            #Get the Central Administration root website object, where the farm administrators group is defined
            $CAApp = Get-SPWebApplication -IncludeCentralAdministration | ?{$_.DisplayName -like "*Central Administration*"}
            $CASite = new-Object Microsoft.SharePoint.SPSite($CAApp.Url)
            $CAWeb = $CASite.RootWeb


            #Add User List to Farm Admin and Shell Admin groups. 
            foreach($UserName in $ShellUsers){
                #Add user to the farm administrator's group
                ($CAWeb.SiteGroups["Farm Administrators"]).AddUser($UserName,"","","")
                
                #Grant users shell administrator rights
                Add-SPShellAdmin -UserName $UserName
            }

            # Register SharePoint 2013 Service Applications - sp13.serviceapps
            $ServiceApps = $ServiceAppAcct
            New-SPManagedAccount $ServiceApps
            Write-Output "SP13.serviceapps managed account registered."
            
            # Register SharePoint 2013 User Profile - sp13.userprofile
            $UserProfile = $UserProfileAcct
            New-SPManagedAccount $UserProfile
            Write-Output "SP13.userprofile managed account registered."

            # Register SharePoint 2013 Service - sp13.service
            $Service = $ServiceAcct
            New-SPManagedAccount $Service
            Write-Output "SP13.service managed account registered."

            # Register SharePoint 2013 Distributed Cache - sp13.cache
            $Cache = $CacheAcct
            New-SPManagedAccount $Cache
            Write-Output "SP13.cache managed account registered."
            
            # Register Search Service Application
            $Search = $SearchAcct
            New-SPManagedAccount $Search
            Write-Output "SP13.search managed account registered."
          

            #### Create Default Service Application Pool
            $DefaultAppPoolName = "SP13_ServiceApplicationsDefaultAppPool"
            $DefaultAppPool = Get-SPServiceApplicationPool -Identity $DefaultAppPoolName -ErrorAction SilentlyContinue
            
            if(!$DefaultAppPool){
                Write-Output "Creating Default Services Application Pool..."
                $AppAccount = Get-SPManagedAccount -Identity "$env:USERDOMAIN\sp13.serviceapps"
                $DefaultAppPool = New-SPServiceApplicationPool –Name $DefaultAppPoolName –Account $AppAccount
            }


            #### Usage and Health Data Collection Service Application
            $logPath = Get-Item -Path "E:\SPUsageLogs"
            if ($logPath -eq $null){
                New-Item -ItemType Directory -Force -Path E:\SPUsageLogs
                Write-Output "Usage Log folder created"
            }
            
            $usageLogLocation = "E:\SPUsageLogs"
            $UsageService = Get-SPUsageService -ErrorAction SilentlyContinue
            if ($UsageService -eq $null){
                throw "Unable to retrieve SharePoint Usage Service."
            }
            Set-SPUsageService -Identity $UsageService `
                               -UsageLogLocation $usageLogLocation
            
            Write-Output "Creating Usage and Health Data Collection Service Application..."
            $usageAppName = "Usage and Health Data Collection Service Application"
            $usageApp = Get-SPUsageApplication $usageAppName
            
            if ($usageApp -eq $null){
                $usageSvc = Get-SPUsageService
                $usageApp = $usageSvc | New-SPUsageApplication –Name $usageAppName `
                                                               –DatabaseServer “SP13-Listener” `
                                                               –DatabaseName “SP13_UsageApplication” `

                $usageProxy = Get-SPServiceApplicationProxy | Where-Object {$_.TypeName -eq "Usage and Health Data Collection Proxy"}
                $usageProxy.Provision()
            }
            
            Set-SPDiagnosticConfig -LogLocation $usageLogLocation


            #### State Service Application
            $stateSvcDBName = “SP13_StateService”
            $stateSvcDB = Get-SPStateServiceDatabase $stateSvcDBName
            if ($stateSvcDB -eq $null){
                Write-Output "Creating $stateSvcDBName"
                $stateSvcDB = New-SPStateServiceDatabase –Name $stateSvcDBName `
                                                         -DatabaseServer "SP13-Listener"
                $stateSvcDB | Initialize-SPStateServiceDatabase
            }

            $stateSvcAppName = “State Service”
            $stateSvcApp = Get-SPStateServiceApplication $stateSvcAppName
            if ($stateSvcApp -eq $null){
                Write-Output "Creating $stateSvcAppName"
                $stateSvcApp = New-SPStateServiceApplication –Name $stateSvcAppName `
                                                             -Database $stateSvcDB
            }

            $stateSvcAppProxyName = "State Service Proxy"
            $stateSvcAppProxy = Get-SPStateServiceApplicationProxy $stateSvcAppProxyName
            if ($stateSvcAppProxy -eq $null){
                Write-Output "Creating $stateSvcAppProxyName"
                $stateSvcAppProxy = New-SPStateServiceApplicationProxy -ServiceApplication $stateSvcApp `
                                                                       -Name $stateSvcAppProxyName `
                                                                       –DefaultProxyGroup
            }
            

            #### Subscription Settings Service Application
            $subsSettingsService = Get-SPServiceInstance | where {$_.TypeName -eq "Microsoft SharePoint Foundation Subscription Settings Service"}
            if($subsSettingsService.Status -ne "Online"){
                Write-Output "Starting Microsoft SharePoint Foundation Subscription Settings Service ..."
                $subsSettingsService | Start-SPServiceInstance | Out-Null
            }

            Sleep 5
            
            $subsSettingsServiceAppName = "Subscription Settings Service Application"
            $subsSettingsServiceApp = Get-SPServiceApplication | where {$_.Name -eq $subsSettingsServiceAppName}
            
            Write-Output "Creating Subscription Settings Service Application..."
            if($subsSettingsServiceApp -eq $null){
                #$appPool = Get-SPServiceApplicationPool "SP13_ServiceApplicationsDefaultAppPool"
                $subsSettingsServiceApp = New-SPSubscriptionSettingsServiceApplication –ApplicationPool $DefaultAppPool `
                                                                                       –Name $subsSettingsServiceName `
                                                                                       –DatabaseName “SP13_SubscriptionSettingsService”
                $subsSettingsServiceAppProxy = New-SPSubscriptionSettingsServiceApplicationProxy –ServiceApplication $subsSettingsServiceApp
                
            }
            

            ##### Excel Service Application
            $excelService = Get-SPServiceInstance | where {$_.TypeName -eq "Excel Calculation Services"}
            if($excelService.Status -ne "Online"){
                Write-Output "Starting Excel Calculation Services..."
                $excelService | Start-SPServiceInstance | Out-Null
            }

            Sleep 5
            
            $ExcelServieApp = Get-SPExcelServiceApplication
            $ExcelServiceName = "Excel Services Service Application"

            if($ExcelServiceApp -eq $null){
                Write-Output "Creating Excel Calculation Service Application..."
                $ExcelServiceApp = New-SPExcelServiceApplication -Name $ExcelServiceName `
                                                                 -ApplicationPool $DefaultAppPool `
                                                                 -LoadBalancingScheme "WorkbookUrl"
       
            }

            
            ##### Application Management Service
            $AppMgmtService = Get-SPServiceInstance | where {$_.TypeName -eq "App Management Service"}
            if($AppMgmtService.Status -ne "Online"){
                Write-Output "Starting App Management Service Services..."
                $AppMgmtService | Start-SPServiceInstance | Out-Null
            }

            Sleep 5

            #App Management Service Application Name
            $AppManagementAppName = "App Management Service Application"
            #App Management Database Name
            $AppManagementDatabase = "SP13_AppManagement"
            #Name the App Management Service Application Proxy
            $AppManagementProxy = "$AppManagementAppName Proxy"
            $AppManagementApp = Get-SPServiceApplication | Where {$_.Name -eq $AppManagementAppName}

            if($AppManagementAppName -eq $null){
                Write-Output "Creating App Management Service Application and Proxy..."
                $AppManagementApp = New-SPAppManagementServiceApplication -Name $AppManagementAppName `
                                                                          -DatabaseName $AppManagementDatabase `
                                                                          -ApplicationPool $DefaultAppPool
                
                New-SPAppManagementServiceApplicationProxy -Name $AppManagementProxy `
                                                           -ServiceApplication $AppManagementApp `
                                                           -UseDefaultProxyGroup            
            }

            #### Create Primaty Web Application, Root Site Collection, Apps Catalog Site Collection, and Enterprise Search Site Collection
            #Variables for web application
            $WebAppName = "SharePoint - SP13”
            $Port = 443
            $hostHeader = "portal.$ENV:USERDNSDOMAIN"
            #Use Kerberos, to use NTLM, input -DisableKerberos:$true
            $authprovider = New-SPAuthenticationProvider -UseWindowsIntegratedAuthentication
            $url = "https://portal.$ENV:USERDNSDOMAIN"
            $appPoolName = "SharePoint-SP13"
            $appPoolAccount = (Get-SPManagedAccount "$ENV:USERDOMAIN\sp13.service")
            $dbServer = "SP13-Listener"
            $dbName = "SP13_WSS_Content"


            #Create Web Application, Remove the –SecureSocketsLayer flag if SSL is not to be used
            Write-Output "Creating Web Application...”
            $webApp = New-SPWebApplication -Name $WebAppName `
                                           -Port $port `
                                           -HostHeader $hostHeader `
                                           -AuthenticationProvider $authprovider `
                                           -URL $url `
                                           -ApplicationPool $AppPoolName `
                                           -ApplicationPoolAccount $AppPoolAccount `
                                           -DatabaseServer $dbServer `
                                           -DatabaseName $dbName `
                                           –SecureSocketsLayer
                               
            Write-Output "WebApp created using SSL"
            Write-Output ""
            Write-Output "#### ENSURE HOST RECORD FOR" $hostHeader "EXISTS IN DNS, SSL CERTICATE WAS CREATED AND IMPORTED INTO EACH WFE, AND IIS BINDINGS ARE CONFIGURED ####"

            Sleep 5

            #Variables for root site collection
            $rootSiteUrl = "https://portal.$ENV:USERDNSDOMAIN"
            $rootSiteTitle = "SP13 Portal"
            $rootSiteDesc = "SAPNet Portal"
            $rootSiteOwner = "$ENV:USERDNSDOMAIN\rodney.loranunez"
            $rootSiteTemplate = "BLANKINTERNETCONTAINER#0"
                #Templates: Publishing Portal: BLANKINTERNETCONTAINER#0, Team Site: STS#0
            
            #Create root site collection
            Write-Output "Creating root site collection..."
            $rootSite = New-SPSite -Url $rootSiteUrl/ `
                               -Template $rootSiteTemplate `
                               -OwnerAlias $rootSiteOwner `
                               -Name $rootSiteTitle `
                               -Description $rootSiteDesc `
                               
            Write-Output "Root site collection created"
            Write-Output ""
            
            #Create App Catalog Site Collection
            #Variables for App site collection
            $AppHostCollectionURL = "https://portal.$ENV:USERDNSDOMAIN/sites/appcatalog"
            $AppHostSiteName = "Apps Catalog"
            $AppSiteDesc = "Apps Catalog"
            $AppSiteOwner = "$ENV:USERDNSDOMAIN\rodney.loranunez"

            Write-Output "Creating App Catalog Site Collection..."
            New-SPSite -Url $AppHostCollectionURL `
                       -Name $AppHostSiteName `
                       -Description $AppSiteDesc `
                       -OwnerAlias $AppSiteOwner `
                       -Template “APPCATALOG#0”
             
            Write-Output "Updating App Catalog Site..."
            Update-SPAppCatalogConfiguration -Site $AppHostCollectionURL -Force:$true -SkipWebTemplateChecking:$true

            Write-Output "App Catalog site collection created"
            Write-Output ""
            
            #Create Enterprise Search site collection
            #Variables for Enterprise Search site collection
            $SearchCollectionURL = "https://portal.$ENV:USERDNSDOMAIN/sites/search"
            $SearchHostSiteName = "Enterprise Search"
            $SearchSiteDesc = "SAPNet Portal Enterprise Search"
            $SearchSiteOwner = "$ENV:USERDNSDOMAIN\rodney.loranunez"

            Write-Output "Creating Enterprise Search Site Collection..."
            New-SPSite -Url $SearchCollectionURL `
                       -Name $SearchHostSiteName `
                       -Description $SearchSiteDesc `
                       -OwnerAlias $SearchSiteOwner `
                       -Template “SRCHCEN#0” 

            Write-Output "Enterprise Search site collection created"
            Write-Output ""


            #### Excel Services Updates
            Write-Output "Updating trusted file location for Excel Services Application..."
            Get-SPExcelServiceApplication | Get-SPExcelFileLocation | Set-SPExcelFileLocation -Address $rootSiteUrl -Description "Default trusted file location for Excel Services Application"

            Write-Output "Granting sp13.ServiceApps permissions to access content DBs in Web App..."
            $webApp.GrantAccessToProcessIdentity("$env:userdomain\sp13.serviceapps")

            Write-Output "Updating Web App Branding..."
            $webApp.SuiteBarBrandingElementHtml = '<div class="ms-core-brandingText"><a style="color:#fff;" href="/">SharePoint 2013 UNCLASS Test Bed</a></div>'
            $webApp.Update();
        }
        
        Invoke-Command -ComputerName ($Using:Computers | where {$_ -like "*APP1*"}) `
                       -ScriptBlock $ScriptBlock `
                       -ArgumentList $Using:ServiceAppAcct,$Using:UserProfileAcct,$Using:ServiceAcct,$Using:CacheAcct,$Using:SearchAcct `
                       -Authentication Credssp `
                       -Credential $Using:SetupAcct

    }
    
}
