ALTER DATABASE [<%= @db_name%>] SET RECOVERY FULL
GO

BACKUP DATABASE [<%= @db_name%>] 
TO DISK = N'<%= @backup_name%>.bak'
    WITH NOFORMAT,
    NOINIT,
    NAME = N'<%= @db_name%>-Full DB backup%>',
    SKIP,
    NOREWIND,
    NOUNLOAD,
    STATS = 10
GO

BACKUP LOG [<%= @db_name%>]
TO DISK = N'<%= @backup_name%>_log.trn'
    WITH NOFORMAT,
    NOINIT,
    NOSKIP,
    REWIND,
    NOUNLOAD,
    COMPRESSION,
    STATS = 5
GO

USE [master]

GO

ALTER AVAILABILITY GROUP [<%= @avail_group_name %>]
ADD DATABASE [<%= @db_name%>]

GO