
CREATE DATABASE [TempSPDb]

GO

ALTER DATABASE [TempSPDb] SET RECOVERY FULL

GO

CREATE DATABASE [TempSenDB]

GO

ALTER DATABASE [TempSenDB] SET RECOVERY Full

GO

BACKUP DATABASE [TempSPDb]
TO DISK = N'F:\Backups\TempSPdbFull.bak'
    WITH NOFORMAT,
    NOINIT, 
    NAME = N'TempSPDb-Full Database Backup', 
    SKIP, 
    NOREWIND, 
    NOUNLOAD, 
    STATS = 10
GO

BACKUP DATABASE [TempSenDb]
TO DISK = N'F:\Backups\TempSendbFull.bak'
    WITH NOFORMAT,
    NOINIT, 
    NAME = N'TempSenDb-Full Database Backup', 
    SKIP, 
    NOREWIND, 
    NOUNLOAD, 
    STATS = 10
GO

