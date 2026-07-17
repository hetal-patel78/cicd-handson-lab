-- Database initialization script
-- Mirrors the DACPAC deployment in production
-- In your company, the DACPAC is built from a SQL Server Data Tools project
-- and deployed via SqlPackage.exe during Octopus deployments

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'MySubscriptionService')
BEGIN
    CREATE DATABASE [MySubscriptionService];
END
GO

USE [MySubscriptionService];
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Subscriptions')
BEGIN
    CREATE TABLE [dbo].[Subscriptions] (
        [Id]           UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        [CustomerName] NVARCHAR(200)    NOT NULL,
        [Email]        NVARCHAR(200)    NOT NULL,
        [Plan]         NVARCHAR(50)     NOT NULL,
        [Amount]       DECIMAL(18,2)    NOT NULL,
        [CreatedAt]    DATETIME2        NOT NULL DEFAULT GETUTCDATE(),
        [IsActive]     BIT              NOT NULL DEFAULT 1,
        [UpdatedAt]    DATETIME2        NULL
    );
    PRINT '>>> Table [Subscriptions] created';
END
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'SubscriptionEvents')
BEGIN
    CREATE TABLE [dbo].[SubscriptionEvents] (
        [Id]             UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        [SubscriptionId] UNIQUEIDENTIFIER NOT NULL,
        [EventType]      NVARCHAR(50)     NOT NULL,
        [EventData]      NVARCHAR(MAX)    NULL,
        [CreatedAt]      DATETIME2        NOT NULL DEFAULT GETUTCDATE(),
        CONSTRAINT [FK_SubscriptionEvents_Subscriptions]
            FOREIGN KEY ([SubscriptionId]) REFERENCES [dbo].[Subscriptions]([Id])
    );
    PRINT '>>> Table [SubscriptionEvents] created';
END
GO

PRINT '>>> Database initialization complete';
GO