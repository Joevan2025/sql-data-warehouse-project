/*
===============================================================================
DDL Script: Create Gold Views
===============================================================================
Script Purpose:
    This script creates views for the Gold layer in the data warehouse. 
    The Gold layer represents the final dimension and fact tables (Star Schema)

    Each view performs transformations and combines data from the Silver layer 
    to produce a clean, enriched, and business-ready dataset.

Usage:
    - These views can be queried directly for analytics and reporting.
===============================================================================
*/

-- =============================================================================
-- Create Dimension: gold.dim_customers
-- =============================================================================

IF OBJECT_ID('gold.dim_customers', 'V') IS NOT NULL
    DROP VIEW gold.dim_customers;
GO
create view gold.dim_customers as
select
	row_number() over (order by cst_id) as customer_key,
	ci.cst_id as customer_id,
	ci.cst_key as customer_number,
	ci.cst_firstname as first_name,
	ci.cst_lastname as last_name,
	la.cntry as country,
	ci.cst_marital_status as marital_status,
	case when ci.cst_gndr != 'n/a' then ci.cst_gndr --- CRM is the MASTER File of the gender info
		else coalesce(ca.gen, 'n/a')
	end as gender,
	ca.bdate as birthdate,
	ci.cst_create_date as create_date
from
silver.crm_cust_info ci
left join silver.erp_cust_az12 ca
on ci.cst_key = ca.cid
left join silver.erp_loc_a101 la
on ci.cst_key = la.cid
;
GO


IF OBJECT_ID('gold.dim_products', 'V') IS NOT NULL
    DROP VIEW gold.dim_products;
GO
create view gold.dim_products as
select
row_number() over (order by p.prd_start_dt, p.prd_key) as product_key,
p.prd_id as product_id,
p.prd_key as product_number,
p.prd_nm as product_name,
p.cat_id as category_id,
c.cat as  category,
c.subcat as sub_category,
c.maintenance,
p.prd_cost as cost,
p.prd_line as product_line,
p.prd_start_dt as start_date
from
silver.crm_prd_info p
left join 
silver.erp_px_cat_g1v2 c
on p.cat_id = c.id
where p.prd_end_dt is null --- filter out historical data
;
GO


IF OBJECT_ID('gold.fact_sales', 'V') IS NOT NULL
    DROP VIEW gold.fact_sales;
GO
create view gold.fact_sales as
select
--- Columns order
--- Dimension keys
sd.sls_ord_num as order_number,
pr.product_key,
cu.customer_key,

--- Dates
sd.sls_order_dt as order_date,
sd.sls_ship_dt as ship_date,
sd.sls_due_dt as due_date,

--- Measures
sd.sls_sales as sales,
sd.sls_quantity as quantity,
sd.sls_price as price
from
silver.crm_sales_details sd
left join gold.dim_products pr
on sd.sls_prd_key = pr.product_number
left join gold.dim_customers cu
on sd.sls_cust_id = cu.customer_id
;
GO
