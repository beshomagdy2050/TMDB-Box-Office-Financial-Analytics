-- =============================================================================
-- TMDB 5000 Box Office Economics, Talent Bankability & Studio ROI Audit
-- SQLite Star-Schema Analytical Warehouse & Executive BI Views
-- Database: tmdb_5000.db
-- Scope: 4,802 Cleaned Movies (1916–2017) | 3,205 Financially Validated Films
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. CORE STAR-SCHEMA TABLES (1 FACT TABLE + 6 DIMENSION BRIDGE TABLES)
-- -----------------------------------------------------------------------------

-- Central Fact Table: Cleaned & Feature-Engineered Movies (4,802 rows x 22 columns)
CREATE TABLE IF NOT EXISTS "clean_movies" (
    "budget" INTEGER,
    "id" INTEGER PRIMARY KEY,
    "original_language" TEXT,
    "original_title" TEXT,
    "overview" TEXT,
    "popularity" REAL,
    "release_date" TIMESTAMP,
    "revenue" INTEGER,
    "runtime" REAL,
    "status" TEXT,
    "title" TEXT,
    "vote_average" REAL,
    "vote_count" INTEGER,
    "release_year" INTEGER,
    "release_month" INTEGER,
    "has_valid_financials" INTEGER,
    "profit" REAL,
    "roi_pct" REAL,
    "has_homepage" INTEGER,
    "has_tagline" INTEGER,
    "title_word_count" INTEGER,
    "weighted_rating" REAL
);

-- Dimension Table 1: Unpacked Movie Genres (12,160 rows)
CREATE TABLE IF NOT EXISTS "movie_genres" (
    "movie_id" INTEGER,
    "genre_name" TEXT
);

-- Dimension Table 2: Top-3 Production Studios per Film (10,162 rows)
CREATE TABLE IF NOT EXISTS "movie_companies" (
    "movie_id" INTEGER,
    "company_name" TEXT
);

-- Dimension Table 3: Top-5 Billed Cast Members per Film (23,594 rows)
CREATE TABLE IF NOT EXISTS "movie_cast" (
    "movie_id" INTEGER,
    "actor_name" TEXT,
    "billing_order" INTEGER
);

-- Dimension Table 4: Core Crew — Directors, Producers & Writers (17,718 rows)
CREATE TABLE IF NOT EXISTS "movie_crew" (
    "movie_id" INTEGER,
    "member_name" TEXT,
    "job_role" TEXT
);

-- Dimension Table 5: Production Countries (6,436 rows)
CREATE TABLE IF NOT EXISTS "movie_countries" (
    "movie_id" INTEGER,
    "country_name" TEXT
);

-- Dimension Table 6: Thematic & IP Keywords (36,194 rows)
CREATE TABLE IF NOT EXISTS "movie_keywords" (
    "movie_id" INTEGER,
    "keyword_name" TEXT
);

-- -----------------------------------------------------------------------------
-- 2. ANALYTICAL VIEWS FOR POWER BI & EXECUTIVE REPORTING
-- -----------------------------------------------------------------------------

-- View 1: Executive Financial Benchmark (Full Catalog vs. Validated Cohort)
DROP VIEW IF EXISTS vw_executive_financial_kpis;
CREATE VIEW vw_executive_financial_kpis AS
SELECT 
    COUNT(*) AS total_catalog_movies,
    SUM("has_valid_financials") AS validated_financial_movies,
    MIN("release_year") AS earliest_release_year,
    MAX("release_year") AS latest_release_year,
    ROUND(SUM("budget") / 1e9, 2) AS catalog_total_budget_B,
    ROUND(SUM("revenue") / 1e9, 2) AS catalog_total_revenue_B,
    ROUND(SUM("revenue" - "budget") / 1e9, 2) AS catalog_net_profit_B,
    ROUND(SUM(CASE WHEN "has_valid_financials" = 1 THEN "budget" ELSE 0 END) / 1e9, 2) AS validated_budget_B,
    ROUND(SUM(CASE WHEN "has_valid_financials" = 1 THEN "revenue" ELSE 0 END) / 1e9, 2) AS validated_revenue_B,
    ROUND(SUM(CASE WHEN "has_valid_financials" = 1 THEN "profit" ELSE 0 END) / 1e9, 2) AS validated_profit_B,
    ROUND(AVG(CASE WHEN "has_valid_financials" = 1 THEN "budget" END) / 1e6, 2) AS avg_validated_budget_M,
    ROUND(AVG(CASE WHEN "has_valid_financials" = 1 THEN "revenue" END) / 1e6, 2) AS avg_validated_revenue_M,
    ROUND(AVG(CASE WHEN "has_valid_financials" = 1 THEN "profit" END) / 1e6, 2) AS avg_validated_profit_M,
    ROUND(AVG(CASE WHEN "has_valid_financials" = 1 THEN "roi_pct" END), 2) AS mean_movie_roi_pct,
    ROUND(SUM(CASE WHEN "has_valid_financials" = 1 THEN "profit" ELSE 0 END) * 100.0 / 
          SUM(CASE WHEN "has_valid_financials" = 1 THEN "budget" ELSE 0 END), 2) AS portfolio_roi_pct,
    ROUND(SUM(CASE WHEN "has_valid_financials" = 1 AND "profit" > 0 THEN 1.0 ELSE 0.0 END) * 100.0 / 
          SUM("has_valid_financials"), 2) AS profitable_movies_share_pct,
    ROUND(AVG("runtime"), 2) AS avg_runtime_mins,
    ROUND(AVG("weighted_rating"), 2) AS avg_imdb_weighted_rating
FROM clean_movies;

-- View 2: Production Budget Tiers & Downside Loss Risk Analysis
DROP VIEW IF EXISTS vw_budget_tier_economics;
CREATE VIEW vw_budget_tier_economics AS
SELECT 
    CASE 
        WHEN "budget" < 1000000 THEN '1. Micro Budget (< $1M)'
        WHEN "budget" >= 1000000 AND "budget" < 15000000 THEN '2. Low Budget ($1M - $15M)'
        WHEN "budget" >= 15000000 AND "budget" < 50000000 THEN '3. Mid Budget ($15M - $50M)'
        WHEN "budget" >= 50000000 AND "budget" < 100000000 THEN '4. High Budget ($50M - $100M)'
        ELSE '5. Blockbuster ($100M+)'
    END AS budget_tier,
    COUNT(*) AS movie_count,
    ROUND(AVG("budget") / 1e6, 2) AS avg_budget_M,
    ROUND(AVG("revenue") / 1e6, 2) AS avg_revenue_M,
    ROUND(AVG("profit") / 1e6, 2) AS avg_profit_M,
    ROUND(SUM("profit") * 100.0 / SUM("budget"), 2) AS aggregate_tier_roi_pct,
    ROUND(SUM(CASE WHEN "profit" < 0 THEN 1.0 ELSE 0.0 END) * 100.0 / COUNT(*), 2) AS loss_rate_pct,
    ROUND(AVG("weighted_rating"), 2) AS avg_weighted_rating
FROM clean_movies
WHERE "has_valid_financials" = 1
GROUP BY budget_tier
ORDER BY budget_tier;

-- View 3: Genre Unit Economics, Total Gross & Audience Engagement Matrix
DROP VIEW IF EXISTS vw_genre_performance_matrix;
CREATE VIEW vw_genre_performance_matrix AS
SELECT 
    g."genre_name",
    COUNT(m."id") AS validated_movies,
    ROUND(SUM(m."revenue") / 1e9, 2) AS total_revenue_B,
    ROUND(SUM(m."profit") / 1e9, 2) AS total_profit_B,
    ROUND(AVG(m."budget") / 1e6, 2) AS avg_budget_M,
    ROUND(AVG(m."revenue") / 1e6, 2) AS avg_revenue_per_movie_M,
    ROUND(AVG(m."profit") / 1e6, 2) AS avg_profit_per_movie_M,
    ROUND(AVG(m."popularity"), 2) AS avg_popularity,
    ROUND(AVG(m."weighted_rating"), 2) AS avg_weighted_rating
FROM clean_movies m
JOIN movie_genres g ON m."id" = g."movie_id"
WHERE m."has_valid_financials" = 1
GROUP BY g."genre_name"
ORDER BY avg_revenue_per_movie_M DESC;

-- View 4: Monthly Release Calendar & Seasonal Profitability Windows
DROP VIEW IF EXISTS vw_seasonal_release_strategy;
CREATE VIEW vw_seasonal_release_strategy AS
SELECT 
    "release_month" AS month_num,
    CASE "release_month"
        WHEN 1 THEN 'January' WHEN 2 THEN 'February' WHEN 3 THEN 'March'
        WHEN 4 THEN 'April' WHEN 5 THEN 'May' WHEN 6 THEN 'June'
        WHEN 7 THEN 'July' WHEN 8 THEN 'August' WHEN 9 THEN 'September'
        WHEN 10 THEN 'October' WHEN 11 THEN 'November' WHEN 12 THEN 'December'
    END AS release_month_name,
    CASE 
        WHEN "release_month" IN (5, 6, 7) THEN 'Summer Tentpole (May-Jul)'
        WHEN "release_month" IN (11, 12) THEN 'Holiday Corridor (Nov-Dec)'
        WHEN "release_month" IN (3, 4) THEN 'Spring Window (Mar-Apr)'
        ELSE 'Dump / Off-Peak Months'
    END AS release_season,
    COUNT("id") AS movies_released,
    ROUND(AVG("budget") / 1e6, 2) AS avg_budget_M,
    ROUND(AVG("revenue") / 1e6, 2) AS avg_revenue_M,
    ROUND(AVG("profit") / 1e6, 2) AS avg_profit_M,
    ROUND(AVG("weighted_rating"), 2) AS avg_weighted_rating
FROM clean_movies
WHERE "has_valid_financials" = 1
GROUP BY "release_month"
ORDER BY avg_profit_M DESC;

-- View 5: Top Directors Bankability Leaderboard (Min. 3 Validated Films)
DROP VIEW IF EXISTS vw_top_directors_leaderboard;
CREATE VIEW vw_top_directors_leaderboard AS
SELECT 
    c."member_name" AS director_name,
    COUNT(m."id") AS total_movies_directed,
    ROUND(SUM(m."revenue") / 1e6, 2) AS total_revenue_M,
    ROUND(AVG(m."revenue") / 1e6, 2) AS avg_revenue_per_movie_M,
    ROUND(AVG(m."profit") / 1e6, 2) AS avg_profit_per_movie_M,
    ROUND(AVG(m."weighted_rating"), 2) AS avg_weighted_rating,
    ROUND(AVG(m."roi_pct"), 2) AS avg_roi_pct
FROM clean_movies m
JOIN movie_crew c ON m."id" = c."movie_id"
WHERE m."has_valid_financials" = 1 AND c."job_role" = 'Director'
GROUP BY c."member_name"
HAVING total_movies_directed >= 3
ORDER BY total_revenue_M DESC;

-- View 6: First-Billing Lead Actors Bankability (Billing Order = 1, Min. 5 Lead Roles)
DROP VIEW IF EXISTS vw_top_lead_actors_bankability;
CREATE VIEW vw_top_lead_actors_bankability AS
SELECT 
    c."actor_name" AS lead_actor,
    COUNT(m."id") AS total_lead_roles,
    ROUND(SUM(m."revenue") / 1e6, 2) AS total_box_office_M,
    ROUND(AVG(m."revenue") / 1e6, 2) AS avg_revenue_per_movie_M,
    ROUND(AVG(m."profit") / 1e6, 2) AS avg_profit_per_movie_M,
    ROUND(AVG(m."weighted_rating"), 2) AS avg_weighted_rating,
    ROUND(AVG(m."roi_pct"), 2) AS avg_roi_pct
FROM clean_movies m
JOIN movie_cast c ON m."id" = c."movie_id"
WHERE m."has_valid_financials" = 1 AND c."billing_order" = 1
GROUP BY c."actor_name"
HAVING total_lead_roles >= 5
ORDER BY total_box_office_M DESC;

-- View 7: Production Studio Market Share & Capital Efficiency (Min. 10 Validated Films)
DROP VIEW IF EXISTS vw_studio_market_share;
CREATE VIEW vw_studio_market_share AS
SELECT 
    c."company_name" AS production_company,
    COUNT(m."id") AS total_movies,
    ROUND(SUM(m."revenue") / 1e6, 2) AS total_revenue_M,
    ROUND(AVG(m."budget") / 1e6, 2) AS avg_budget_M,
    ROUND(AVG(m."revenue") / 1e6, 2) AS avg_revenue_per_movie_M,
    ROUND(AVG(m."profit") / 1e6, 2) AS avg_profit_per_movie_M,
    ROUND(AVG(m."weighted_rating"), 2) AS avg_rating
FROM clean_movies m
JOIN movie_companies c ON m."id" = c."movie_id"
WHERE m."has_valid_financials" = 1
GROUP BY c."company_name"
HAVING total_movies >= 10
ORDER BY total_revenue_M DESC;

-- View 8: Digital Marketing Synergy, Runtime Tiers & Title Length Impact
DROP VIEW IF EXISTS vw_marketing_content_drivers;
CREATE VIEW vw_marketing_content_drivers AS
SELECT 
    CASE WHEN "has_homepage" = 1 THEN 'Yes' ELSE 'No' END AS has_official_website,
    CASE WHEN "has_tagline" = 1 THEN 'Yes' ELSE 'No' END AS has_marketing_tagline,
    CASE 
        WHEN "runtime" < 90 THEN '1. Under 90 mins'
        WHEN "runtime" >= 90 AND "runtime" < 120 THEN '2. Standard (90-120m)'
        WHEN "runtime" >= 120 AND "runtime" < 150 THEN '3. Long (120-150m)'
        ELSE '4. Epic (150m+)'
    END AS runtime_tier,
    COUNT("id") AS movie_count,
    ROUND(AVG("budget") / 1e6, 2) AS avg_budget_M,
    ROUND(AVG("revenue") / 1e6, 2) AS avg_revenue_M,
    ROUND(AVG("profit") / 1e6, 2) AS avg_profit_M,
    ROUND(AVG("popularity"), 2) AS avg_popularity,
    ROUND(AVG("weighted_rating"), 2) AS avg_weighted_rating
FROM clean_movies
WHERE "has_valid_financials" = 1
GROUP BY has_official_website, has_marketing_tagline, runtime_tier
ORDER BY avg_revenue_M DESC;
