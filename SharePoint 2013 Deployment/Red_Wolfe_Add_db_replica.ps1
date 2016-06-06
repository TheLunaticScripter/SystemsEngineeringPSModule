Function Add-DBDAG{
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$ServerName,
        [Parameter(Mandatory=$true)]
        [string]$DAGName,
        [Parameter(Mandatory=$true)]
        [string]$DBSearchNameStandard,
        [Parameter(Mandatory=$true)]
        [string]$BackupShare,
        [Parameter(Mandatory=$true)]
        [string]$SqlCmdsDir
    )
    
    $orig_backup_file = "$SqlCmdsDir\Red_Wolfe_backup_db.sql"
    $orig_add_db_file = "$SqlCmdsDir\Red_Wolfe_add_db_replica.sql"
    
    Import-Module 'C:\Program Files (x86)\Microsoft SQL Server\110\Tools\PowerShell\Modules\SQLPS'
    
    $databases = Invoke-Sqlcmd -Query "SELECT name FROM master.dbo.sysdatabases WHERE name NOT IN ('master','tempdb','model','msdb','SP13_UsageApplication') AND name NOT IN (SELECT database_name FROM sys.availability_databases_cluster)"
    
    #$otherdbs = Invoke-Sqlcmd -Query "SELECT database_name FROM sys.availability_databases_cluster"

    
    foreach($db in $databases){
        if($db.Name -like "*$DBSearchNameStandard*"){
            Write-Output "Adding $($db.Name) to dag"
            ""
            $scriptPath = Get-Item  FileSystem::"$BackupShare\Scripts"
            If($scriptPath -eq $null){
                New-Item -ItemType Directory -Name "Scripts" -Path $BackupShare
            }
            cd c:\
            New-Item -ItemType file -Name "$($db.Name)_db_backup.sql" -Path FileSystem::"$BackupShare\Scripts"
            New-Item -ItemType file -Name "$($db.Name)_add_db_replica.sql" -Path FileSystem::"$BackupShare\Scripts"
            Write-Output "Starting backup of database " $db.Name ". . ."
            $backupName = $db.Name + "_" + (Get-Date -UFormat "%Y%m%d%H%M%S").ToString()
            (Get-Content FileSystem::$orig_backup_file) | Foreach-Object {
                $_ -replace '<%= @db_name%>', $db.Name `
                   -replace '<%= @backup_name%>', "$BackupShare\$backupName" `
                   -replace '<%= @avail_group_name %>', $DAGName
            } | Set-Content "$BackupShare\Scripts\$($db.Name)_db_backup.sql"
            Invoke-Sqlcmd -InputFile "$BackupShare\Scripts\$($db.Name)_db_backup.sql" -ServerInstance $env:COMPUTERNAME
            
            Write-Output "Restoring db to Replica server $ServerName . . . "
            foreach($server in $ServerName){
                (Get-Content FileSystem::$orig_add_db_file) | Foreach-Object {
                    $_ -replace '<%= @backup_name%>', "$BackupShare\$backupName" `
                       -replace '<%= @db_name%>', $db.Name `
                       -replace '<%= @avail_group_name %>', $DAGName
                } | Set-Content "$BackupShare\Scripts\$($db.Name)_add_db_replica.sql"
                Invoke-Sqlcmd -InputFile "$BackupShare\Scripts\$($db.Name)_add_db_replica.sql" -ServerInstance $server
            }
        }
    }
    
}