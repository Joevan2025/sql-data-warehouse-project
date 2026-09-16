/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to 
    populate the 'silver' schema tables from the 'bronze' schema.
	Actions Performed:
		- Truncates Silver tables.
		- Inserts transformed and cleansed data from Bronze into Silver tables.
		
Parameters:
    None. 
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC Silver.load_silver;
===============================================================================
*/

create or alter procedure silver.load_silver as
begin

	declare @start_time datetime, @end_time datetime, @batch_start_time datetime, @batch_end_time datetime;
	begin try
	
		set @batch_start_time = getdate();
		print '======================================';
		print 'Loading Silver layer';
		print '======================================';

			print '--------------------------------------';
			print 'Loading CRM Table';
			print '--------------------------------------';
			set @start_time = getdate();
			print '>> Truncating Table: silver.crm_cust_info';
			truncate table silver.crm_cust_info;
			print '>> Inserting Data Into: silver.crm_cust_info';
			insert into silver.crm_cust_info(
			cst_id,
			cst_key,
			cst_firstname,
			cst_lastname,
			cst_marital_status,
			cst_gndr,
			cst_create_date
			)
			select
			cst_id,
			cst_key,
			trim(cst_firstname) as cst_firstname,
			trim(cst_lastname) as cst_lastname,
			case when upper(trim(cst_marital_status)) = 's' then 'Single'
				when upper(trim(cst_marital_status)) = 'M' then 'Married'
				else 'n/a'
			end cst_marital_status,
			case when upper(trim(cst_gndr)) = 'F' then 'Female'
				when upper(trim(cst_gndr)) = 'M' then 'Male'
				else 'n/a'
			end cst_gndr,
			cst_create_date
			from (
			select
			*,
			ROW_NUMBER() over (partition by cst_id order by cst_create_date desc) as flag_last
			from bronze.crm_cust_info
			where cst_id is not null
			)t
			where flag_last = 1;
			set @end_time = getdate();
			print '>> Load duration:' + cast(datediff (second, @start_time, @end_time) as nvarchar) + ' seconds';
			print '--------------------------------------';



			-------------------------------------------------------

			set @start_time = getdate();
			print '>> Truncating Table: silver.crm_prd_info';
			truncate table silver.crm_prd_info;
			print '>> Inserting Data Into: silver.crm_prd_info';
			insert into silver.crm_prd_info (
			prd_id,
			cat_id,
			prd_key,
			prd_nm,
			prd_cost,
			prd_line,
			prd_start_dt,
			prd_end_dt
			)
			select
			prd_id,
			replace(SUBSTRING(prd_key, 1, 5), '-','_') as cat_id, --- Extract category ID
			substring(prd_key, 7, len(prd_key)) as prd_key, ---Extract product key
			prd_nm,
			isnull(prd_cost, 0) as 'prd_cost', --- Handling null values

			case upper(trim(prd_line))
				when 'M' then 'MOUNTAIN'
				when 'R' then 'ROAD'
				when 'S' then 'OTHER SALES'
				when 'T' then 'TOURING'
				else 'n/a' --- handling missing data
			end as 'prd_line', --- Map product line codes to descriptive values
			cast(prd_start_dt as date) as prd_start_dt, --- data type casting
			cast(
				lead(prd_start_dt) over (partition by prd_key order by prd_start_dt)-1 as date) 
				as prd_end_dt --- Calculate end date as one day before the next start date
			from
			bronze.crm_prd_info
			where prd_end_dt <= prd_start_dt or prd_start_dt is null or prd_end_dt is null;
			set @end_time = getdate();
			print '>> Load duration:' + cast(datediff (second, @start_time, @end_time) as nvarchar) + ' seconds';
			print '--------------------------------------';

			-------------------------------------------------

			set @start_time = getdate();
			print '>> Truncating Table: silver.crm_sales_details';
			truncate table silver.crm_sales_details;
			print '>> Inserting Data Into: silver.crm_sales_details';
			insert into silver.crm_sales_details(
				sls_ord_num,
				sls_prd_key,
				sls_cust_id ,
				sls_order_dt,
				sls_ship_dt,
				sls_due_dt,
				sls_sales,
				sls_quantity,
				sls_price
			)
			select
			sls_ord_num,
			sls_prd_key,
			sls_cust_id,
			case when sls_order_dt = 0 or len(sls_order_dt) != 8 then null
				else cast(cast(sls_order_dt as varchar) as date) --- Casting from integer to string and from string to date
			end as sls_order_dt, --- Note: Integer cannot cast directly to dates

			case when sls_ship_dt = 0 or len(sls_ship_dt) != 8 then null
				else cast(cast(sls_ship_dt as varchar) as date)
			end as sls_ship_dt,

			case when sls_due_dt = 0 or len(sls_due_dt) != 8 then null
				else cast(cast(sls_due_dt as varchar) as date) 
			end as sls_due_dt,

			--- sales = price * quantity
			--- if sales is negative, zero or null derive it using quantity and price
			--- If price is zero or null calculate it using quantity and sales
			--- If price is negative, convert it to positive value
			case when sls_sales <= 0 or sls_sales is null or sls_sales != sls_quantity * sls_price
				then sls_quantity * abs(sls_price)
				else sls_sales
			end as sls_sales,
			sls_quantity,
			case when sls_price <= 0 or sls_price is null
				then sls_sales / nullif(sls_quantity, 0)
				else sls_price
			end as sls_price
			from
			bronze.crm_sales_details
			;
			set @end_time = getdate();
			print '>> Load duration:' + cast(datediff (second, @start_time, @end_time) as nvarchar) + ' seconds';
			print '--------------------------------------';

			--------------------------------------------------------
			print '--------------------------------------';
			print 'Loading ERP Table';
			print '--------------------------------------';
			set @start_time = getdate();
			print '>> Truncating Table: silver.erp_cust_az12';
			truncate table silver.erp_cust_az12;
			print '>> Inserting Data Into: silver.erp_cust_az12';

			insert into silver.erp_cust_az12(
			cid,
			bdate,
			gen
			)

			select 
			--- Handling unwanted letters for distinct connection to other files ---
			case when cid like 'NAS%' then substring(cid, 4, len(cid)) --- Removing 'NAS' prefix
				else cid
			end as cid,

			--- Identify out of range dates ---
			--- select
			--- *
			--- from
			--- bronze.erp_cust_az12
			--- where bdate < '1920-01-01' or bdate > getdate();
			case when bdate > getdate() then null --- Set future values null
				else bdate
			end bdate,

			--- Data standardization and consistency ---
			case when upper(trim(gen)) in ('F', 'FEMALE') then 'Female'
				when upper(trim(gen)) in ('M', 'MALE') then 'Male'
				else 'n/a'
			end gen --- Normalize gender values and handle unknown cases
			from
			bronze.erp_cust_az12
			--- Checking for connections ---
			--- where case when cid like 'NAS%' then substring(cid, 4, len(cid))
			--- 	else cid
			--- end not in (select distinct cst_key from bronze.crm_cust_info)
			;
			set @end_time = getdate();
			print '>> Load duration:' + cast(datediff (second, @start_time, @end_time) as nvarchar) + ' seconds';
			print '--------------------------------------';

			-------------------------------------------------------

			print '>> Truncating Table: silver.erp_loc_a101';
			truncate table silver.erp_loc_a101;
			print '>> Inserting Data Into: silver.erp_loc_a101';

			insert into silver.erp_loc_a101(cid, cntry)
			select
			--- Handling unwanted characters
			replace(cid,'-', '') cid,
			--- Inspect for distinct
			--- Data standardization and consistency
			case when trim(cntry) = 'DE' then 'Germany'
				when trim(cntry) in ('US', 'USA') then 'United States'
				when trim(cntry) = '' or trim(cntry) is null then 'n/a'
				else trim(cntry)
			end cntry --- Normalize and Handle missing or blank countries
			from bronze.erp_loc_a101
			;
			set @end_time = getdate();
			print '>> Load duration:' + cast(datediff (second, @start_time, @end_time) as nvarchar) + ' seconds';
			print '--------------------------------------';

			-----------------------------------------------

			set @start_time = getdate();
			print '>> Truncating Table: silver.erp_px_cat_g1v2';
			truncate table silver.erp_px_cat_g1v2;
			print '>> Inserting Data Into: silver.erp_px_cat_g1v2';

			insert into silver.erp_px_cat_g1v2(id, cat, subcat, maintenance)
			select
			id,
			cat,
			subcat,
			maintenance
			from
			bronze.erp_px_cat_g1v2
			;
			set @end_time = getdate();
			print '>> Load duration:' + cast(datediff (second, @start_time, @end_time) as nvarchar) + ' seconds';
			print '--------------------------------------';

		set @batch_end_time = getdate();
		print '--------------------------------------';
		print 'Loading Silver is Complete'
		print '>> Total Load duration:' + cast(datediff (second, @start_time, @end_time) as nvarchar) + ' seconds';
		print '--------------------------------------';
	end try
	begin catch
	PRINT '=========================================='
	PRINT 'ERROR OCCURED DURING LOADING BRONZE LAYER'
	PRINT 'Error Message' + ERROR_MESSAGE();
	PRINT 'Error Message' + CAST (ERROR_NUMBER() AS NVARCHAR);
	PRINT 'Error Message' + CAST (ERROR_STATE() AS NVARCHAR);
	PRINT '=========================================='
	end catch

end
