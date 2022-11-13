
-- Show basic use of SQL Statements based on the available database

-- How many monthly complaints did Wells Fargo & Company have in 2014 showing from highest to lowest when there
-- were more than 200 complaints.

SELECT 
	 [Company]
	,YEAR([Date Received]) AS [Year Received]
	,DATENAME(MONTH, [Date Received]) AS [Month Received]
	,COUNT([Complaint ID]) AS [Complaints]
FROM [ConsumerComplaints].[sql_projects].[Consumer_Complaints_Table]
WHERE Company = N'Wells Fargo & Company' AND YEAR([Date Received]) = '2014'
GROUP BY Company, YEAR([Date Received]), DATENAME(MONTH, [Date Received])
HAVING COUNT([Complaint ID]) > 200
ORDER BY [Complaints] DESC

-- This question shows the application of joins


-- What product, sub category and issue combinations where the sub category is NULL.

SELECT

	 p.[Product Name]
	,ISNULL(p.[Sub Product], N'No Sub Category') [Sub Category]
	,i.[Issue]
	,COUNT(c.[Complaint ID]) AS [Total]
	
FROM [ConsumerComplaints].[sql_projects].[Consumer_Complaints_Table] AS c
LEFT OUTER JOIN [ConsumerComplaints].[sql_projects].[Issue_Table] AS i
	ON i.Issue_Code = c.Issue_Code 
LEFT OUTER JOIN [ConsumerComplaints].[sql_projects].[Product_Table] AS p
	ON p.Product_ID = c.Product_ID
WHERE p.[Sub Product] IS NULL
GROUP BY p.[Product Name], p.[Sub Product], i.[Issue]
ORDER BY Total DESC

--Which areas have the highest fee related sub issues

SELECT TOP 3
	COALESCE(i.[Sub Issue], i.[Issue]) AS [Sub Issue]
	,k.[State Name]
	,CASE
		WHEN k.[Zip Code] IS NULL THEN ISNULL(k.[Zip Code], '00000')
		WHEN LEN(k.[Zip Code]) <> 5 THEN 'Incomplete Code'
		ELSE k.[Zip Code]
	END [Zip Code]
	,COUNT(c.[Complaint ID]) AS Total
FROM [ConsumerComplaints].[sql_projects].[Consumer_Complaints_Table] AS c
LEFT OUTER JOIN [ConsumerComplaints].[sql_projects].[Issue_Table] AS i
	ON i.Issue_Code = c.Issue_Code 
LEFT OUTER JOIN [ConsumerComplaints].[sql_projects].[Location_Table] AS k
	ON k.Location_Key = c.Location_Key
WHERE i.[Issue] LIKE '%fee%'
GROUP BY COALESCE(i.[Sub Issue], i.[Issue]), k.[State Name], [Zip Code]
ORDER BY Total DESC 

-- Application of subqueries 

-- Which companies had potentially the worst costly resolution experience where there was monetary relief, late responses
-- and the customer still disputed.

SELECT 
	  c.[Company]
	 ,COUNT(c.[Complaint ID]) AS Complaints
FROM [ConsumerComplaints].[sql_projects].[Consumer_Complaints_Table] AS c
WHERE EXISTS
	( SELECT *
	  FROM [ConsumerComplaints].[sql_projects].[Resolution_Table] AS r 
	  WHERE r.[Complaint ID] = c.[Complaint ID]
	  AND r.[Company Response to Consumer] = 'Closed with monetary relief'
	  AND r.[Timely Response] = 'No'
	  AND r.[Consumer Disputed] = 'No'
	)
GROUP BY c.[Company]
ORDER BY Complaints DESC


-- show customer IDs on rows, shipper IDs on columns, total freight in intersection
DECLARE @TotalRows INT
SELECT @TotalRows = COUNT(1) FROM [ConsumerComplaints].[sql_projects].[Consumer_Complaints_Table];

WITH PivotTable AS
(
  SELECT
    c.[Submitted via],    
    r.[Company Response to Consumer],
	c.[Complaint ID]    
  FROM [ConsumerComplaints].[sql_projects].[Consumer_Complaints_Table] AS c
  LEFT OUTER JOIN [ConsumerComplaints].[sql_projects].[Resolution_Table] AS r 
					ON r.[Complaint ID] = c.[Complaint ID]
)
SELECT [Submitted via], [Closed with explanation], [Closed], [Closed with non-monetary relief],
		[Closed with monetary relief], [Untimely response]
FROM PivotTable
  PIVOT(COUNT([Complaint ID]) FOR [Company Response to Consumer] IN ( [Closed with explanation], [Closed],
				[Closed with non-monetary relief], [Closed with monetary relief], [Untimely response] ) ) AS p;

--What are running totals of complaints for Bank of America, Experian, Equifax for the first three months of 2015

WITH IssuesTable AS
(
	SELECT
		 c.[Company]
		,EOMONTH(c.[Date Received]) AS [Month End]
		,COUNT(c.[Complaint ID]) AS [Total]
	FROM [ConsumerComplaints].[sql_projects].[Consumer_Complaints_Table] AS c
	LEFT OUTER JOIN [ConsumerComplaints].[sql_projects].[Issue_Table] AS i
		ON i.Issue_Code = c.Issue_Code 
	WHERE YEAR(c.[Date Received]) = '2015'
	AND c.[Company] IN ('Bank of America', 'Experian', 'Equifax') 
	GROUP BY c.[Company], EOMONTH(c.[Date Received])
)
SELECT 
	 [Company]
	,[Month End]
	,[Total]
    ,SUM([Total]) OVER(PARTITION BY [Company]
                  ORDER BY [Month End]
                  ROWS BETWEEN UNBOUNDED PRECEDING
                           AND CURRENT ROW) AS [Running Total]
FROM IssuesTable


--What are the average number of days between the complaint being received and being forwarded to the company.
-- The solution should be a resusable function which has the company name as the parameter. This solution is achieved
-- using a scalar user-defined function.
CREATE OR ALTER FUNCTION [sql_projects].[Days_Between_Complaints](@company AS NVARCHAR(70))
  RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
  DECLARE @averagedays AS INT;
  WITH ComplaintsDaysCTE AS
  (
	SELECT
		DATEDIFF(DAY, c.[Date Received], c.[Date Sent to Company]) AS [Days Between]
    FROM [sql_projects].[Consumer_Complaints_Table] c
	WHERE c.[Company] = @company
  )
  SELECT 
	@averagedays = AVG([Days Between])
  FROM ComplaintsDaysCTE;
  RETURN @averagedays;
END;
GO

--Execute and scalar function
SELECT [sql_projects].[Days_Between_Complaints](N'JPMorgan Chase & Co.') AS [Average Days];
GO


--How can one explore the data through paging using inline table-valued functions?
CREATE OR ALTER FUNCTION [sql_projects].[Paging_Function](@pagenum AS INT, @pagesize AS INT)
	RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
	SELECT ROW_NUMBER() OVER(ORDER BY c.[Date Received], c.[Complaint ID]) AS RowNum
		,c.[Complaint ID]
		,c.[Date Received]
		,p.[Product Name]
		,c.[Company]
		,i.[Issue]
	FROM [sql_projects].[Consumer_Complaints_Table] AS c
		LEFT OUTER JOIN [sql_projects].[Issue_Table] AS i
		ON i.Issue_Code = c.Issue_Code 
		LEFT OUTER JOIN [sql_projects].[Product_Table] AS p
		ON p.Product_ID = c.Product_ID
	ORDER BY c.[Date Received], c.[Complaint ID]
	OFFSET (@pagenum - 1) * @pagesize ROWS FETCH NEXT @pagesize ROWS ONLY
GO

--Testing the paging function
SELECT RowNum,
	 [Complaint ID]
	,FORMAT([Date Received],  'dd/MM/yyyy') AS [Date Received]
	,[Product Name]
	,[Company]
	,[Issue]
FROM [sql_projects].[Paging_Function](10, 10) AS c;


--What are the details of issues raised in the state state of New York on 01 August 2013? The solution uses a created
--uses a stored procedure to return data based on 4 parameters namely Complaint ID, Date Recieved, Company and State Name.

CREATE OR ALTER PROC sql_projects.Get_Details
  @complaintid AS INT = NULL,
  @datereceived AS DATETIME = NULL,
  @companyname AS NVARCHAR(70) = NULL,
  @state AS NCHAR(2) = NULL
AS
SET XACT_ABORT, NOCOUNT ON;
DECLARE @sql AS NVARCHAR(MAX) = 
			N'SELECT
					 c.[Complaint ID]
					,c.[Date Received]
					,c.[Company]
					,p.[Product Name]
					,i.[Issue]	
					,k.[State Name]
				FROM [ConsumerComplaints].[sql_projects].[Consumer_Complaints_Table] AS c
				LEFT OUTER JOIN [ConsumerComplaints].[sql_projects].[Issue_Table] AS i
					ON i.Issue_Code = c.Issue_Code 
				LEFT OUTER JOIN [ConsumerComplaints].[sql_projects].[Product_Table] AS p
					ON p.Product_ID = c.Product_ID
				LEFT OUTER JOIN [ConsumerComplaints].[sql_projects].[Location_Table] AS k
					ON k.Location_Key = c.Location_Key
				WHERE 1 = 1'
				  + CASE WHEN @complaintid IS NOT NULL THEN N' AND c.[Complaint ID]  = @complaintid  ' ELSE N'' END
				  + CASE WHEN @datereceived IS NOT NULL THEN N' AND c.[Date Received] = @datereceived ' ELSE N'' END
				  + CASE WHEN @companyname IS NOT NULL THEN N' AND c.[Company]    = @companyname   ' ELSE N'' END
				  + CASE WHEN @state IS NOT NULL THEN N' AND k.[State Name]    = @state   ' ELSE N'' END
				  + N';'

EXEC sys.sp_executesql
  @stmt = @sql,
  @params = N'@complaintid AS INT, @datereceived AS DATETIME, @companyname AS NVARCHAR(70), @state AS NCHAR(2)',
  @complaintid   = @complaintid,
  @datereceived = @datereceived,
  @companyname    = @companyname,
  @state     = @state;
GO

-- Execute and test procedure
EXEC sql_projects.Get_Details @datereceived = '20130801', @state = 'NY';
