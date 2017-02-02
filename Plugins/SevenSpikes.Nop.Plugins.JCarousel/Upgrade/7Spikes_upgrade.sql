-- 7Spikes upgrade scripts from nopCommerce 3.70 to 3.80

/* =============== Create the entity mapping table =============== */
IF(NOT EXISTS (SELECT NULL FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SS_MAP_EntityMapping]') AND type in (N'U')))
BEGIN
	CREATE TABLE [dbo].[SS_MAP_EntityMapping] (
		[Id]             INT IDENTITY (1, 1) NOT NULL,
		[EntityType]     INT NOT NULL,
		[EntityId]       INT NOT NULL,
		[MappedEntityId] INT NOT NULL,
		[DisplayOrder]   INT NOT NULL,
		[MappingType]    INT NOT NULL,
		PRIMARY KEY CLUSTERED ([Id] ASC)
	);
END

/* =============== Create the entity widget mapping table =============== */  
IF(NOT EXISTS (SELECT NULL FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SS_MAP_EntityWidgetMapping]') AND type in (N'U')))
BEGIN
	CREATE TABLE [dbo].[SS_MAP_EntityWidgetMapping] (
		[Id]           INT            IDENTITY (1, 1) NOT NULL,
		[EntityType]   INT            NOT NULL,
		[EntityId]     INT            NOT NULL,
		[WidgetZone]   NVARCHAR (MAX) NULL,
		[DisplayOrder] INT            NOT NULL,
		PRIMARY KEY CLUSTERED ([Id] ASC)
	);
END

-- Mega Menu plugin - SP for transfering simple settings
IF OBJECT_ID ( 'dbo.MegaMenuTransferSimpleSettings', 'P' ) IS NOT NULL 
DROP PROCEDURE dbo.MegaMenuTransferSimpleSettings;
GO

CREATE PROCEDURE dbo.MegaMenuTransferSimpleSettings ( @SettingName nvarchar(max), @ResourceKey nvarchar(max), @TypeId int, @DefaultTitle nvarchar(max), @DisplayOrder INT OUTPUT, @MenuId INT, @StoreId INT )
AS
	DECLARE @SettingValue NVARCHAR(max)
	SET @SettingValue = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE @SettingName AND StoreId = @StoreId)
	
	IF @SettingValue IS NULL
	BEGIN
		SET @SettingValue = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE @SettingName AND StoreId = 0)
	END
	
	IF LOWER (@SettingValue) = LOWER ('true')
	BEGIN
		-- Get resource value for the language id with the lowest display order as we are setting it as the 'standart' title
		DECLARE @DefaultLanguageId INT
		SET @DefaultLanguageId = (SELECT TOP 1 Id FROM [dbo].[Language] WHERE Published = 1 ORDER BY DisplayOrder ASC)

		DECLARE @DefaultResourceValue NVARCHAR(MAX)
		SET @DefaultResourceValue = (SELECT TOP 1 ResourceValue FROM [LocaleStringResource]
		WHERE LanguageId = @DefaultLanguageId AND [ResourceName] LIKE @ResourceKey)
		
		IF @DefaultResourceValue IS NULL
		BEGIN
			SET @DefaultResourceValue = @DefaultTitle
		END
	
		-- Insert the menu item in the database;
		INSERT INTO [dbo].[SS_MM_MenuItem] (Type, Title, Url, OpenInNewWindow, DisplayOrder, CssClass, MaximumNumberOfEntities, NumberOfBoxesPerRow, CatalogTemplate, ImageSize, EntityId, WidgetZone, Width, ParentMenuItemId, MenuId) VALUES (@TypeId, @DefaultResourceValue, NULL, 0, @DisplayOrder, NULL, 0, 0, 0, 0, 0, NULL, 0, 0, @MenuId)
		 
		DECLARE @LastInsertedMenuItem INT
		SET @LastInsertedMenuItem = (SELECT @@IDENTITY)
		 
		-- Get the rest resource values
		
		DECLARE @LanguageId int
		DECLARE @ResourceName nvarchar(MAX)
		DECLARE @ResourceValue nvarchar(MAX)

		DECLARE LocaleResources CURSOR 
		  LOCAL STATIC READ_ONLY FORWARD_ONLY
		FOR 
		SELECT LanguageId, ResourceName, ResourceValue FROM [LocaleStringResource] AS lsr
		INNER JOIN [Language] AS l ON lsr.LanguageId = l.Id
		WHERE 
			l.Published = 1 AND 
			lsr.Id in ( SELECT MIN(Id) FROM [LocaleStringResource] WHERE [ResourceName] LIKE @ResourceKey AND [LanguageId] != @DefaultLanguageId GROUP BY LanguageId) 
			AND [ResourceName] LIKE @ResourceKey

		OPEN LocaleResources
		FETCH NEXT FROM LocaleResources INTO @LanguageId, @ResourceName, @ResourceValue
		WHILE @@FETCH_STATUS = 0
		BEGIN 
			
			-- If there is no resource value for the current language, let's use the default one.
			IF @ResourceValue IS NULL
			BEGIN
				SET @ResourceValue = @DefaultResourceValue
			END
			
			-- Inserting the localized values for the menu item
			INSERT INTO [dbo].[LocalizedProperty] (EntityId, LanguageId, LocaleKeyGroup, LocaleKey, LocaleValue) VALUES (@LastInsertedMenuItem, @LanguageId, 'MenuItem', 'Title', @ResourceValue)
			
			FETCH NEXT FROM LocaleResources INTO @LanguageId, @ResourceName, @ResourceValue
		END
		CLOSE LocaleResources
		DEALLOCATE LocaleResources

		-- increment the display order each time when we insert a menu item
		SET @DisplayOrder += 1;
	END
GO

-- Mega Menu plugin - SP for transfering category settings
IF OBJECT_ID ( 'dbo.MegaMenuTransferCategorySettings', 'P' ) IS NOT NULL 
DROP PROCEDURE dbo.MegaMenuTransferCategorySettings;
GO

CREATE PROCEDURE dbo.MegaMenuTransferCategorySettings ( @DisplayOrder INT OUTPUT, @MenuId INT, @StoreId INT )
AS
	DECLARE @SettingValue NVARCHAR(max)
	SET @SettingValue = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.enablecategories' AND StoreId = @StoreId)
	
	IF @SettingValue IS NULL
	BEGIN
		SET @SettingValue = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.enablecategories' AND StoreId = 0)
	END
	
	IF LOWER (@SettingValue) = LOWER ('true')
	BEGIN
		DECLARE @DefaultResourceValue NVARCHAR(MAX)
		SET @DefaultResourceValue = (SELECT TOP 1 [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.menuitemname' AND StoreId = @StoreId)
		
		IF @DefaultResourceValue IS NULL
		BEGIN
			SET @DefaultResourceValue = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.menuitemname' AND StoreId = 0)
		END
		
		IF @DefaultResourceValue IS NULL
		BEGIN
			SET @DefaultResourceValue = 'Products'
		END

		DECLARE @CatalogTemplate INT

		-- Get the category template
		DECLARE @CatalogTemplateAsString NVARCHAR(max)
		SET @CatalogTemplateAsString = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.megamenucategorytemplate' AND StoreId = @StoreId)
		
		IF @CatalogTemplateAsString IS NULL
		BEGIN
			SET @CatalogTemplateAsString = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.megamenucategorytemplate' AND StoreId = 0)
		END
		
		IF @CatalogTemplateAsString = 'CategoryMenuTemplate.WithPictures'
			SET @CatalogTemplate = 5
		ELSE
			SET @CatalogTemplate = 10
		
		-- Get the number of boxes per row
		DECLARE @NumberOfBoxesPerRow INT
		SET @NumberOfBoxesPerRow = (SELECT CAST([Value] AS INT) FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.numberofcategoriesperrow' AND StoreId = @StoreId)
		
		IF @NumberOfBoxesPerRow IS NULL
		BEGIN
			SET @NumberOfBoxesPerRow = (SELECT ISNULL((SELECT CAST([Value] AS INT) FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.numberofcategoriesperrow' AND StoreId = 0), '4'))
		END
		
		-- Get the category image size
		DECLARE @ImageSize INT
		SET @ImageSize = (SELECT CAST([Value] AS INT) FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.categoriesimagesize' AND StoreId = @StoreId)
		
		IF @ImageSize IS NULL
		BEGIN
			SET @ImageSize = (SELECT ISNULL((SELECT CAST([Value] AS INT) FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.categoriesimagesize' AND StoreId = 0), '290'))
		END
		
		-- Get the maximum number of categories
		DECLARE @MaximumNumberOfEntities INT
		SET @MaximumNumberOfEntities = (SELECT CAST([Value] AS INT) FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.numberofcategories' AND StoreId = @StoreId)
		
		IF @MaximumNumberOfEntities IS NULL
		BEGIN
			SET @MaximumNumberOfEntities = (SELECT ISNULL((SELECT CAST([Value] AS INT) FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.numberofcategories' AND StoreId = 0), '8'))
		END
		
		-- Get the show categories in a single item
		DECLARE @ShowCategoriesInASingleMenu NVARCHAR(max)
		SET @ShowCategoriesInASingleMenu = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.showcategoriesinasinglemenuitem' AND StoreId = @StoreId)
			
		IF @ShowCategoriesInASingleMenu IS NULL
		BEGIN
			SET @ShowCategoriesInASingleMenu = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.showcategoriesinasinglemenuitem' AND StoreId = 0)
		END
			
		IF LOWER (@ShowCategoriesInASingleMenu) = LOWER ('true')
		BEGIN
			-- Insert the menu item in the database;
			INSERT INTO [dbo].[SS_MM_MenuItem] (Type, Title, Url, OpenInNewWindow, DisplayOrder, CssClass, MaximumNumberOfEntities, NumberOfBoxesPerRow, CatalogTemplate, ImageSize, EntityId, WidgetZone, Width, ParentMenuItemId, MenuId) VALUES (0, @DefaultResourceValue, NULL, 0, @DisplayOrder, NULL, @MaximumNumberOfEntities, @NumberOfBoxesPerRow, @CatalogTemplate, @ImageSize, 0, NULL, 0, 0, @MenuId)
		
			-- increment the display order each time when we insert a menu item
			SET @DisplayOrder += 1;
		END
		ELSE
		BEGIN
			DECLARE @CategoryId int
			DECLARE @CategoryName nvarchar(MAX)

			DECLARE TopLevelCategories CURSOR 
			  LOCAL STATIC READ_ONLY FORWARD_ONLY
			FOR 
			SELECT Id, Name FROM [Category]
			WHERE 
				Published = 1 AND 
				IncludeInTopMenu = 1 AND 
				Deleted = 0 AND
				ParentCategoryId = 0
				AND 
				(	
					LimitedToStores = 0 OR EXISTS (
					SELECT 1 FROM [StoreMapping] sm with (NOLOCK)
					WHERE [sm].EntityId = Id AND [sm].EntityName = 'Category' and [sm].StoreId = CAST(@StoreId AS nvarchar(max))
				))
			ORDER BY DisplayOrder ASC

			OPEN TopLevelCategories
			FETCH NEXT FROM TopLevelCategories INTO @CategoryId, @CategoryName
			WHILE @@FETCH_STATUS = 0
			BEGIN 
				
				-- Insert the menu item in the database;
				INSERT INTO [dbo].[SS_MM_MenuItem] (Type, Title, Url, OpenInNewWindow, DisplayOrder, CssClass, MaximumNumberOfEntities, NumberOfBoxesPerRow, CatalogTemplate, ImageSize, EntityId, WidgetZone, Width, ParentMenuItemId, MenuId) VALUES (0, @CategoryName, NULL, 0, @DisplayOrder, NULL, @MaximumNumberOfEntities, @NumberOfBoxesPerRow, @CatalogTemplate, @ImageSize, @CategoryId, NULL, 0, 0, @MenuId)
			
				-- increment the display order each time when we insert a menu item
				SET @DisplayOrder += 1;
				
				FETCH NEXT FROM TopLevelCategories INTO @CategoryId, @CategoryName
			END
			CLOSE TopLevelCategories
			DEALLOCATE TopLevelCategories
		END
	END
GO

-- Mega Menu plugin - SP for transfering manufacturer settings
IF OBJECT_ID ( 'dbo.MegaMenuTransferManufacturerSettings', 'P' ) IS NOT NULL 
DROP PROCEDURE dbo.MegaMenuTransferManufacturerSettings;
GO

CREATE PROCEDURE dbo.MegaMenuTransferManufacturerSettings ( @DisplayOrder INT OUTPUT, @MenuId INT, @StoreId INT )
AS
	DECLARE @SettingValue NVARCHAR(max)
	SET @SettingValue = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.enablemanufacturers' AND StoreId = @StoreId)
	
	IF @SettingValue IS NULL
	BEGIN
		SET @SettingValue = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.enablemanufacturers' AND StoreId = 0)
	END
	
	IF LOWER (@SettingValue) = LOWER ('true')
	BEGIN
		DECLARE @DefaultResourceValue NVARCHAR(MAX)
		SET @DefaultResourceValue = (SELECT TOP 1 [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.manufacturersitemname' AND StoreId = @StoreId)
		
		IF @DefaultResourceValue IS NULL
		BEGIN
			SET @DefaultResourceValue = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.manufacturersitemname' AND StoreId = 0)
		END
		
		IF @DefaultResourceValue IS NULL
		BEGIN
			SET @DefaultResourceValue = 'Manufacturers'
		END
			
		DECLARE @CatalogTemplate INT

		-- Get the manufacturers template
		DECLARE @CatalogTemplateAsString NVARCHAR(max)
		SET @CatalogTemplateAsString = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.megamenumanufacturertemplate' AND StoreId = @StoreId)
		
		IF @CatalogTemplateAsString IS NULL
		BEGIN
			SET @CatalogTemplateAsString = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.megamenumanufacturertemplate' AND StoreId = 0)
		END
		
		IF @CatalogTemplateAsString = 'ManufacturerMenuTemplate.WithPictures'
			SET @CatalogTemplate = 5
		ELSE
			SET @CatalogTemplate = 10
		
		-- Get the number of boxes per row
		DECLARE @NumberOfBoxesPerRow INT
		SET @NumberOfBoxesPerRow = (SELECT CAST([Value] AS INT) FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.numberofmanufacturersperrow' AND StoreId = @StoreId)
		
		IF @NumberOfBoxesPerRow IS NULL
		BEGIN
			SET @NumberOfBoxesPerRow = (SELECT ISNULL((SELECT CAST([Value] AS INT) FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.numberofmanufacturersperrow' AND StoreId = 0), '6'))
		END
		
		-- Get the manufacturer image size
		DECLARE @ImageSize INT
		SET @ImageSize = (SELECT CAST([Value] AS INT) FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.manufacturerimagesize' AND StoreId = @StoreId)
		
		IF @ImageSize IS NULL
		BEGIN
			SET @ImageSize = (SELECT ISNULL((SELECT CAST([Value] AS INT) FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.manufacturerimagesize' AND StoreId = 0), '165'))
		END
		
		-- Get the maximum number of manufacturers
		DECLARE @MaximumNumberOfEntities INT
		SET @MaximumNumberOfEntities = (SELECT CAST([Value] AS INT) FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.numberofmanufacturers' AND StoreId = @StoreId)
	
		IF @MaximumNumberOfEntities IS NULL
		BEGIN
			SET @MaximumNumberOfEntities = (SELECT ISNULL((SELECT CAST([Value] AS INT) FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.numberofmanufacturers' AND StoreId = 0), '10'))
		END
	
		-- Insert the menu item in the database;
		INSERT INTO [dbo].[SS_MM_MenuItem] (Type, Title, Url, OpenInNewWindow, DisplayOrder, CssClass, MaximumNumberOfEntities, NumberOfBoxesPerRow, CatalogTemplate, ImageSize, EntityId, WidgetZone, Width, ParentMenuItemId, MenuId) VALUES (20, @DefaultResourceValue, NULL, 0, @DisplayOrder, NULL, @MaximumNumberOfEntities, @NumberOfBoxesPerRow, @CatalogTemplate, @ImageSize, 0, NULL, 0, 0, @MenuId)

		-- increment the display order each time when we insert a menu item
		SET @DisplayOrder += 1;
	END
GO

-- Mega Menu plugin - SP for transfering vendor settings
IF OBJECT_ID ( 'dbo.MegaMenuTransferVendorSettings', 'P' ) IS NOT NULL 
DROP PROCEDURE dbo.MegaMenuTransferVendorSettings;
GO

CREATE PROCEDURE dbo.MegaMenuTransferVendorSettings ( @DisplayOrder INT OUTPUT, @MenuId INT, @StoreId INT )
AS
	DECLARE @SettingValue NVARCHAR(max)
	SET @SettingValue = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.enablevendors' AND StoreId = @StoreId)
	
	IF @SettingValue IS NULL
	BEGIN
		SET @SettingValue = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.enablevendors' AND StoreId = 0)
	END
	
	IF LOWER (@SettingValue) = LOWER ('true')
	BEGIN
		DECLARE @DefaultResourceValue NVARCHAR(MAX)
		SET @DefaultResourceValue = (SELECT TOP 1 [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.vendorscolumnname' AND StoreId = @StoreId)
		
		IF @DefaultResourceValue IS NULL
		BEGIN
			SET @DefaultResourceValue = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.vendorscolumnname' AND StoreId = 0)
		END
		
		IF @DefaultResourceValue IS NULL
		BEGIN
			SET @DefaultResourceValue = 'Vendors'
		END
			
		-- Get the catalog template
		DECLARE @CatalogTemplate INT
		SET @CatalogTemplate = 10
		
		-- Get the number of boxes per row
		DECLARE @NumberOfBoxesPerRow INT
		SET @NumberOfBoxesPerRow = 6
		
		-- Get the image size
		DECLARE @ImageSize INT
		SET @ImageSize = 90
		
		-- Get the maximum number of categories
		DECLARE @MaximumNumberOfEntities INT
		SET @MaximumNumberOfEntities = (SELECT CAST([Value] AS INT) FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.numberofvendors' AND StoreId = @StoreId)
		
		IF @MaximumNumberOfEntities IS NULL
		BEGIN
			SET @MaximumNumberOfEntities = (SELECT ISNULL((SELECT CAST([Value] AS INT) FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.numberofvendors' AND StoreId = 0), '10'))
		END
	
		-- Insert the menu item in the database;
		INSERT INTO [dbo].[SS_MM_MenuItem] (Type, Title, Url, OpenInNewWindow, DisplayOrder, CssClass, MaximumNumberOfEntities, NumberOfBoxesPerRow, CatalogTemplate, ImageSize, EntityId, WidgetZone, Width, ParentMenuItemId, MenuId) VALUES (30, @DefaultResourceValue, NULL, 0, @DisplayOrder, NULL, @MaximumNumberOfEntities, @NumberOfBoxesPerRow, @CatalogTemplate, @ImageSize, 0, NULL, 0, 0, @MenuId)

		-- increment the display order each time when we insert a menu item
		SET @DisplayOrder += 1;
	END
GO

-- Create the [SS_MM_Menu] table if not exists
BEGIN TRANSACTION;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN

	IF(NOT EXISTS (SELECT NULL FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SS_MM_Menu]')))
	BEGIN
		SET ANSI_NULLS ON;

		SET QUOTED_IDENTIFIER ON;

		CREATE TABLE [dbo].[SS_MM_Menu](
			[Id] [int] IDENTITY(1,1) NOT NULL,
			[Enabled] [bit] NOT NULL,
			[Name] [nvarchar](max) NULL,
			[CssClass] [nvarchar](max) NULL,
			[ShowDropdownsOnClick] [bit] NOT NULL,
			[LimitedToStores] [bit] NOT NULL,
		PRIMARY KEY CLUSTERED 
		(
			[Id] ASC
		)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
		) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
	END

END
COMMIT TRANSACTION;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- Create the [SS_MM_MenuItem] table if not exists
BEGIN TRANSACTION;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN

	IF(NOT EXISTS (SELECT NULL FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SS_MM_MenuItem]')))
	BEGIN
		SET ANSI_NULLS ON;

		SET QUOTED_IDENTIFIER ON;

		CREATE TABLE [dbo].[SS_MM_MenuItem](
			[Id] [int] IDENTITY(1,1) NOT NULL,
			[Type] [int] NOT NULL,
			[Title] [nvarchar](max) NULL,
			[Url] [nvarchar](max) NULL,
			[OpenInNewWindow] [bit] NOT NULL,
			[DisplayOrder] [int] NOT NULL,
			[CssClass] [nvarchar](max) NULL,
			[MaximumNumberOfEntities] [int] NOT NULL,
			[NumberOfBoxesPerRow] [int] NOT NULL,
			[CatalogTemplate] [int] NOT NULL,
			[ImageSize] [int] NOT NULL,
			[EntityId] [int] NOT NULL,
			[WidgetZone] [nvarchar](max) NULL,
			[Width] [decimal](18, 2) NOT NULL,
			[ParentMenuItemId] [int] NOT NULL,
			[MenuId] [int] NULL,
		PRIMARY KEY CLUSTERED 
		(
			[Id] ASC
		)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
		) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
	END

END
COMMIT TRANSACTION;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- Insert the records
BEGIN TRANSACTION;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN
	-- If the table exists and there are no rows in it, we should start transfering the settings.
	IF(EXISTS (SELECT NULL FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SS_MM_MenuItem]')) AND NOT EXISTS (SELECT Id FROM [dbo].[SS_MM_MenuItem]))
	BEGIN
	
		DECLARE @StoreId int
		DECLARE @StoreName nvarchar(MAX)

		DECLARE AlLStores CURSOR 
		  LOCAL STATIC READ_ONLY FORWARD_ONLY
		FOR 
		SELECT Id, Name FROM [Store]
		ORDER BY DisplayOrder ASC

		OPEN AlLStores
		FETCH NEXT FROM AlLStores INTO @StoreId, @StoreName
		WHILE @@FETCH_STATUS = 0
		BEGIN 
		
			INSERT INTO [dbo].[SS_MM_Menu] (Enabled, Name, CssClass, ShowDropdownsOnClick, LimitedToStores) VALUES ('True', 'Mega Menu' + @StoreName, '', 'False', 'True')
			
			-- Get the last inserted menu id
			DECLARE @LastInsertedMenu INT
			SET @LastInsertedMenu = (SELECT @@IDENTITY)
			
			INSERT INTO [dbo].[StoreMapping] (EntityId, EntityName, StoreId) VALUES (@LastInsertedMenu, 'Menu', @StoreId)
			
			-- Set DisplayOrder of items to be 0 by default
			DECLARE @DisplayOrder INT
			SET @DisplayOrder = 0
			
			-- Include Home Page Link
			EXEC dbo.MegaMenuTransferSimpleSettings @SettingName = 'megamenusettings.includehomepagelink', @ResourceKey = 'HomePage', @TypeId = 300, @DefaultTitle = 'Home page', @DisplayOrder = @DisplayOrder OUTPUT, @MenuId = @LastInsertedMenu, @StoreId = @StoreId
			
			-- Include Categories
			EXEC dbo.MegaMenuTransferCategorySettings @DisplayOrder = @DisplayOrder OUTPUT, @MenuId = @LastInsertedMenu, @StoreId = @StoreId
			
			-- Include Manufacturers
			EXEC dbo.MegaMenuTransferManufacturerSettings @DisplayOrder = @DisplayOrder OUTPUT, @MenuId = @LastInsertedMenu, @StoreId = @StoreId
			
			-- Include Vendors
			EXEC dbo.MegaMenuTransferVendorSettings @DisplayOrder = @DisplayOrder OUTPUT, @MenuId = @LastInsertedMenu, @StoreId = @StoreId
			
			-- Include New Products Link
			EXEC dbo.MegaMenuTransferSimpleSettings @SettingName = 'megamenusettings.includerecentlyaddedlink', @ResourceKey = 'Products.NewProducts', @TypeId = 315, @DefaultTitle = 'New products', @DisplayOrder = @DisplayOrder OUTPUT, @MenuId = @LastInsertedMenu, @StoreId = @StoreId
			
			-- Include My Account Link
			EXEC dbo.MegaMenuTransferSimpleSettings @SettingName = 'megamenusettings.includemyaccountlink', @ResourceKey = 'Account.MyAccount', @TypeId = 305, @DefaultTitle = 'My account', @DisplayOrder = @DisplayOrder OUTPUT, @MenuId = @LastInsertedMenu, @StoreId = @StoreId

			-- Include Contanct Us Link
			EXEC dbo.MegaMenuTransferSimpleSettings @SettingName = 'megamenusettings.includecontactuslink', @ResourceKey = 'ContactUs', @TypeId = 310, @DefaultTitle = 'Contact us', @DisplayOrder = @DisplayOrder OUTPUT, @MenuId = @LastInsertedMenu, @StoreId = @StoreId
			
			-- Include Blog Link
			EXEC dbo.MegaMenuTransferSimpleSettings @SettingName = 'megamenusettings.includebloglink', @ResourceKey = 'Blog', @TypeId = 320, @DefaultTitle = 'Blog', @DisplayOrder = @DisplayOrder OUTPUT, @MenuId = @LastInsertedMenu, @StoreId = @StoreId
			
			-- Include News Link
			EXEC dbo.MegaMenuTransferSimpleSettings @SettingName = 'megamenusettings.includenewslink', @ResourceKey = 'News', @TypeId = 325, @DefaultTitle = 'News', @DisplayOrder = @DisplayOrder OUTPUT, @MenuId = @LastInsertedMenu, @StoreId = @StoreId
			
			-- Include Forum Link
			EXEC dbo.MegaMenuTransferSimpleSettings @SettingName = 'megamenusettings.includeforumlink', @ResourceKey = 'Forum.Forums', @TypeId = 330, @DefaultTitle = 'Forums', @DisplayOrder = @DisplayOrder OUTPUT, @MenuId = @LastInsertedMenu, @StoreId = @StoreId
			
			-- Move sticky category
			DECLARE @StickyCategory NVARCHAR(max)
			SET @StickyCategory = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.stickycategoryid' AND StoreId = @StoreId)

			IF @StickyCategory IS NULL
			BEGIN
				-- if we do not find a store specific setting, set the store id to 0 and search again...
				SET @StoreId = 0
				
				SET @StickyCategory = (SELECT [Value] FROM [dbo].[Setting] WHERE Name LIKE 'megamenusettings.stickycategoryid' AND StoreId = @StoreId)
			END
			
			IF @StickyCategory IS NOT NULL
			BEGIN
				DECLARE @StickyCategoryId INT
				SET @StickyCategoryId = (SELECT CAST(@StickyCategory AS INT))
				
				IF @StickyCategoryId > 0
				BEGIN
					DECLARE @CategoryName NVARCHAR(MAX)
					SET @CategoryName = (SELECT Name FROM [dbo].[Category] WHERE Id = @StickyCategoryId AND ( LimitedToStores = 0 OR EXISTS (SELECT 1 FROM [StoreMapping] sm with (NOLOCK) WHERE [sm].EntityId = Id AND [sm].EntityName = 'Category' and [sm].StoreId = CAST(@StoreId AS nvarchar(max)))))
					
					-- Insert the menu item in the database;
					INSERT INTO [dbo].[SS_MM_MenuItem] (Type, Title, Url, OpenInNewWindow, DisplayOrder, CssClass, MaximumNumberOfEntities, NumberOfBoxesPerRow, CatalogTemplate, ImageSize, EntityId, WidgetZone, Width, ParentMenuItemId, MenuId) VALUES (0, @CategoryName, NULL, 0, @DisplayOrder, NULL, 0, 0, 0, 0, @StickyCategoryId, NULL, 0, 0, @LastInsertedMenu)
					
					-- increment the display order each time when we insert a menu item
					SET @DisplayOrder += 1;
				END
			END
			
			-- Create widget mapping
			INSERT INTO [dbo].[SS_MAP_EntityWidgetMapping] (EntityType, EntityId, WidgetZone, DisplayOrder) VALUES (60, @LastInsertedMenu, 'theme_header_menu', 0)
			
			FETCH NEXT FROM AlLStores INTO @StoreId, @StoreName
		END
		CLOSE AlLStores
		DEALLOCATE AlLStores
	END
END
COMMIT TRANSACTION;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

IF OBJECT_ID ( 'dbo.MegaMenuTransferSimpleSettings', 'P' ) IS NOT NULL 
EXEC('DROP PROCEDURE dbo.MegaMenuTransferSimpleSettings;');

IF OBJECT_ID ( 'dbo.MegaMenuTransferCategorySettings', 'P' ) IS NOT NULL 
EXEC('DROP PROCEDURE dbo.MegaMenuTransferCategorySettings;');

IF OBJECT_ID ( 'dbo.MegaMenuTransferManufacturerSettings', 'P' ) IS NOT NULL 
EXEC('DROP PROCEDURE dbo.MegaMenuTransferManufacturerSettings;');

IF OBJECT_ID ( 'dbo.MegaMenuTransferVendorSettings', 'P' ) IS NOT NULL 
EXEC('DROP PROCEDURE dbo.MegaMenuTransferVendorSettings;');