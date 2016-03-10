
Function New-StandardVM {
    [CmdletBinding(DefaultParameterSetName="Name")]
    Param(
        [Parameter(Mandatory = $True,Position = 0,ValueFromPipeline=$True)]
        [String[]]$Name,
        [Parameter(Mandatory = $True,Position = 1)]
        [String[]]$Folder,
        [Parameter(Mandatory = $True,Position = 2)]
        [String[]]$DataStore,
        [Parameter(Mandatory = $True,Position = 3)]
        [String[]]$Site,
        [Parameter(Mandatory = $True,Position = 4)]
        [String]$ConfigDataBaseDirectory,
        [Parameter(Mandatory = $True,Position = 5)]
        [String]$ConfigDataFileName,
        [Parameter(Position=6)]
        [String]$Template,
        [Parameter(Position=7)]
        [String]$Customization,
        [Parameter(Position=8)]
        [Decimal]$Memory,
        [Parameter(Position=9)]
        [Int64]$NumCPUs
        
    )

    Begin{}

    Process{
        Try{
            # Import Configuration Data File
            $ConfigData = Import-LocalizedData -BaseDirectory $ConfigDataBaseDirectory -FileName $ConfigDataFileName

            # Add Snapins for PowerCLI        
            $Snapins = Get-PSSnapin

            Foreach($snap in $Snapins){
                if($snap.Name -eq "VMWare.VimAutomation.Core"){
                    Write-Host "Snap in already loaded"
                }
                else{
                    Add-PSSnapin "VMWare.VimAutomation.Core"
                    
                    Connect-VIServer ($ConfigData.Nodes.Where{($_.Role -eq "VSphere") -and ($_.ADSite -eq [System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::GetComputerSite().Name)}).NodeName -AllLinked 
                }
            
            }

            # Get Cluster Resource Pool
            If($Site[0] -like "*South*"){
                $Resource = Get-ResourcePool
                if($Resource.Count -gt 1){
                    $Resource = $Resource | Where {$_.Parent -like "*South*"}
                }
                else{
                    if($Resource.Parent -like "*South*"){
                    }
                    else{
                        Write-Host "There is currently an issue with the VSphere service." -ForegroundColor Red
                        break;
                    }
                }
            }
            elseIf($Site[0] -like "*North*"){
                $Resource = Get-ResourcePool
                if($Resource.Count -gt 1){
                    $Resource = $Resource | Where {$_.Parent -like "*North*"}
                }
                else{
                    if($Resource.Parent -like "*North*"){
                    }
                    else{
                        Write-Host "There is currently an issue with the VSphere service." -ForegroundColor Red
                        break;
                    }
                }
            }
            else{
                Write-Host "Invalid Site location" -ForegroundColor Red
                break;
            }
            
            # Get Customization File                         
            if($Customization){
                $OSCustom = Get-OSCustomizationSpec | where {$_.Name -like "*$($Customization[0])*"}
            }
            else{
                $OSCustom = Get-OSCustomizationSpec | where {$_.Name -eq $ConfigData.Common.BaselineOSCustomization}
            }

            # Check to ensure only one resource pool is specified
            If($Resource.Count -gt 1){
                Write-Host "The resource pools are: "
                Foreach($r in $Resource){
                    $r.Name
                }
                break;
            }

            if($Memory -eq 0){
                $Memory = 4
            }
            if($NumCPUs -eq 0){
                $NumCPUs = 1
            }

            # Get Template
            $usedTemplate = if($Template){$Template}else{$ConfigData.Common.BaselineOSTemplateName}

            # Build VM
            $VMS = new-vm -Name $Name[0] `
                          -Location $Folder[0] `
                          -Datastore $Datastore[0] `
                          -ResourcePool $Resource `
                          -OSCustomizationSpec $OSCustom[0].Name `
                          -Template $usedTemplate
            
            $VMS | Set-VM -NumCpu $NumCPUs -MemoryGB $Memory -Confirm:$false
    
            $VMS = $VMS | Start-VM

            
            # Start of Customization Monitoring
            $timeoutSeconds = 600

            # Constants for status
            $STATUS_VM_NOT_STARTED = "VmNotStarted"
            $STATUS_CUSTOMIZATION_NOT_STARTED = "CustomizationNotStarted"
            $STATUS_STARTED = "CustomizationStarted"
            $STATUS_SUCCEEDED = "CustomizationSucceeded"
            $STATUS_FAILED = "CustomizationFailed"
            $STATUS_NOT_COMPLETED_LIST = @($STATUS_CUSTOMIZATION_NOT_STARTED, $STATUS_STARTED)
    
            # Constants for Event types
            $evt_type_custom_started = "VMware.Vim.CustomizationStartedEvent"
            $evt_type_custom_Succeeded = "VMWare.Vim.CustomizationSucceeded"
            $evt_type_custom_failed = "VMWare.Vim.CustomizationFailed"
            $evt_type_custom_Start = "VMware.Vim.VmStartingEvent"

            $WaitInterval = 15

            
            $time = Get-Date
            $timeevntFilter = $time.AddMinutes(-5)
            $vmDescriptors = New-Object System.Collections.ArrayList
            # Determines for each VM in the list if the VM is started
            foreach ($vm in $VMS){
                Write-Host "Start monitoring customization for vm '$vm'"
                $obj = "" | select VM,CustomizationStatus,StartVMEvent
                $obj.VM = $vm
                $obj.StartVMEvent = Get-VIEvent $vm -Start $timeevntFilter | where {$_ -is $evt_type_custom_Start} | Sort CreatedTime | Select -Last 1
                if(!($obj.StartVMEvent)){
                    $obj.CustomizationStatus = $STATUS_VM_NOT_STARTED
                }
                else{
                    $obj.CustomizationStatus = $STATUS_CUSTOMIZATION_NOT_STARTED
                }
                ($vmDescriptors.Add($obj))
            }

            # Determins whether the timeout has occured or the Status is finished to continue the loop
            $shouldContinue = {
                $notCompleteVMs = $vmDescriptors | where {$STATUS_NOT_COMPLETED_LIST -contains $_.CustomizationStatus}
                $currentTime = Get-Date
                $timeoutElapsed = $currentTime - $time
                $timeoutNotElasped = ($timeoutElapsed.TotalSeconds -lt $timeoutSeconds)

                return (($notCompleteVMs -ne $null) -and ($timeoutNotElasped))
            }

            # Begins looping through the event to determine VM Status
            while(& $shouldContinue){
                foreach($vmItem in $vmDescriptors){
                    $vmName = $vmItem.VM.Name
                    switch($vmItem.CustomizationStatus){
                        $STATUS_CUSTOMIZATION_NOT_STARTED {
                            $vmEvents = Get-VIEvent -Entity $vmItem.VM -Start $vmItem.StartVMEvent.CreatedTime
                            $startEvent = $vmEvents | where {$_ -is $evt_type_custom_started}
                            if ($startEvent){
                                $vmItem.CustomizationStatus = $STATUS_STARTED
                                Write-Host "Customization for VM '$vmName' has started" -ForegroundColor Green
                            }
                            break;
                        }
                        $STATUS_STARTED {
                            $vmEvents = Get-VIEvent -Entity $vmItem.VM -Start $vmItem.StartVMEvent.CreatedTime
                            $succeedEvent = $vmEvents | where {$_ -is $evt_type_custom_Succeeded}
                            $failedEvent = $vmEvents | where {$_ -is $evt_type_custom_failed}
                            if($succeedEvent){
                                $vmItem.CustomizationStatus = $STATUS_SUCCEEDED
                                Write-Host "Customization for VM '$vmName' has successfully completed" -ForegroundColor Green
                            }
                            if($failedEvent){
                                $vmItem.CustomizationStatus = $STATUS_FAILED
                                Write-Host "Customization for VM '$vmName' has Failed" -ForegroundColor Red
                            }
                            break;
                        }
                        default {
                            break;
                        }
                    }
                }

                #Write-Host "Sleeping for $WaitInterval seconds"
                Sleep $WaitInterval
            }

            # Outputs the results of the Customization
            $result = $vmDescriptors
            return $result
        }
        Catch{
            Write-Error error$_
        }
    }
    end{}


<#
.Synopsis
   Creates a new Windows 2012 R2 SP1 Standard Virtual Machine 
   on the North or South Cluster.

.Description
   The New-StandardVM Function creates a new Windows 2012 R2 SP1 
   Standard Virtual Machine on the VMware Environment. It can be 
   on the North Cluster or the South Cluster.

.Parameter Name
   The name of the Server
 
.Parameter Folder
   The VSphere the VM will be put in

.Parameter DataStore
   The DataStore of the storage for the VM. This needs to 
   already be a valide DataStore in VSphere environment.

.Parameter Site
   The cluster site the VM will be on example North or South

.Parameter ConfigDataBaseDirectory
   The Folder location where the network specific Configuration 
   Data file lives.

.Parameter ConfigDataFileName
   The name of the Configuration Data File

.Parameter Template
   [Optional] This allows you to change the default template 
     that is being used to to build the server. The default 
     template is identified in the Configuration Data file.

.Parameter Customization
   [Optional] This allows you to change the default Customization 
     file that is being used to build the server. The default 
     template is identifed in the Configuration Data file

.Parameter Memeory
   [Optional] Increase or decrease the available Memory in GB
     DEFAULT: 4GB

.Parameter NumCPUs
   [Opetional] Increase the number of CPUs
     DEFAULT: 1

.Example
     New-StandardVM `
      -Name "Testing" `
      -Folder "Testing" `
      -DataStore "TestDataStore_1" `
      -Site "South" `
      -ConfigDataBaseDirectory "\\contoso\share\ConfigData" `
      -ConfigDataFileName "ConfigData.psd1"

.Example
     New-StandardVM ` 
      -Name "Testing" `
      -Folder "Testing" `
      -DataStore "TestDataStore_1" `
      -Site "South" `
      -ConfigDataBaseDirectory "\\contoso\share\ConfigData" `
      -ConfigDataFileName "ConfigData.psd1" `
      -Template "Windows Server 2008 R2" `
      -Customization "Windows 2008 R2 Customization"
.Inputs
   You can supply the Server Name to be built

.Outputs
   Returns the status of the VM customization

.Notes
    Version: 1.0.1072016
    Date Created: 1/7/2016
    Creator: John Snow TLS
    Required Software: PowerCLI v5.8 
                       VSphere 5.1 or greater 
                       VMWare Template
                       VMWare Customization File
    PowerShell Version: v3.0 or greater

.Component
    PowerCLI 5.8
    VMWare 5.1
    VSphere 5.1

.Role
    Virtualization Administrator

.Functionality
    Build Company Standard Virtual Machine on VMWare and 
    monitor the completion of the customization file
#>
}

Function Add-StandardVMNetwork {
    
    [CmdletBinding(DefaultParameterSetName="VMName")]

    param(
        [parameter(Mandatory=$true,Position=0)]
        [String]$VirtualNetworkName,
        [parameter(Mandatory=$true,Position=1)]
        [string]$VMName,
        [parameter(Mandatory=$true,Position=2)]
        [Boolean]$DHCP,
        [parameter(Mandatory=$true,Position=3)]
        [string]$ConfigDataBaseDirectory,
        [parameter(Mandatory=$true,Position=4)]
        [string]$ConfigDataFileName
        #[parameter][string]$IP,
        #[parameter][string]$Subnet,
        #[parameter][string]$DefaultGateway
        
    )

    Begin{}

    Process{
        # Import Configuration Data File
        $ConfigData = Import-LocalizedData -BaseDirectory $ConfigDataBaseDirectory -FileName $ConfigDataFileName

        # Add Snapins for PowerCLI        
        $Snapins = Get-PSSnapin

        Foreach($snap in $Snapins){
            if($snap.Name -eq "VMWare.VimAutomation.Core"){
                    Write-Host "Snap in already loaded"
            }
            else{
                Add-PSSnapin "VMWare.VimAutomation.Core"
                    
                Connect-VIServer ($ConfigData.Nodes.Where{($_.Role -eq "VSphere") -and ($_.ADSite -eq [System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::GetComputerSite().Name)}).NodeName -AllLinked 
            }
           
        }

        New-NetworkAdapter -NetworkName $VirtualNetworkName -VM $VMName -Type Vmxnet3 -StartConnected -WakeOnLan



    }

    End{}
<#
.Synopsis
  Adds a NIC to the VM and configures it for DHCP or Static IP

.Description
  Adds a NIC to the VM and configures it for DHCP or Static IP

.Parameter VirtualNetworkName
  The virtual network as seen in VMWare example "Adam-Test 93"

.Parameter VMName
  The name of the server to be configured

.Parameter DHCP
  Boolean yes use DHCP or No

.Example
  Set-ADStandardServer -Service "Testing" -ServerName "Testing"

#>

}

function Set-StandardVM_AD{
    [CmdletBinding(DefaultParameterSetName="ServerName")]
<#
.Synopsis
  Adds a WorkGroup VM to Active Directory

.Description
  Adds a Server to Active Directory in the correct service OU under the Member Servers OU

.Parameter Service
  The service that Server will be used to support ie. Exchange, SteelCentral, Lync, etc.

.Parameter ServerName
  The name of the server to be configured

.Example
  Set-ADStandardServer -Service "Testing" -ServerName "Testing"

#>
    
    param(
        [Parameter(Mandatory=$true,Position = 0)][String]$Service,
        [Parameter(Mandatory=$true,Position = 1)][String[]]$ServerName,
        [Parameter(Mandatory=$true,Position = 2)][String]$ConfigDataBaseDirectory,
        [Parameter(Mandatory=$true,Position = 3)][String]$ConfigDataFileName,
        [Parameter(Mandatory=$true,Position = 4)][System.Management.Automation.PSCredential]$DomainCred,
        [Parameter(Mandatory=$true,Position = 5)][System.Management.Automation.PSCredential]$LocalCred
    
    )

    Begin{
        Import-Module ActiveDirectory

        $domain = $env:USERDNSDOMAIN

        $PDC = Get-ADDomainController -Discover -Service PrimaryDC

        $rootOU = Get-ADOrganizationalUnit -Filter {Name -like "*Member Servers*"} -Server $PDC

        if($rootOU.Count -gt 1){
            Write-Host "Error there is more than one Member Servers OU." -ForegroundColor Red
        }
        else{
            $OU = Get-ADOrganizationalUnit -Filter {Name -eq $Service} -SearchBase $rootOU -Server:$PDC
            #$OU
        }


    }

    Process{
        # Import Configuration Data File
        $ConfigData = Import-LocalizedData -BaseDirectory $ConfigDataBaseDirectory -FileName $ConfigDataFileName

        # Add Snapins for PowerCLI        
        $Snapins = Get-PSSnapin

        Foreach($snap in $Snapins){
            if($snap.Name -eq "VMWare.VimAutomation.Core"){
                    Write-Host "Snap in already loaded"
            }
            else{
                Add-PSSnapin "VMWare.VimAutomation.Core"
                    
                Connect-VIServer ($ConfigData.Nodes.Where{($_.Role -eq "VSphere") -and ($_.ADSite -eq [System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::GetComputerSite().Name)}).NodeName -AllLinked 
           }
          
        }
        if(!$OU){
            #Create new OU

            #Write-Host "Creating OU"

            New-ADOrganizationalUnit -Name:$Service `
                                     -Path:$rootOU `
                                     -ProtectedFromAccidentalDeletion:$false `
                                     -Server:$PDC.name

            $newOU = Get-ADOrganizationalUnit -Filter {Name -eq $Service} -SearchBase $rootOU -Server:$PDC.Name

            Write-host $newOU
        }
        else{
            $newOU = Get-ADOrganizationalUnit -Filter {Name -eq $Service} -SearchBase $rootOU -Server:$PDC.Name
        }



        # Prestage Server in OU
    
        New-ADComputer -Enabled:$false `
                       -Name:$ServerName[0] `
                       -Path:$newOU.DistinguishedName `
                       -SamAccountName:$ServerName[0] `
                       -Server:$PDC.Name

        # Add Server to Domain

        $userName = $env:USERDNSDOMAIN + "\" + $env:USERNAME

        Add-Computer -DomainCredential $DomainCred `
                     -LocalCredential $LocalCred `
                     -DomainName "test.local" `
                     -ComputerName $ServerName[0] `
                     -Server $PDC.Name
    
        Restart-VMGuest $ServerName[0]

    }
    End{}


}

Function Add-CustomVMDisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]$VMName,
        [Parameter(Mandatory=$true,Position=1)]
        [string]$DataStore,
        [Parameter(Mandatory=$true,Position=2)]
        [Decimal]$DiskSize,
        [Parameter(Mandatory=$true,Position=3)]
        [Validateset('E','F')]
        [string]$DriveLetter, 
        [Parameter(Mandatory=$true,Position=4)]
        [string]$DriveLabel,
        [Parameter(Mandatory=$true,Position=5)]
        [string]$ConfigDataBaseDirectory

    )

    Begin{
        # Import ConfigData File
        
        $ConfigData = Import-LocalizedData -BaseDirectory $ConfigDataBaseDirectory -FileName "ConfigData.psd1"

        # Connect to VSphere

        $Snapins = Get-PSSnapin

        Foreach($snap in $Snapins){
            if($snap.Name -eq "VMWare.VimAutomation.Core"){
                Write-Host "Snap in already loaded"
            }
            else{
                Add-PSSnapin "VMWare.VimAutomation.Core"
                    
                Connect-VIServer ($ConfigData.Nodes.Where{($_.Role -eq "VSphere") -and ($_.ADSite -eq [System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::GetComputerSite().Name)}).NodeName -AllLinked 
            }
            
        }
    }

    Process{

        Get-VM -Name $VMName | New-HardDisk -CapacityGB $DiskSize -Datastore $DataStore


        if((Test-Connection -ComputerName $VMName -Count 1)){

            Invoke-Command -ComputerName $VMName `
                           -Verbose `
                           -ScriptBlock {
                                Initialize-Disk -Number 1 -PartitionStyle GPT
                                New-Partition -DiskNumber 1 -UseMaximumSize -DriveLetter $Using:DriveLetter
                                Format-Volume -DriveLetter $Using:DriveLetter -FileSystem NTFS -NewFileSystemLabel $Using:DriveLabel -Confirm:$false
                            }
        }        
    }

    End{
        
    }

<#

.Synopsis
  Adds a new VirtualDisk to a VM.

.Description
  Adds a disk to a VM with PowerCLI, Initializes the disk as GPT, Creates a Partition, and Formats the disk as NTFS

.Parameter VMName
  Name of the VM being configured

.Parameter DataStore
  Datastore where the disk will be stored

.Parameter DiskSize
  Size of the disk to be greated in GB's

.Parameter DriveLetter
  The Drive letter that is going to be used Valid options are currently E and F

.Parameter DriveLabel
  This is the purpose of the drive being created ie. Databases, Data, Software, etc.

.Parameter ConfigDataBaseDirectory
  The Directory the Configuration Data file is stored o the network the function is being run.
  

.Example
  Add-VMDisk -VMName <Test> -DataStore DatStore_112 -DiskSize 80 -DriveLetter E -DriveLabel "Data" -ConfigDataBaseDirectory '\\test\admins\share\System Engineering Module\Published' 

#>

}


Function Install-StandardSQL{
    [CmdletBinding()]
    
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]$SQLSourceDir,
        [Parameter(Mandatory=$true,Position=1)]
        [string]$NetFx3SourceDir,
        [Parameter(Mandatory=$true,Position=2)]
        [string]$ServerName,
        [Parameter(Mandatory=$true,Position=3)]
        [System.Management.Automation.PSCredential]$DomainCred,
        [Parameter(Mandatory=$true,Position=4)]
        [string]$SQLSvcAcct,
        [Parameter(Mandatory=$true,Position=5)]
        [String]$SQLSvcAcctPassword,
        [Parameter(Mandatory=$true,Position=6)]
        [string]$StartingSQLConfigINI,
        [Parameter(Mandatory=$true,Position=7)]
        [Int64]$MaxSQLMemoryinKB
    
    )
    Begin{}

    Process{
        #Install .Net 3.5 Features from Source
    
        Install-WindowsFeature -Name NET-FRAMEWORK-CORE -ComputerName $ServerName -Source $NetFx3SourceDir


        # Create SQL Install and Temporary Service Account
        #Import-Module ActiveDirectory

        # Build SQL Configuration File

        $IniContent = Get-IniContent -FilePath $StartingSQLConfigINI

        $outfile = New-Item -Path "$SQLSourceDir\ConfigurationFile.ini" -ItemType file -Force
        $SQLProps = @()

        foreach($keys in $IniContent.OPTIONS.Keys){
            #Write-Host $i $keys
            #"-----------------------"
            $i++
            #Write-Host $keys

            $obj = [pscustomobject]@{Property=$keys;Value=""}
            $SQLProps += $obj

            #$testKeys += $keys
        }

    
        $t = 0
        $testValues = @()

        foreach($values in $IniContent.OPTIONS.Values){
            #Write-Host $t $values
            #"-----------------------"
            $t++

            $testValues += $values
        }

        $newObject = @()
        $j = 0
        while($j -le $SQLProps.Count){
            $newobj = [pscustomobject]@{Property=$SQLProps[$j].Property;Value=$testValues[$j]}
            $newObject += $newobj
            $j++
        }

        #$newObject
        
        $new = @()

        Foreach($prop in $newObject){
            if($prop.Property -like "*Comment*"){}
            elseif($prop.Property -eq $null){}
            elseif($prop.Property -eq "SQLSVCACCOUNT"){
                $prop.Value = """$SQLSvcAcct"""
                $output = $prop.Property + "=" + $prop.Value
    
                $new += $output
            }
            elseif($prop.Property -eq "SQLSYSADMINACCOUNTS"){
                $prop.Value = """$env:USERDNSDOMAIN\SQL Administrators"""
                $output = $prop.Property + "=" + $prop.Value
    
                $new += $output
            }
            elseif($prop.Property -eq "AGTSVCACCOUNT"){
                $prop.Value = """$SQLSvcAcct"""
                $output = $prop.Property + "=" + $prop.Value
    
                $new += $output
            }
            else{
                $output = $prop.Property + "=" + $prop.Value
    
                $new += $output
        
            }
        }

        "[OPTIONS]">>$outfile
        $new>>$outfile
        #Install SQL on Server

        Enable-WSManCredSSP -Role Client -DelegateComputer $ServerName -Force

        Invoke-Command -ComputerName $ServerName -Verbose -ScriptBlock{ Enable-WSManCredSSP -Role Server -Force} 
        
        $job = Invoke-Command -ComputerName $ServerName -Verbose -ScriptBlock {cmd /c "$Using:SQLSourceDir\setup.exe" /AGTSVCPASSWORD="$Using:SQLSvcAcctPassword" /SQLSVCPASSWORD="$Using:SQLSvcAcctPassword" /ConfigurationFile="$Using:SQLSourceDir\ConfigurationFile.ini"} -AsJob -Authentication Credssp -Credential $DomainCred 

        Wait-Job $job

        #Receive-Job $job

        #Remove-Job $job
        
        # Verify SQL Installed TODO

        #Disable-WSManCredSSP -Role Client

        Invoke-Command -ComputerName $ServerName -ScriptBlock {Disable-WSManCredSSP -Role Server}        
        
        
        #Set SQL Memory

        sleep 120
               
        
        Invoke-Command -ComputerName $ServerName -ScriptBlock {Import-Module sqlps; cd \sql\$Using:ServerName; $svr = Get-Item default; $svr.Configuration.MaxServerMemory.ConfigValue = $Using:MaxSQLMemoryinKB; $svr.Configuration.Alter()}
    
    }

    


    End{}

<#
COMMENTS SECTION

TODO


#>


}

#Build Configuration.ini file
function Get-IniContent{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]$FilePath
        
    )
    $ini = @{}

    switch -Regex -File $filePath{
        "^\[(.+?)\]$"#Section
        {
            $section = $Matches[1]
            $ini[$section]=@{}
            $CommentCount=0
        }
        "^(;.*)$" #Comment
        {
            $value = $Matches[1]
            $CommentCount = $CommentCount + 1
            $name = "Comment" + $CommentCount
            $ini[$section][$name] = $value
        }
        "(.+?)\s*=(.*)"#Key
        {
            $name,$value = $Matches[1..2]
            $ini[$section][$name] = $value
        }
        
    }
    return $ini
}


workflow Build-VirtualServer{
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [String[]]$ServerName,
        [Parameter(Mandatory=$true,Position=1)]
        [string]$Service,
        [Parameter(Mandatory=$true,Position=2)]
        [ValidateSet('South','North')]
        [string]$Site,
        [Parameter(Mandatory=$true,Position=3)]
        [string]$ConfigDataBaseDir,
        [Parameter(Mandatory=$true,Position=4)]
        [string]$SysEngModulePath,
        [Parameter(Position=5)]
        [string]$VMNetwork,
        [Parameter(Position=6)]
        [string]$DataStore,
        [Parameter(Position=7)]
        [Int64]$MemoryGB,
        [Parameter(Position=8)]
        [Int64]$NumCPU,
        [Parameter(Position=9,Mandatory=$true)]
        [switch]$JoinDomain,
        [Parameter(Mandatory=$false,Position=10)]
        [System.Management.Automation.PSCredential]$DomainCredential,
        [Parameter(Mandatory=$false,Position=11)]
        [System.Management.Automation.PSCredential]$LocalCredential,
        [Parameter(Mandatory=$true,Position=12)]
        [switch]$AddDisk,
        [Parameter(Mandatory=$false,Position=13)]
        [Int64[]]$DiskSizeGB,
        [Parameter(Position=14)]
        [ValidateSet('E','F')]
        [string[]]$DriveLetter,
        [Parameter(Position=15)]
        [string[]]$DriveLabel

    )

    
    $ConfigData = Import-LocalizedData -BaseDirectory $ConfigDataBaseDir -FileName "ConfigData.psd1"
    
    # Validate Optional Parameters 

    if($JoinDomain -eq $true){
        if($DomainCredential -eq $null){
            exit 
        }
        elseif($LocalCredential -eq $null){
            exit
        }
        else{
            Write-Output "You have choosen to join the domain."
        }
    }
    if($AddDisk -eq $true){
        if($DiskSizeGB -eq 0){
            exit
        }
        elseif($DriveLetter -eq $null){
            exit
        }
        elseif($DriveLabel -eq $null){
            exit
        }
        else{
            Write-Output "You have choosen to add an additional disk."
        }
    }
    
    # Create Server Objects for Parallel build 
    
    $SetDataStore = ""

    if($DataStore){
        $SetDataStore = $DataStore
    }
    elseif($Site -eq "South" ){
        $SetDataStore = $ConfigData.South.DefaultDataStore
    }
    elseif($Site -eq "North"){
        $SetDataStore = $ConfigData.North.DefaultDataStore
    }

    $SetNetwork = ""
    if($VMNetwork){
        $SetNetwork = $VMNetwork
    }
    elseif($Site -eq "South"){
        $SetNetwork = $ConfigData.South.DefaultNetwork
    }
    elseif($Site -eq "North"){
        $SetNetwork = $ConfigData.North.DefaultNetwork
    }
    $SetNetwork
    
    $Servers = @()

    [Decimal]$SetMemory = $ConfigData.Common.DefaultMemory
    
    if($MemoryGB -ge 1){
        $SetMemory = $MemoryGB
    }

    [Int64]$SetCPU = $ConfigData.Common.DefaultCPU
    
    if($NumCPU -ge 1){
        $SetCPU = $NumCPU
    }

    $Servers = @()

    Foreach($server in $ServerName){
        
        $Servers += [PSCustomObject]@{Name=$server;Folder=$Service;DataStore=$SetDataStore;Site=$Site;Memory=$SetMemory;CPU=$SetCPU;Network=$SetNetwork}

    }

    $Servers
    
    foreach -Parallel($server in $Servers){
        InlineScript{
            $Service = $Using:Service
            $Snapins = Get-PSSnapin

            $ConfigData = $Using:ConfigData
    
            Foreach($snap in $Snapins){
                if($snap.Name -eq "VMWare.VimAutomation.Core"){
                    Write-Output "Snap in already loaded"
                }
                else{
                    Add-PSSnapin "VMWare.VimAutomation.Core"
                       
                    Connect-VIServer ($ConfigData.Nodes.Where{($_.Role -eq "VSphere") -and ($_.ADSite -eq [System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::GetComputerSite().Name)}).NodeName -AllLinked | Out-Null
                }
            
            }
                
            # Check SQL Folder in VSphere
            $BaseFoldS = Get-Folder -Name "vm" -Location "South*"
            $BaseFoldN = Get-Folder -Name "vm" -Location "North*"
            $SqlFolderS = Get-Folder -Name $Service -Location "South*" -ErrorAction SilentlyContinue
            $SqlFolderN = Get-Folder -Name $Service -Location "North*" -ErrorAction SilentlyContinue
            $VMFolderUp = $false
            if($SqlFolderS){
                If($SqlFolderN -ne $null){
                    $VMFolderUp = $true
                }
                else{
                    New-Folder -Name $Service -Location $BaseFoldN
                }
            }
            else{
                New-Folder -Name $Service -Location $BaseFoldS
                if($SqlFolderN -ne $null){
                    $VMFolderUp = $true
                }
                else{
                    New-Folder -Name $Service -Location $BaseFoldN
                    $VMFolderUp = $true 
                }
            }
            
            $ConfigDataBaseDir = $Using:ConfigDataBaseDir
            Import-Module $Using:SysEngModulePath

            Write-Output "Creating VM $($Using:server.Name)"

            New-StandardVM -Name $Using:server.Name `
                           -Folder $Using:server.Folder `
                           -DataStore $Using:server.DataStore `
                           -Site $Using:server.Site `
                           -ConfigDataBaseDirectory $ConfigDataBaseDir `
                           -ConfigDataFileName "ConfigData.psd1" `
                           -Memory $Using:server.Memory `
                           -NumCPUs $Using:server.CPU | Out-Null

            if($Using:JoinDomain){
                Write-Output "Adding NIC"
                Add-StandardVMNetwork -VirtualNetworkName $Using:server.Network `
                                      -VMName $Using:server.Name -DHCP:$true `
                                      -ConfigDataBaseDirectory $ConfigDataBaseDir `
                                      -ConfigDataFileName "ConfigData.psd1" | Out-Null

                Write-Output "Waiting for DNS to Resolve Please be patient."
                while(!(Test-Connection -ComputerName $Using:server.Name -Count 1 -ErrorAction SilentlyContinue)){Sleep 30; ipconfig /flushdns | Out-Null}


                Write-Output "Joining server $($Using:server.Name) to the Domain"
                Set-StandardVM_AD -Service $Using:Service `
                                  -ServerName $Using:server.Name `
                                  -ConfigDataBaseDirectory $ConfigDataBaseDir `
                                  -ConfigDataFileName "ConfigData.psd1" `
                                  -DomainCred $Using:DomainCredential `
                                  -LocalCred $Using:LocalCredential | Out-Null
            }

            if($Using:AddDisk){
                
                while(!(Test-Connection -ComputerName $Using:server.Name -Count 1 -ErrorAction SilentlyContinue)){Sleep 30; ipconfig /flushdns | Out-Null} 
                
                $i = 0

                $DiskSizeGB = $Using:DiskSizeGB
                $DriveLetter = $Using:DriveLetter
                $DriveLabel = $Using:DriveLabel

                Write-Output "Adding Disk/s"

                do{
                    Add-CustomVMDisk -VMName $Using:server.Name `
                                     -DataStore $Using:server.DataStore `
                                     -DiskSize $DiskSizeGB[$i] `
                                     -DriveLetter $DriveLetter[$i] `
                                     -DriveLabel $DriveLabel[$i] `
                                     -ConfigDataBaseDirectory $ConfigDataBaseDir | Out-Null
                    $i++
                }
                while($i -lt $Using:DiskSizeGB.Count)
            }



        }
    }
}