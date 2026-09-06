-- =====================================================================
-- BUSINESS SALES & CLIENT ANALYTICS PROJECT
-- Author: Ojewale John Jeremiah
-- Platform: MySQL 8.0+
-- Purpose:
--   A clean end-to-end SQL portfolio project demonstrating:
--   • relational database design
--   • primary/foreign keys and referential integrity
--   • CRUD and data validation
--   • joins, aggregations, subqueries and CASE logic
--   • CTEs and window functions
--   • views, stored functions, procedures and triggers
--   • business-oriented sales, client, employee and branch analysis
-- =====================================================================

DROP DATABASE IF EXISTS business_sales_analytics;
CREATE DATABASE business_sales_analytics
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE business_sales_analytics;

-- =====================================================================
-- 1. TABLE DESIGN
-- =====================================================================

CREATE TABLE employee (
    emp_id       INT PRIMARY KEY,
    first_name   VARCHAR(40) NOT NULL,
    last_name    VARCHAR(40) NOT NULL,
    birth_day    DATE,
    sex          CHAR(1),
    salary       DECIMAL(12,2) NOT NULL,
    super_id     INT NULL,
    branch_id    INT NULL,
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_employee_sex
        CHECK (sex IN ('M','F') OR sex IS NULL),
    CONSTRAINT chk_employee_salary
        CHECK (salary >= 0),
    CONSTRAINT fk_employee_supervisor
        FOREIGN KEY (super_id)
        REFERENCES employee(emp_id)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);

CREATE TABLE branch (
    branch_id       INT PRIMARY KEY,
    branch_name     VARCHAR(60) NOT NULL UNIQUE,
    mgr_id          INT NULL,
    mgr_start_date  DATE,
    CONSTRAINT fk_branch_manager
        FOREIGN KEY (mgr_id)
        REFERENCES employee(emp_id)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);

ALTER TABLE employee
    ADD CONSTRAINT fk_employee_branch
    FOREIGN KEY (branch_id)
    REFERENCES branch(branch_id)
    ON DELETE SET NULL
    ON UPDATE CASCADE;

CREATE TABLE client (
    client_id     INT PRIMARY KEY,
    client_name   VARCHAR(80) NOT NULL,
    branch_id     INT NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_client_branch
        FOREIGN KEY (branch_id)
        REFERENCES branch(branch_id)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);

CREATE TABLE works_with (
    emp_id        INT NOT NULL,
    client_id     INT NOT NULL,
    total_sales   DECIMAL(14,2) NOT NULL,
    PRIMARY KEY (emp_id, client_id),
    CONSTRAINT chk_works_with_sales
        CHECK (total_sales >= 0),
    CONSTRAINT fk_works_with_employee
        FOREIGN KEY (emp_id)
        REFERENCES employee(emp_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_works_with_client
        FOREIGN KEY (client_id)
        REFERENCES client(client_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

CREATE TABLE branch_supplier (
    branch_id       INT NOT NULL,
    supplier_name   VARCHAR(80) NOT NULL,
    supply_type     VARCHAR(80) NOT NULL,
    PRIMARY KEY (branch_id, supplier_name),
    CONSTRAINT fk_branch_supplier_branch
        FOREIGN KEY (branch_id)
        REFERENCES branch(branch_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

-- Helpful indexes for reporting.
CREATE INDEX idx_employee_branch       ON employee(branch_id);
CREATE INDEX idx_employee_supervisor   ON employee(super_id);
CREATE INDEX idx_client_branch         ON client(branch_id);
CREATE INDEX idx_works_with_client     ON works_with(client_id);
CREATE INDEX idx_works_with_sales      ON works_with(total_sales);

-- =====================================================================
-- 2. SAMPLE DATA
-- =====================================================================

-- Corporate
INSERT INTO employee
    (emp_id, first_name, last_name, birth_day, sex, salary, super_id, branch_id)
VALUES
    (100, 'David', 'Wallace', '1967-11-17', 'M', 250000.00, NULL, NULL);

INSERT INTO branch (branch_id, branch_name, mgr_id, mgr_start_date)
VALUES (1, 'Corporate', 100, '2006-02-09');

UPDATE employee SET branch_id = 1 WHERE emp_id = 100;

INSERT INTO employee
    (emp_id, first_name, last_name, birth_day, sex, salary, super_id, branch_id)
VALUES
    (101, 'Jan', 'Levinson', '1961-05-11', 'F', 110000.00, 100, 1);

-- Scranton
INSERT INTO employee
    (emp_id, first_name, last_name, birth_day, sex, salary, super_id, branch_id)
VALUES
    (102, 'Michael', 'Scott', '1964-03-15', 'M', 75000.00, 100, NULL);

INSERT INTO branch (branch_id, branch_name, mgr_id, mgr_start_date)
VALUES (2, 'Scranton', 102, '1992-04-06');

UPDATE employee SET branch_id = 2 WHERE emp_id = 102;

INSERT INTO employee
    (emp_id, first_name, last_name, birth_day, sex, salary, super_id, branch_id)
VALUES
    (103, 'Angela',  'Martin', '1971-06-25', 'F', 63000.00, 102, 2),
    (104, 'Kelly',   'Kapoor', '1980-02-05', 'F', 55000.00, 102, 2),
    (105, 'Stanley', 'Hudson', '1958-02-19', 'M', 69000.00, 102, 2);

-- Stamford
INSERT INTO employee
    (emp_id, first_name, last_name, birth_day, sex, salary, super_id, branch_id)
VALUES
    (106, 'Josh', 'Porter', '1969-09-05', 'M', 78000.00, 100, NULL);

INSERT INTO branch (branch_id, branch_name, mgr_id, mgr_start_date)
VALUES (3, 'Stamford', 106, '1998-02-13');

UPDATE employee SET branch_id = 3 WHERE emp_id = 106;

INSERT INTO employee
    (emp_id, first_name, last_name, birth_day, sex, salary, super_id, branch_id)
VALUES
    (107, 'Andy', 'Bernard', '1973-07-22', 'M', 65000.00, 106, 3),
    (108, 'Jim',  'Halpert', '1978-10-01', 'M', 71000.00, 106, 3);

-- Extra branch with no manager, useful for outer-join demonstrations.
INSERT INTO branch (branch_id, branch_name, mgr_id, mgr_start_date)
VALUES (4, 'Buffalo', NULL, NULL);

INSERT INTO branch_supplier (branch_id, supplier_name, supply_type)
VALUES
    (2, 'Hammer Mill',          'Paper'),
    (2, 'Uni-ball',             'Writing Utensils'),
    (3, 'Patriot Paper',        'Paper'),
    (2, 'J.T. Forms & Labels',  'Custom Forms'),
    (3, 'Uni-ball',             'Writing Utensils'),
    (3, 'Hammer Mill',          'Paper'),
    (3, 'Stamford Labels',      'Custom Forms');

INSERT INTO client (client_id, client_name, branch_id)
VALUES
    (400, 'Dunmore High School',    2),
    (401, 'Lackawanna County',      2),
    (402, 'FedEx',                  3),
    (403, 'John Daly Law, LLC',     3),
    (404, 'Scranton White Pages',   2),
    (405, 'Times Newspaper',        3),
    (406, 'FedEx',                  2);

INSERT INTO works_with (emp_id, client_id, total_sales)
VALUES
    (105, 400,  55000.00),
    (102, 401, 267000.00),
    (108, 402,  22500.00),
    (107, 403,   5000.00),
    (108, 403,  12000.00),
    (105, 404,  33000.00),
    (107, 405,  26000.00),
    (102, 406,  15000.00),
    (105, 406, 130000.00);

-- =====================================================================
-- 3. DATA VALIDATION / QUALITY CHECKS
-- =====================================================================

-- 3.1 Count records in each business entity.
SELECT 'employee' AS table_name, COUNT(*) AS row_count FROM employee
UNION ALL
SELECT 'branch', COUNT(*) FROM branch
UNION ALL
SELECT 'client', COUNT(*) FROM client
UNION ALL
SELECT 'works_with', COUNT(*) FROM works_with
UNION ALL
SELECT 'branch_supplier', COUNT(*) FROM branch_supplier;

-- 3.2 Find employees with missing branch assignments.
SELECT emp_id, first_name, last_name
FROM employee
WHERE branch_id IS NULL;

-- 3.3 Check for duplicate client names across branches.
SELECT
    client_name,
    COUNT(*) AS occurrences,
    COUNT(DISTINCT branch_id) AS branches_served
FROM client
GROUP BY client_name
HAVING COUNT(*) > 1;

-- 3.4 Validate that sales are never negative.
SELECT *
FROM works_with
WHERE total_sales < 0;

-- =====================================================================
-- 4. BASIC FILTERING, SORTING AND DATE FUNCTIONS
-- =====================================================================

-- All employees.
SELECT *
FROM employee
ORDER BY emp_id;

-- All clients.
SELECT *
FROM client
ORDER BY client_name, branch_id;

-- Employees ordered by salary.
SELECT emp_id, first_name, last_name, salary
FROM employee
ORDER BY salary DESC, last_name, first_name;

-- Employees ordered by sex, then surname and first name.
SELECT emp_id, first_name, last_name, sex
FROM employee
ORDER BY sex, last_name, first_name;

-- First five employees by employee ID.
SELECT emp_id, first_name, last_name
FROM employee
ORDER BY emp_id
LIMIT 5;

-- Aliases for reporting.
SELECT
    first_name AS forename,
    last_name  AS surname
FROM employee
ORDER BY surname, forename;

-- Distinct sex values.
SELECT DISTINCT sex
FROM employee
WHERE sex IS NOT NULL;

-- Employees in branch 2.
SELECT *
FROM employee
WHERE branch_id = 2;

-- Employees born from 1 January 1970 onwards.
SELECT emp_id, first_name, last_name, birth_day
FROM employee
WHERE birth_day >= '1970-01-01'
ORDER BY birth_day;

-- Female employees in branch 2.
SELECT *
FROM employee
WHERE branch_id = 2
  AND sex = 'F';

-- Female employees born after 1969 OR employees earning above 80,000.
SELECT *
FROM employee
WHERE (birth_day >= '1970-01-01' AND sex = 'F')
   OR salary > 80000
ORDER BY salary DESC;

-- Employees born during 1970-1975 inclusive.
SELECT *
FROM employee
WHERE birth_day BETWEEN '1970-01-01' AND '1975-12-31';

-- Named employees.
SELECT *
FROM employee
WHERE first_name IN ('Jim', 'Michael', 'Johnny', 'David');

-- Employees born on the 10th day of any month.
SELECT emp_id, first_name, last_name, birth_day
FROM employee
WHERE DAY(birth_day) = 10;

-- =====================================================================
-- 5. AGGREGATE FUNCTIONS AND KPI ANALYSIS
-- =====================================================================

-- Workforce KPIs.
SELECT
    COUNT(*)                         AS employee_count,
    ROUND(AVG(salary), 2)            AS average_salary,
    MIN(salary)                      AS minimum_salary,
    MAX(salary)                      AS maximum_salary,
    SUM(salary)                      AS total_salary_cost
FROM employee;

-- Salary KPIs by sex.
SELECT
    sex,
    COUNT(*)              AS employee_count,
    ROUND(AVG(salary), 2) AS average_salary,
    SUM(salary)           AS salary_cost
FROM employee
GROUP BY sex
ORDER BY sex;

-- Total sales by salesperson.
SELECT
    e.emp_id,
    CONCAT(e.first_name, ' ', e.last_name) AS salesperson,
    COUNT(DISTINCT w.client_id)             AS client_count,
    SUM(w.total_sales)                      AS total_sales,
    ROUND(AVG(w.total_sales), 2)            AS average_client_sales
FROM employee e
JOIN works_with w
  ON w.emp_id = e.emp_id
GROUP BY e.emp_id, e.first_name, e.last_name
ORDER BY total_sales DESC;

-- Total amount spent by each client.
SELECT
    c.client_id,
    c.client_name,
    SUM(w.total_sales) AS client_value
FROM client c
JOIN works_with w
  ON w.client_id = c.client_id
GROUP BY c.client_id, c.client_name
ORDER BY client_value DESC;

-- =====================================================================
-- 6. STRING SEARCH / WILDCARDS
-- =====================================================================

-- Clients that are LLCs.
SELECT *
FROM client
WHERE client_name LIKE '%LLC%';

-- Suppliers related to labels.
SELECT *
FROM branch_supplier
WHERE supplier_name LIKE '%Label%';

-- School clients.
SELECT *
FROM client
WHERE client_name LIKE '%School%';

-- =====================================================================
-- 7. UNION
-- =====================================================================

-- One reporting list of client and supplier entities.
SELECT
    'Client' AS entity_type,
    client_name AS entity_name,
    branch_id
FROM client

UNION ALL

SELECT
    'Supplier' AS entity_type,
    supplier_name AS entity_name,
    branch_id
FROM branch_supplier
ORDER BY branch_id, entity_type, entity_name;

-- =====================================================================
-- 8. JOINS
-- =====================================================================

-- Employee and branch assignment. LEFT JOIN keeps unassigned employees.
SELECT
    e.emp_id,
    CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
    b.branch_name,
    e.salary
FROM employee e
LEFT JOIN branch b
  ON b.branch_id = e.branch_id
ORDER BY b.branch_name, employee_name;

-- Branch managers, including branches without a manager.
SELECT
    b.branch_id,
    b.branch_name,
    CONCAT(e.first_name, ' ', e.last_name) AS manager_name,
    b.mgr_start_date
FROM branch b
LEFT JOIN employee e
  ON e.emp_id = b.mgr_id
ORDER BY b.branch_id;

-- Sales detail with salesperson, client and branch.
SELECT
    w.emp_id,
    CONCAT(e.first_name, ' ', e.last_name) AS salesperson,
    c.client_name,
    b.branch_name,
    w.total_sales
FROM works_with w
JOIN employee e
  ON e.emp_id = w.emp_id
JOIN client c
  ON c.client_id = w.client_id
LEFT JOIN branch b
  ON b.branch_id = c.branch_id
ORDER BY w.total_sales DESC;

-- =====================================================================
-- 9. SUBQUERIES
-- =====================================================================

-- Employees who have at least one client relationship worth more than 30,000.
SELECT emp_id, first_name, last_name
FROM employee
WHERE emp_id IN (
    SELECT emp_id
    FROM works_with
    WHERE total_sales > 30000
);

-- Clients handled by the branch managed by Michael Scott.
SELECT client_id, client_name
FROM client
WHERE branch_id = (
    SELECT branch_id
    FROM branch
    WHERE mgr_id = (
        SELECT emp_id
        FROM employee
        WHERE first_name = 'Michael'
          AND last_name = 'Scott'
        LIMIT 1
    )
);

-- Clients whose cumulative sales exceed 100,000.
SELECT c.client_id, c.client_name
FROM client c
WHERE c.client_id IN (
    SELECT client_id
    FROM works_with
    GROUP BY client_id
    HAVING SUM(total_sales) > 100000
);

-- =====================================================================
-- 10. CASE EXPRESSIONS
-- =====================================================================

-- Classify employees by salary band.
SELECT
    emp_id,
    CONCAT(first_name, ' ', last_name) AS employee_name,
    salary,
    CASE
        WHEN salary >= 100000 THEN 'Executive'
        WHEN salary >= 70000  THEN 'Senior'
        WHEN salary >= 60000  THEN 'Mid'
        ELSE 'Developing'
    END AS salary_band
FROM employee
ORDER BY salary DESC;

-- Classify clients by cumulative value.
SELECT
    c.client_id,
    c.client_name,
    SUM(w.total_sales) AS total_client_sales,
    CASE
        WHEN SUM(w.total_sales) >= 100000 THEN 'High Value'
        WHEN SUM(w.total_sales) >= 30000  THEN 'Medium Value'
        ELSE 'Standard Value'
    END AS client_segment
FROM client c
JOIN works_with w
  ON w.client_id = c.client_id
GROUP BY c.client_id, c.client_name
ORDER BY total_client_sales DESC;

-- =====================================================================
-- 11. COMMON TABLE EXPRESSIONS (CTEs)
-- =====================================================================

-- CTE: salesperson performance.
WITH salesperson_sales AS (
    SELECT
        e.emp_id,
        CONCAT(e.first_name, ' ', e.last_name) AS salesperson,
        e.branch_id,
        COUNT(DISTINCT w.client_id)             AS clients_managed,
        SUM(w.total_sales)                      AS total_sales
    FROM employee e
    JOIN works_with w
      ON w.emp_id = e.emp_id
    GROUP BY e.emp_id, e.first_name, e.last_name, e.branch_id
)
SELECT
    ss.emp_id,
    ss.salesperson,
    b.branch_name,
    ss.clients_managed,
    ss.total_sales
FROM salesperson_sales ss
LEFT JOIN branch b
  ON b.branch_id = ss.branch_id
ORDER BY ss.total_sales DESC;

-- CTE: branch sales contribution to company sales.
WITH branch_sales AS (
    SELECT
        c.branch_id,
        SUM(w.total_sales) AS branch_sales
    FROM works_with w
    JOIN client c
      ON c.client_id = w.client_id
    GROUP BY c.branch_id
),
company_total AS (
    SELECT SUM(total_sales) AS company_sales
    FROM works_with
)
SELECT
    b.branch_name,
    bs.branch_sales,
    ROUND(100 * bs.branch_sales / ct.company_sales, 2) AS company_sales_pct
FROM branch_sales bs
JOIN branch b
  ON b.branch_id = bs.branch_id
CROSS JOIN company_total ct
ORDER BY bs.branch_sales DESC;

-- =====================================================================
-- 12. WINDOW FUNCTIONS
-- =====================================================================

-- Rank salespeople by total sales.
WITH salesperson_sales AS (
    SELECT
        e.emp_id,
        CONCAT(e.first_name, ' ', e.last_name) AS salesperson,
        COALESCE(SUM(w.total_sales), 0)         AS total_sales
    FROM employee e
    LEFT JOIN works_with w
      ON w.emp_id = e.emp_id
    GROUP BY e.emp_id, e.first_name, e.last_name
)
SELECT
    emp_id,
    salesperson,
    total_sales,
    DENSE_RANK() OVER (ORDER BY total_sales DESC) AS sales_rank,
    ROUND(
        100 * total_sales / NULLIF(SUM(total_sales) OVER (), 0),
        2
    ) AS share_of_recorded_sales_pct
FROM salesperson_sales
ORDER BY sales_rank, salesperson;

-- Rank clients within each branch.
WITH client_sales AS (
    SELECT
        c.branch_id,
        c.client_id,
        c.client_name,
        COALESCE(SUM(w.total_sales), 0) AS total_sales
    FROM client c
    LEFT JOIN works_with w
      ON w.client_id = c.client_id
    GROUP BY c.branch_id, c.client_id, c.client_name
)
SELECT
    b.branch_name,
    cs.client_id,
    cs.client_name,
    cs.total_sales,
    ROW_NUMBER() OVER (
        PARTITION BY cs.branch_id
        ORDER BY cs.total_sales DESC, cs.client_id
    ) AS client_rank_in_branch
FROM client_sales cs
LEFT JOIN branch b
  ON b.branch_id = cs.branch_id
ORDER BY b.branch_name, client_rank_in_branch;

-- Compare each salesperson with the average salesperson sales.
WITH salesperson_sales AS (
    SELECT
        e.emp_id,
        CONCAT(e.first_name, ' ', e.last_name) AS salesperson,
        COALESCE(SUM(w.total_sales), 0)         AS total_sales
    FROM employee e
    LEFT JOIN works_with w
      ON w.emp_id = e.emp_id
    GROUP BY e.emp_id, e.first_name, e.last_name
)
SELECT
    emp_id,
    salesperson,
    total_sales,
    ROUND(AVG(total_sales) OVER (), 2) AS average_salesperson_sales,
    ROUND(total_sales - AVG(total_sales) OVER (), 2) AS variance_from_average
FROM salesperson_sales
ORDER BY total_sales DESC;

-- =====================================================================
-- 13. REPORTING VIEWS
-- =====================================================================

DROP VIEW IF EXISTS vw_salesperson_performance;
CREATE VIEW vw_salesperson_performance AS
SELECT
    e.emp_id,
    CONCAT(e.first_name, ' ', e.last_name) AS salesperson,
    b.branch_name,
    COUNT(DISTINCT w.client_id)             AS client_count,
    COALESCE(SUM(w.total_sales), 0)         AS total_sales,
    COALESCE(ROUND(AVG(w.total_sales), 2), 0) AS average_client_sales
FROM employee e
LEFT JOIN works_with w
  ON w.emp_id = e.emp_id
LEFT JOIN branch b
  ON b.branch_id = e.branch_id
GROUP BY e.emp_id, e.first_name, e.last_name, b.branch_name;

DROP VIEW IF EXISTS vw_client_value;
CREATE VIEW vw_client_value AS
SELECT
    c.client_id,
    c.client_name,
    b.branch_name,
    COUNT(DISTINCT w.emp_id)      AS salespeople_involved,
    COALESCE(SUM(w.total_sales),0) AS lifetime_sales
FROM client c
LEFT JOIN works_with w
  ON w.client_id = c.client_id
LEFT JOIN branch b
  ON b.branch_id = c.branch_id
GROUP BY c.client_id, c.client_name, b.branch_name;

-- Use the views.
SELECT *
FROM vw_salesperson_performance
ORDER BY total_sales DESC;

SELECT *
FROM vw_client_value
ORDER BY lifetime_sales DESC;

-- =====================================================================
-- 14. STORED FUNCTION
-- =====================================================================

DROP FUNCTION IF EXISTS fn_employee_full_name;

DELIMITER $$
CREATE FUNCTION fn_employee_full_name(p_emp_id INT)
RETURNS VARCHAR(85)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_full_name VARCHAR(85);

    SELECT CONCAT(first_name, ' ', last_name)
      INTO v_full_name
    FROM employee
    WHERE emp_id = p_emp_id;

    RETURN v_full_name;
END$$
DELIMITER ;

SELECT
    emp_id,
    fn_employee_full_name(emp_id) AS employee_name,
    salary
FROM employee
ORDER BY emp_id;

-- =====================================================================
-- 15. STORED PROCEDURE: REUSABLE BRANCH MANAGEMENT REPORT
-- =====================================================================

DROP PROCEDURE IF EXISTS sp_branch_performance;

DELIMITER $$
CREATE PROCEDURE sp_branch_performance(IN p_branch_id INT)
BEGIN
    -- Branch headline KPIs.
    SELECT
        b.branch_id,
        b.branch_name,
        COUNT(DISTINCT e.emp_id) AS employee_count,
        COUNT(DISTINCT c.client_id) AS client_count,
        COALESCE(SUM(w.total_sales), 0) AS total_sales,
        COALESCE(ROUND(AVG(w.total_sales), 2), 0) AS average_relationship_sales
    FROM branch b
    LEFT JOIN employee e
      ON e.branch_id = b.branch_id
    LEFT JOIN client c
      ON c.branch_id = b.branch_id
    LEFT JOIN works_with w
      ON w.client_id = c.client_id
    WHERE b.branch_id = p_branch_id
    GROUP BY b.branch_id, b.branch_name;

    -- Client detail for the selected branch.
    SELECT
        c.client_id,
        c.client_name,
        COALESCE(SUM(w.total_sales), 0) AS total_sales
    FROM client c
    LEFT JOIN works_with w
      ON w.client_id = c.client_id
    WHERE c.branch_id = p_branch_id
    GROUP BY c.client_id, c.client_name
    ORDER BY total_sales DESC;
END$$
DELIMITER ;

-- Example:
CALL sp_branch_performance(2);

-- =====================================================================
-- 16. TRIGGER + AUDIT LOG
-- =====================================================================

CREATE TABLE employee_audit (
    audit_id      BIGINT AUTO_INCREMENT PRIMARY KEY,
    emp_id        INT NOT NULL,
    action_type   VARCHAR(20) NOT NULL,
    message       VARCHAR(255) NOT NULL,
    changed_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DROP TRIGGER IF EXISTS trg_employee_after_insert;

DELIMITER $$
CREATE TRIGGER trg_employee_after_insert
AFTER INSERT ON employee
FOR EACH ROW
BEGIN
    INSERT INTO employee_audit (emp_id, action_type, message)
    VALUES (
        NEW.emp_id,
        'INSERT',
        CONCAT(
            'Added employee ',
            NEW.first_name, ' ', NEW.last_name,
            ' with salary ', FORMAT(NEW.salary, 2)
        )
    );
END$$
DELIMITER ;

-- Trigger test.
INSERT INTO employee
    (emp_id, first_name, last_name, birth_day, sex, salary, super_id, branch_id)
VALUES
    (109, 'Oscar', 'Martinez', '1968-02-19', 'M', 69000.00, 106, 3),
    (110, 'Kevin', 'Malone',   '1978-02-19', 'M', 61000.00, 106, 3),
    (111, 'Pam',   'Beesly',   '1979-03-25', 'F', 62000.00, 106, 3);

SELECT *
FROM employee_audit
ORDER BY changed_at, audit_id;

-- =====================================================================
-- 17. MANAGEMENT-LEVEL BUSINESS QUESTIONS
-- =====================================================================

-- Q1. Which salesperson produces the most recorded sales?
SELECT *
FROM vw_salesperson_performance
WHERE total_sales > 0
ORDER BY total_sales DESC
LIMIT 5;

-- Q2. Which clients contribute the most sales?
SELECT *
FROM vw_client_value
ORDER BY lifetime_sales DESC
LIMIT 5;

-- Q3. Which branches contribute the most client sales?
SELECT
    b.branch_name,
    COALESCE(SUM(w.total_sales), 0) AS total_sales
FROM branch b
LEFT JOIN client c
  ON c.branch_id = b.branch_id
LEFT JOIN works_with w
  ON w.client_id = c.client_id
GROUP BY b.branch_id, b.branch_name
ORDER BY total_sales DESC;

-- Q4. Which employees have no recorded client sales?
SELECT
    e.emp_id,
    CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
    b.branch_name
FROM employee e
LEFT JOIN works_with w
  ON w.emp_id = e.emp_id
LEFT JOIN branch b
  ON b.branch_id = e.branch_id
WHERE w.emp_id IS NULL
ORDER BY b.branch_name, employee_name;

-- Q5. Which clients are served by more than one salesperson?
SELECT
    c.client_id,
    c.client_name,
    COUNT(DISTINCT w.emp_id) AS salesperson_count,
    SUM(w.total_sales) AS total_sales
FROM client c
JOIN works_with w
  ON w.client_id = c.client_id
GROUP BY c.client_id, c.client_name
HAVING COUNT(DISTINCT w.emp_id) > 1
ORDER BY total_sales DESC;

-- =====================================================================
-- 18. PORTFOLIO NOTES
-- =====================================================================
-- What this project demonstrates:
--   1. Corrected date literals, table names and ORDER BY references.
--   2. Strong relational design with data types, constraints and indexes.
--   3. Business questions answered with joins, aggregates and subqueries.
--   4. MySQL 8.0 CTEs and window functions for ranking and contribution.
--   5. Reusable views, stored function and stored procedure.
--   6. Trigger-based audit logging.
--   7. Data-quality checks and management reporting.
--
-- Suggested CV project title:
--   "Sales, Client & Branch Performance Analytics | MySQL"
--
-- Suggested CV bullets:
--   • Designed a relational sales database linking employees, branches,
--     clients, suppliers and sales relationships using primary/foreign keys.
--   • Wrote advanced MySQL queries using joins, CTEs, subqueries, CASE,
--     aggregations and window functions to analyse sales and client value.
--   • Built reusable views and a stored procedure for branch-level KPI
--     reporting, and implemented trigger-based audit logging.
-- =====================================================================
