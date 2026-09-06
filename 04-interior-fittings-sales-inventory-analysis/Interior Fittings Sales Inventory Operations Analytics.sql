-- =====================================================================
-- INTERIOR FITTINGS SALES, INVENTORY & OPERATIONS ANALYTICS
-- Author: Ojewale John Jeremiah
-- Platform: MySQL 8.0+
-- Currency: Nigerian Naira (NGN)
-- Dataset: Synthetic portfolio data created for analytics practice.
--
-- WHY THIS PROJECT EXISTS
-- This project is designed around the business needs of an interior-design
-- and fittings company. It closes common portfolio gaps by demonstrating:
--   • sales, customer, inventory and operational analysis
--   • procurement and supplier performance
--   • data quality validation
--   • budgeting and budget-vs-actual reporting
--   • demand planning and a simple moving-average forecast
--   • CTEs, window functions, CASE, date functions and NULL handling
--   • functions, views, stored procedures, triggers and scheduled reporting
--   • management-ready KPIs and automated report structures
--
-- IMPORTANT:
-- Forecasting here is a simple 3-month moving-average planning forecast,
-- not a machine-learning forecast. It is intentionally transparent and
-- suitable for a SQL/business-intelligence portfolio project.
-- =====================================================================

DROP DATABASE IF EXISTS interior_fittings_analytics;
CREATE DATABASE interior_fittings_analytics
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE interior_fittings_analytics;

-- =====================================================================
-- 1. MASTER DATA TABLES
-- =====================================================================

CREATE TABLE category (
    category_id     INT PRIMARY KEY,
    category_name   VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE supplier (
    supplier_id       INT PRIMARY KEY,
    supplier_name     VARCHAR(100) NOT NULL UNIQUE,
    standard_lead_days INT NOT NULL,
    CONSTRAINT chk_supplier_lead_days CHECK (standard_lead_days >= 0)
);

CREATE TABLE product (
    product_id       INT PRIMARY KEY,
    sku              VARCHAR(30) NOT NULL UNIQUE,
    product_name     VARCHAR(120) NOT NULL,
    category_id      INT NOT NULL,
    supplier_id      INT NOT NULL,
    standard_cost    DECIMAL(12,2) NOT NULL,
    list_price       DECIMAL(12,2) NOT NULL,
    reorder_level    INT NOT NULL,
    safety_stock     INT NOT NULL,
    active           BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_product_cost CHECK (standard_cost >= 0),
    CONSTRAINT chk_product_price CHECK (list_price >= 0),
    CONSTRAINT chk_product_reorder CHECK (reorder_level >= 0),
    CONSTRAINT chk_product_safety CHECK (safety_stock >= 0),
    CONSTRAINT fk_product_category
        FOREIGN KEY (category_id) REFERENCES category(category_id),
    CONSTRAINT fk_product_supplier
        FOREIGN KEY (supplier_id) REFERENCES supplier(supplier_id)
);

CREATE TABLE store (
    store_id       INT PRIMARY KEY,
    store_name     VARCHAR(100) NOT NULL UNIQUE,
    city           VARCHAR(80) NOT NULL,
    store_type     VARCHAR(30) NOT NULL,
    CONSTRAINT chk_store_type
        CHECK (store_type IN ('Showroom','Warehouse'))
);

CREATE TABLE customer (
    customer_id      INT PRIMARY KEY,
    customer_name    VARCHAR(120) NOT NULL,
    segment          VARCHAR(40) NOT NULL,
    signup_date      DATE NOT NULL,
    CONSTRAINT chk_customer_segment
        CHECK (segment IN ('Interior Design Firm','Contractor','Property Developer','Homeowner'))
);

-- =====================================================================
-- 2. TRANSACTION TABLES
-- =====================================================================

CREATE TABLE sales_order (
    order_id       INT PRIMARY KEY,
    order_date     DATE NOT NULL,
    store_id       INT NOT NULL,
    customer_id    INT NOT NULL,
    channel        VARCHAR(30) NOT NULL,
    status         VARCHAR(20) NOT NULL,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_sales_channel
        CHECK (channel IN ('Showroom','B2B Project','Online','Referral')),
    CONSTRAINT chk_sales_status
        CHECK (status IN ('Completed','Cancelled')),
    CONSTRAINT fk_sales_order_store
        FOREIGN KEY (store_id) REFERENCES store(store_id),
    CONSTRAINT fk_sales_order_customer
        FOREIGN KEY (customer_id) REFERENCES customer(customer_id)
);

CREATE TABLE sales_order_item (
    order_id        INT NOT NULL,
    product_id      INT NOT NULL,
    quantity        INT NOT NULL,
    unit_price      DECIMAL(12,2) NOT NULL,
    unit_cost       DECIMAL(12,2) NOT NULL,
    discount_pct    DECIMAL(6,4) NOT NULL DEFAULT 0,
    PRIMARY KEY (order_id, product_id),
    CONSTRAINT chk_sales_item_quantity CHECK (quantity > 0),
    CONSTRAINT chk_sales_item_price CHECK (unit_price >= 0),
    CONSTRAINT chk_sales_item_cost CHECK (unit_cost >= 0),
    CONSTRAINT chk_sales_item_discount CHECK (discount_pct BETWEEN 0 AND 1),
    CONSTRAINT fk_sales_item_order
        FOREIGN KEY (order_id) REFERENCES sales_order(order_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_sales_item_product
        FOREIGN KEY (product_id) REFERENCES product(product_id)
);

CREATE TABLE inventory_snapshot (
    snapshot_date    DATE NOT NULL,
    store_id         INT NOT NULL,
    product_id       INT NOT NULL,
    opening_stock    INT NOT NULL,
    received_qty     INT NOT NULL,
    sold_qty         INT NOT NULL,
    closing_stock    INT NOT NULL,
    PRIMARY KEY (snapshot_date, store_id, product_id),
    CONSTRAINT chk_inventory_nonnegative
        CHECK (
            opening_stock >= 0
            AND received_qty >= 0
            AND sold_qty >= 0
            AND closing_stock >= 0
        ),
    CONSTRAINT fk_inventory_store
        FOREIGN KEY (store_id) REFERENCES store(store_id),
    CONSTRAINT fk_inventory_product
        FOREIGN KEY (product_id) REFERENCES product(product_id)
);

CREATE TABLE monthly_budget (
    budget_month      DATE NOT NULL,
    store_id          INT NOT NULL,
    sales_budget      DECIMAL(14,2) NOT NULL,
    expense_budget    DECIMAL(14,2) NOT NULL,
    PRIMARY KEY (budget_month, store_id),
    CONSTRAINT chk_budget_month_first_day CHECK (DAY(budget_month) = 1),
    CONSTRAINT chk_budget_values CHECK (sales_budget >= 0 AND expense_budget >= 0),
    CONSTRAINT fk_budget_store
        FOREIGN KEY (store_id) REFERENCES store(store_id)
);

CREATE TABLE operating_expense (
    expense_id       INT PRIMARY KEY,
    expense_month    DATE NOT NULL,
    store_id         INT NOT NULL,
    expense_category VARCHAR(40) NOT NULL,
    amount           DECIMAL(14,2) NOT NULL,
    CONSTRAINT chk_expense_month_first_day CHECK (DAY(expense_month) = 1),
    CONSTRAINT chk_expense_amount CHECK (amount >= 0),
    CONSTRAINT fk_expense_store
        FOREIGN KEY (store_id) REFERENCES store(store_id)
);

CREATE TABLE purchase_order (
    po_id            INT PRIMARY KEY,
    order_date       DATE NOT NULL,
    expected_date    DATE NOT NULL,
    received_date    DATE NULL,
    supplier_id      INT NOT NULL,
    store_id         INT NOT NULL,
    status           VARCHAR(20) NOT NULL,
    CONSTRAINT chk_po_dates CHECK (expected_date >= order_date),
    CONSTRAINT chk_po_status CHECK (status IN ('Open','Partially Received','Received','Cancelled')),
    CONSTRAINT fk_po_supplier
        FOREIGN KEY (supplier_id) REFERENCES supplier(supplier_id),
    CONSTRAINT fk_po_store
        FOREIGN KEY (store_id) REFERENCES store(store_id)
);

CREATE TABLE purchase_order_item (
    po_id             INT NOT NULL,
    product_id        INT NOT NULL,
    quantity_ordered  INT NOT NULL,
    quantity_received INT NOT NULL,
    unit_cost         DECIMAL(12,2) NOT NULL,
    PRIMARY KEY (po_id, product_id),
    CONSTRAINT chk_po_item_qty CHECK (
        quantity_ordered > 0
        AND quantity_received >= 0
        AND quantity_received <= quantity_ordered
    ),
    CONSTRAINT chk_po_item_cost CHECK (unit_cost >= 0),
    CONSTRAINT fk_po_item_po
        FOREIGN KEY (po_id) REFERENCES purchase_order(po_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_po_item_product
        FOREIGN KEY (product_id) REFERENCES product(product_id)
);

-- =====================================================================
-- 3. INDEXES FOR ANALYTICAL PERFORMANCE
-- =====================================================================

CREATE INDEX idx_sales_order_date          ON sales_order(order_date);
CREATE INDEX idx_sales_order_store_date    ON sales_order(store_id, order_date);
CREATE INDEX idx_sales_order_customer      ON sales_order(customer_id);
CREATE INDEX idx_sales_item_product        ON sales_order_item(product_id);
CREATE INDEX idx_inventory_store_product   ON inventory_snapshot(store_id, product_id, snapshot_date);
CREATE INDEX idx_budget_month              ON monthly_budget(budget_month);
CREATE INDEX idx_expense_month_store       ON operating_expense(expense_month, store_id);
CREATE INDEX idx_po_supplier_date          ON purchase_order(supplier_id, order_date);

-- =====================================================================
-- 4. DATA INTEGRITY TRIGGERS
-- =====================================================================

-- Ensure the inventory arithmetic is internally consistent.
DROP TRIGGER IF EXISTS trg_inventory_validate_insert;
DELIMITER $$
CREATE TRIGGER trg_inventory_validate_insert
BEFORE INSERT ON inventory_snapshot
FOR EACH ROW
BEGIN
    IF NEW.closing_stock <> NEW.opening_stock + NEW.received_qty - NEW.sold_qty THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Inventory error: closing_stock must equal opening_stock + received_qty - sold_qty';
    END IF;

    IF NEW.closing_stock < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Inventory error: closing_stock cannot be negative';
    END IF;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS trg_inventory_validate_update;
DELIMITER $$
CREATE TRIGGER trg_inventory_validate_update
BEFORE UPDATE ON inventory_snapshot
FOR EACH ROW
BEGIN
    IF NEW.closing_stock <> NEW.opening_stock + NEW.received_qty - NEW.sold_qty THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Inventory error: closing_stock must equal opening_stock + received_qty - sold_qty';
    END IF;

    IF NEW.closing_stock < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Inventory error: closing_stock cannot be negative';
    END IF;
END$$
DELIMITER ;

-- =====================================================================
-- 5. SAMPLE DATA
-- =====================================================================


INSERT INTO category (category_id, category_name) VALUES
    (1, 'Flooring'),
    (2, 'Wall Finishes'),
    (3, 'Lighting'),
    (4, 'Cabinet Hardware'),
    (5, 'Sanitary Fittings'),
    (6, 'Doors'),
    (7, 'Paint & Coatings'),
    (8, 'Adhesives');

INSERT INTO supplier (supplier_id, supplier_name, standard_lead_days) VALUES
    (1, 'Lagos Surface Imports', 9),
    (2, 'Prime Panels Nigeria', 6),
    (3, 'Lumen Interiors Supply', 7),
    (4, 'BuildRight Hardware', 4),
    (5, 'AquaFit Distributors', 8),
    (6, 'Coat & Bond Nigeria', 5);

INSERT INTO product (product_id, sku, product_name, category_id, supplier_id, standard_cost, list_price, reorder_level, safety_stock, active) VALUES
    (1, 'FLR-600-POR', 'Porcelain Floor Tile 600x600', 1, 1, 6500, 9500, 25, 12, 1),
    (2, 'FLR-LAM-OAK', 'Oak Laminate Flooring Pack', 1, 1, 22000, 33000, 14, 7, 1),
    (3, 'WAL-PVC-3M', 'PVC Wall Panel 3m', 2, 2, 4200, 6500, 35, 15, 1),
    (4, 'LGT-PEND-01', 'Modern Pendant Light', 3, 3, 18000, 28500, 10, 5, 1),
    (5, 'CAB-HNG-SS', 'Soft-Close Cabinet Hinge Set', 4, 4, 3000, 5200, 40, 20, 1),
    (6, 'SAN-MIX-BSN', 'Basin Mixer Tap', 5, 5, 25000, 38000, 12, 6, 1),
    (7, 'DOR-INT-WD', 'Premium Interior Door', 6, 4, 65000, 92000, 6, 3, 1),
    (8, 'PNT-EMU-20L', 'Interior Emulsion Paint 20L', 7, 6, 28000, 41000, 18, 8, 1),
    (9, 'ADH-TIL-20KG', 'Tile Adhesive 20kg', 8, 6, 7500, 11000, 30, 15, 1),
    (10, 'SAN-VAN-900', 'Bathroom Vanity Unit 900mm', 5, 5, 85000, 125000, 5, 2, 1);

INSERT INTO store (store_id, store_name, city, store_type) VALUES
    (1, 'Lekki Showroom', 'Lekki', 'Showroom'),
    (2, 'Ikeja Showroom', 'Ikeja', 'Showroom'),
    (3, 'Yaba Warehouse', 'Yaba', 'Warehouse');

INSERT INTO customer (customer_id, customer_name, segment, signup_date) VALUES
    (1, 'Apex Interior Studio', 'Homeowner', '2024-05-15'),
    (2, 'BlueBrick Properties', 'Property Developer', '2024-01-19'),
    (3, 'Cedar Homeowners Ltd', 'Contractor', '2024-10-19'),
    (4, 'DwellCraft Design', 'Interior Design Firm', '2024-01-07'),
    (5, 'Elevate Contractors', 'Interior Design Firm', '2024-12-10'),
    (6, 'Forma Space Studio', 'Interior Design Firm', '2024-02-22'),
    (7, 'Granite Projects', 'Homeowner', '2024-04-08'),
    (8, 'Haven Residential', 'Contractor', '2024-07-06'),
    (9, 'Iconic Buildworks', 'Interior Design Firm', '2024-06-23'),
    (10, 'Juno Apartments', 'Contractor', '2024-08-09'),
    (11, 'Kora Design House', 'Homeowner', '2024-11-02'),
    (12, 'Lattice Developments', 'Contractor', '2024-07-06'),
    (13, 'MetroSpace Interiors', 'Contractor', '2024-03-23'),
    (14, 'Nova Property Group', 'Property Developer', '2024-04-02'),
    (15, 'Oak & Stone Concepts', 'Interior Design Firm', '2024-12-01'),
    (16, 'PrimeNest Homes', 'Property Developer', '2024-09-27'),
    (17, 'Quartz Construction', 'Homeowner', '2024-07-16'),
    (18, 'RoomTheory Studio', 'Contractor', '2024-01-16'),
    (19, 'UrbanEdge Developments', 'Contractor', '2024-05-06'),
    (20, 'Vista Homeowner', 'Interior Design Firm', '2024-04-26'),
    (21, 'Westline Contractors', 'Property Developer', '2024-09-28'),
    (22, 'Xenia Design Lab', 'Property Developer', '2024-05-24'),
    (23, 'YellowDoor Properties', 'Contractor', '2024-10-05'),
    (24, 'Zenith Fit-Outs', 'Homeowner', '2024-12-03'),
    (25, 'Alto Homeowner', 'Property Developer', '2024-12-05'),
    (26, 'Bespoke Living', 'Contractor', '2024-10-04'),
    (27, 'CasaNova Design', 'Property Developer', '2024-09-09'),
    (28, 'Delta Build Partners', 'Interior Design Firm', '2024-05-06'),
    (29, 'Elmwood Properties', 'Interior Design Firm', '2024-02-21'),
    (30, 'Fusion Interiors', 'Contractor', '2024-07-12');

INSERT INTO sales_order (order_id, order_date, store_id, customer_id, channel, status) VALUES
    (1001, '2025-01-05', 1, 24, 'B2B Project', 'Completed'),
    (1002, '2025-01-03', 2, 9, 'B2B Project', 'Cancelled'),
    (1003, '2025-01-18', 1, 29, 'Online', 'Completed'),
    (1004, '2025-01-05', 1, 17, 'B2B Project', 'Completed'),
    (1005, '2025-01-26', 1, 19, 'B2B Project', 'Completed'),
    (1006, '2025-01-06', 1, 21, 'Showroom', 'Completed'),
    (1007, '2025-01-01', 1, 27, 'Referral', 'Completed'),
    (1008, '2025-01-02', 1, 14, 'B2B Project', 'Completed'),
    (1009, '2025-01-27', 1, 10, 'B2B Project', 'Completed'),
    (1010, '2025-01-23', 1, 9, 'B2B Project', 'Completed'),
    (1011, '2025-01-09', 1, 17, 'B2B Project', 'Completed'),
    (1012, '2025-01-02', 1, 14, 'Online', 'Completed'),
    (1013, '2025-01-09', 1, 6, 'Showroom', 'Completed'),
    (1014, '2025-01-16', 1, 3, 'B2B Project', 'Cancelled'),
    (1015, '2025-01-02', 2, 16, 'Online', 'Completed'),
    (1016, '2025-01-14', 2, 28, 'Showroom', 'Completed'),
    (1017, '2025-01-24', 2, 5, 'Showroom', 'Completed'),
    (1018, '2025-01-01', 1, 12, 'B2B Project', 'Completed'),
    (1019, '2025-01-18', 2, 30, 'Showroom', 'Completed'),
    (1020, '2025-01-13', 1, 3, 'Online', 'Completed'),
    (1021, '2025-01-18', 1, 19, 'Online', 'Completed'),
    (1022, '2025-02-18', 3, 24, 'B2B Project', 'Cancelled'),
    (1023, '2025-02-23', 1, 1, 'Online', 'Completed'),
    (1024, '2025-02-15', 1, 10, 'Showroom', 'Completed'),
    (1025, '2025-02-09', 3, 21, 'Referral', 'Completed'),
    (1026, '2025-02-02', 1, 8, 'Showroom', 'Completed'),
    (1027, '2025-02-03', 1, 27, 'B2B Project', 'Completed'),
    (1028, '2025-02-01', 1, 11, 'B2B Project', 'Completed'),
    (1029, '2025-02-13', 1, 5, 'B2B Project', 'Completed'),
    (1030, '2025-02-13', 2, 14, 'Referral', 'Completed'),
    (1031, '2025-02-12', 1, 3, 'Online', 'Completed'),
    (1032, '2025-02-03', 1, 26, 'Showroom', 'Completed'),
    (1033, '2025-02-11', 1, 12, 'Showroom', 'Completed'),
    (1034, '2025-02-15', 1, 4, 'B2B Project', 'Completed'),
    (1035, '2025-02-11', 3, 24, 'B2B Project', 'Completed'),
    (1036, '2025-02-20', 2, 15, 'Referral', 'Completed'),
    (1037, '2025-02-03', 2, 23, 'B2B Project', 'Completed'),
    (1038, '2025-02-25', 1, 22, 'Online', 'Completed'),
    (1039, '2025-02-06', 1, 5, 'B2B Project', 'Completed'),
    (1040, '2025-02-02', 2, 10, 'Showroom', 'Completed'),
    (1041, '2025-02-28', 1, 10, 'B2B Project', 'Completed'),
    (1042, '2025-03-18', 2, 17, 'Referral', 'Completed'),
    (1043, '2025-03-26', 3, 18, 'Showroom', 'Completed'),
    (1044, '2025-03-14', 1, 3, 'Referral', 'Completed'),
    (1045, '2025-03-15', 1, 5, 'Online', 'Completed'),
    (1046, '2025-03-10', 1, 11, 'Online', 'Completed'),
    (1047, '2025-03-09', 2, 24, 'Online', 'Completed'),
    (1048, '2025-03-03', 2, 23, 'B2B Project', 'Completed'),
    (1049, '2025-03-20', 2, 30, 'Showroom', 'Completed'),
    (1050, '2025-03-26', 3, 13, 'Online', 'Cancelled'),
    (1051, '2025-03-09', 2, 9, 'Showroom', 'Completed'),
    (1052, '2025-03-11', 3, 24, 'Online', 'Completed'),
    (1053, '2025-03-09', 3, 3, 'Showroom', 'Completed'),
    (1054, '2025-03-03', 1, 13, 'Online', 'Completed'),
    (1055, '2025-03-10', 3, 10, 'Showroom', 'Completed'),
    (1056, '2025-03-20', 2, 1, 'Showroom', 'Completed'),
    (1057, '2025-03-26', 3, 18, 'Referral', 'Completed'),
    (1058, '2025-03-16', 1, 7, 'Showroom', 'Completed'),
    (1059, '2025-03-18', 1, 24, 'Online', 'Cancelled'),
    (1060, '2025-03-19', 3, 29, 'Online', 'Completed'),
    (1061, '2025-03-23', 2, 25, 'Showroom', 'Completed'),
    (1062, '2025-03-09', 3, 22, 'Online', 'Cancelled'),
    (1063, '2025-03-02', 2, 8, 'B2B Project', 'Completed'),
    (1064, '2025-03-27', 1, 6, 'B2B Project', 'Completed'),
    (1065, '2025-03-04', 3, 8, 'B2B Project', 'Completed'),
    (1066, '2025-03-05', 2, 6, 'B2B Project', 'Completed'),
    (1067, '2025-04-11', 2, 4, 'B2B Project', 'Cancelled'),
    (1068, '2025-04-25', 1, 9, 'Showroom', 'Completed'),
    (1069, '2025-04-08', 1, 28, 'B2B Project', 'Completed'),
    (1070, '2025-04-18', 2, 11, 'Showroom', 'Completed'),
    (1071, '2025-04-28', 3, 11, 'B2B Project', 'Completed'),
    (1072, '2025-04-06', 1, 28, 'Showroom', 'Completed'),
    (1073, '2025-04-24', 2, 7, 'B2B Project', 'Completed'),
    (1074, '2025-04-14', 1, 27, 'Showroom', 'Completed'),
    (1075, '2025-04-20', 2, 15, 'B2B Project', 'Completed'),
    (1076, '2025-04-18', 1, 7, 'B2B Project', 'Cancelled'),
    (1077, '2025-04-20', 3, 27, 'Showroom', 'Completed'),
    (1078, '2025-04-26', 1, 23, 'B2B Project', 'Completed'),
    (1079, '2025-04-11', 1, 11, 'Referral', 'Completed'),
    (1080, '2025-04-26', 1, 5, 'B2B Project', 'Completed'),
    (1081, '2025-04-09', 1, 19, 'B2B Project', 'Completed'),
    (1082, '2025-04-09', 3, 11, 'Showroom', 'Completed'),
    (1083, '2025-04-01', 3, 6, 'Showroom', 'Completed'),
    (1084, '2025-04-24', 1, 13, 'B2B Project', 'Completed'),
    (1085, '2025-05-11', 2, 21, 'Referral', 'Cancelled'),
    (1086, '2025-05-28', 2, 21, 'Online', 'Completed'),
    (1087, '2025-05-19', 3, 25, 'B2B Project', 'Completed'),
    (1088, '2025-05-10', 2, 9, 'Showroom', 'Completed'),
    (1089, '2025-05-13', 1, 30, 'Showroom', 'Completed'),
    (1090, '2025-05-23', 3, 30, 'Showroom', 'Completed'),
    (1091, '2025-05-01', 3, 8, 'Showroom', 'Completed'),
    (1092, '2025-05-12', 3, 19, 'Showroom', 'Completed'),
    (1093, '2025-05-24', 2, 27, 'B2B Project', 'Completed'),
    (1094, '2025-05-15', 1, 13, 'B2B Project', 'Completed'),
    (1095, '2025-05-11', 2, 21, 'B2B Project', 'Completed'),
    (1096, '2025-05-01', 1, 17, 'Referral', 'Completed'),
    (1097, '2025-05-09', 2, 25, 'Referral', 'Completed'),
    (1098, '2025-05-15', 1, 3, 'Online', 'Completed'),
    (1099, '2025-05-21', 1, 13, 'Showroom', 'Completed'),
    (1100, '2025-05-22', 2, 9, 'Referral', 'Completed'),
    (1101, '2025-05-10', 1, 25, 'B2B Project', 'Cancelled'),
    (1102, '2025-05-22', 3, 2, 'Showroom', 'Completed'),
    (1103, '2025-05-05', 1, 26, 'Showroom', 'Completed'),
    (1104, '2025-05-19', 1, 29, 'Showroom', 'Completed'),
    (1105, '2025-05-04', 1, 16, 'B2B Project', 'Completed'),
    (1106, '2025-06-18', 1, 23, 'Referral', 'Cancelled'),
    (1107, '2025-06-09', 2, 11, 'Online', 'Completed'),
    (1108, '2025-06-25', 3, 17, 'Showroom', 'Completed'),
    (1109, '2025-06-20', 1, 13, 'Online', 'Completed'),
    (1110, '2025-06-20', 2, 5, 'Showroom', 'Completed'),
    (1111, '2025-06-18', 1, 7, 'B2B Project', 'Cancelled'),
    (1112, '2025-06-01', 3, 24, 'B2B Project', 'Completed'),
    (1113, '2025-06-01', 1, 28, 'Online', 'Completed'),
    (1114, '2025-06-08', 1, 10, 'Showroom', 'Completed'),
    (1115, '2025-06-19', 2, 14, 'B2B Project', 'Completed'),
    (1116, '2025-06-09', 2, 5, 'B2B Project', 'Completed'),
    (1117, '2025-06-11', 1, 13, 'B2B Project', 'Completed'),
    (1118, '2025-06-18', 2, 12, 'B2B Project', 'Cancelled'),
    (1119, '2025-06-14', 3, 2, 'Showroom', 'Cancelled'),
    (1120, '2025-06-24', 2, 4, 'Showroom', 'Completed'),
    (1121, '2025-06-05', 1, 19, 'Referral', 'Completed'),
    (1122, '2025-06-06', 2, 10, 'B2B Project', 'Completed'),
    (1123, '2025-06-26', 2, 21, 'Showroom', 'Completed'),
    (1124, '2025-06-26', 1, 18, 'Online', 'Completed'),
    (1125, '2025-06-11', 1, 12, 'Online', 'Completed'),
    (1126, '2025-06-05', 1, 9, 'Showroom', 'Completed'),
    (1127, '2025-06-09', 2, 14, 'Referral', 'Completed'),
    (1128, '2025-06-21', 3, 3, 'B2B Project', 'Completed'),
    (1129, '2025-06-09', 2, 2, 'Showroom', 'Cancelled'),
    (1130, '2025-06-01', 3, 11, 'Showroom', 'Completed'),
    (1131, '2025-06-19', 1, 16, 'B2B Project', 'Completed'),
    (1132, '2025-07-25', 3, 27, 'B2B Project', 'Completed'),
    (1133, '2025-07-09', 2, 28, 'Showroom', 'Completed'),
    (1134, '2025-07-16', 1, 12, 'B2B Project', 'Completed'),
    (1135, '2025-07-13', 2, 9, 'Referral', 'Completed'),
    (1136, '2025-07-15', 2, 26, 'Referral', 'Completed'),
    (1137, '2025-07-05', 2, 13, 'Showroom', 'Completed'),
    (1138, '2025-07-27', 2, 29, 'Online', 'Completed'),
    (1139, '2025-07-08', 1, 16, 'Showroom', 'Completed'),
    (1140, '2025-07-15', 2, 27, 'Showroom', 'Completed'),
    (1141, '2025-07-08', 3, 3, 'B2B Project', 'Completed'),
    (1142, '2025-07-16', 1, 12, 'Showroom', 'Completed'),
    (1143, '2025-07-19', 1, 6, 'B2B Project', 'Completed'),
    (1144, '2025-07-22', 2, 6, 'Referral', 'Completed'),
    (1145, '2025-07-25', 1, 28, 'B2B Project', 'Completed'),
    (1146, '2025-07-14', 2, 13, 'B2B Project', 'Completed'),
    (1147, '2025-07-20', 2, 14, 'Online', 'Completed'),
    (1148, '2025-07-20', 2, 6, 'Online', 'Completed'),
    (1149, '2025-07-06', 3, 17, 'Showroom', 'Completed'),
    (1150, '2025-07-22', 1, 6, 'B2B Project', 'Completed');

INSERT INTO sales_order (order_id, order_date, store_id, customer_id, channel, status) VALUES
    (1151, '2025-07-15', 1, 15, 'Showroom', 'Completed'),
    (1152, '2025-07-25', 1, 6, 'B2B Project', 'Completed'),
    (1153, '2025-07-24', 1, 19, 'Referral', 'Completed'),
    (1154, '2025-07-25', 1, 21, 'Showroom', 'Completed'),
    (1155, '2025-07-17', 3, 6, 'B2B Project', 'Completed'),
    (1156, '2025-07-19', 2, 26, 'Showroom', 'Completed'),
    (1157, '2025-08-27', 2, 5, 'Referral', 'Completed'),
    (1158, '2025-08-23', 2, 11, 'B2B Project', 'Completed'),
    (1159, '2025-08-26', 1, 22, 'B2B Project', 'Completed'),
    (1160, '2025-08-25', 3, 4, 'B2B Project', 'Completed'),
    (1161, '2025-08-07', 2, 17, 'Online', 'Completed'),
    (1162, '2025-08-17', 1, 8, 'B2B Project', 'Completed'),
    (1163, '2025-08-26', 3, 20, 'B2B Project', 'Completed'),
    (1164, '2025-08-14', 1, 19, 'Showroom', 'Completed'),
    (1165, '2025-08-23', 3, 12, 'Referral', 'Completed'),
    (1166, '2025-08-19', 3, 7, 'Showroom', 'Completed'),
    (1167, '2025-08-05', 2, 6, 'B2B Project', 'Completed'),
    (1168, '2025-08-27', 2, 3, 'Referral', 'Completed'),
    (1169, '2025-08-17', 3, 24, 'Referral', 'Completed'),
    (1170, '2025-08-16', 1, 28, 'B2B Project', 'Completed'),
    (1171, '2025-08-01', 3, 4, 'B2B Project', 'Completed'),
    (1172, '2025-08-27', 2, 19, 'Online', 'Cancelled'),
    (1173, '2025-08-15', 2, 26, 'Referral', 'Completed'),
    (1174, '2025-08-27', 1, 20, 'Online', 'Completed'),
    (1175, '2025-08-09', 3, 12, 'Referral', 'Completed'),
    (1176, '2025-08-05', 1, 11, 'Referral', 'Completed'),
    (1177, '2025-09-24', 3, 26, 'Referral', 'Completed'),
    (1178, '2025-09-01', 1, 10, 'Referral', 'Completed'),
    (1179, '2025-09-04', 1, 21, 'Showroom', 'Completed'),
    (1180, '2025-09-17', 1, 1, 'B2B Project', 'Completed'),
    (1181, '2025-09-10', 3, 15, 'Referral', 'Completed'),
    (1182, '2025-09-10', 3, 15, 'Online', 'Cancelled'),
    (1183, '2025-09-02', 1, 24, 'Online', 'Completed'),
    (1184, '2025-09-22', 2, 6, 'Referral', 'Completed'),
    (1185, '2025-09-02', 1, 15, 'Referral', 'Completed'),
    (1186, '2025-09-21', 1, 15, 'Showroom', 'Completed'),
    (1187, '2025-09-27', 2, 27, 'B2B Project', 'Completed'),
    (1188, '2025-09-11', 2, 3, 'B2B Project', 'Completed'),
    (1189, '2025-09-06', 1, 23, 'B2B Project', 'Completed'),
    (1190, '2025-09-22', 1, 2, 'Showroom', 'Completed'),
    (1191, '2025-09-27', 3, 14, 'Showroom', 'Completed'),
    (1192, '2025-09-19', 1, 30, 'Referral', 'Completed'),
    (1193, '2025-09-19', 3, 13, 'B2B Project', 'Completed'),
    (1194, '2025-09-10', 3, 1, 'Online', 'Completed'),
    (1195, '2025-09-13', 2, 4, 'B2B Project', 'Completed'),
    (1196, '2025-09-21', 3, 3, 'Showroom', 'Completed'),
    (1197, '2025-09-27', 2, 1, 'Showroom', 'Completed'),
    (1198, '2025-09-20', 1, 13, 'B2B Project', 'Completed'),
    (1199, '2025-09-26', 3, 24, 'Showroom', 'Completed'),
    (1200, '2025-09-08', 2, 19, 'B2B Project', 'Completed'),
    (1201, '2025-09-05', 1, 4, 'Online', 'Completed'),
    (1202, '2025-09-16', 3, 4, 'Showroom', 'Completed'),
    (1203, '2025-10-26', 3, 14, 'B2B Project', 'Completed'),
    (1204, '2025-10-20', 1, 14, 'B2B Project', 'Completed'),
    (1205, '2025-10-20', 1, 8, 'Online', 'Completed'),
    (1206, '2025-10-14', 3, 4, 'Showroom', 'Completed'),
    (1207, '2025-10-21', 1, 1, 'Referral', 'Completed'),
    (1208, '2025-10-07', 2, 24, 'B2B Project', 'Completed'),
    (1209, '2025-10-10', 2, 6, 'B2B Project', 'Completed'),
    (1210, '2025-10-03', 2, 13, 'Online', 'Completed'),
    (1211, '2025-10-28', 2, 30, 'Referral', 'Completed'),
    (1212, '2025-10-14', 3, 27, 'B2B Project', 'Completed'),
    (1213, '2025-10-07', 1, 22, 'Referral', 'Completed'),
    (1214, '2025-10-08', 1, 2, 'B2B Project', 'Completed'),
    (1215, '2025-10-24', 1, 5, 'Showroom', 'Completed'),
    (1216, '2025-10-23', 1, 24, 'Showroom', 'Cancelled'),
    (1217, '2025-10-03', 1, 15, 'Showroom', 'Completed'),
    (1218, '2025-10-13', 2, 17, 'B2B Project', 'Completed'),
    (1219, '2025-10-25', 1, 2, 'Referral', 'Completed'),
    (1220, '2025-10-09', 3, 6, 'Referral', 'Completed'),
    (1221, '2025-10-28', 2, 20, 'Showroom', 'Cancelled'),
    (1222, '2025-10-02', 1, 16, 'Referral', 'Completed'),
    (1223, '2025-10-20', 3, 11, 'Showroom', 'Completed'),
    (1224, '2025-10-26', 2, 19, 'B2B Project', 'Completed'),
    (1225, '2025-10-22', 2, 10, 'Online', 'Completed'),
    (1226, '2025-10-09', 2, 25, 'Online', 'Completed'),
    (1227, '2025-10-13', 2, 27, 'Online', 'Completed'),
    (1228, '2025-10-04', 3, 23, 'Showroom', 'Completed'),
    (1229, '2025-11-18', 1, 4, 'B2B Project', 'Completed'),
    (1230, '2025-11-09', 1, 17, 'B2B Project', 'Completed'),
    (1231, '2025-11-12', 2, 18, 'Showroom', 'Completed'),
    (1232, '2025-11-21', 1, 6, 'Referral', 'Completed'),
    (1233, '2025-11-08', 3, 27, 'Online', 'Completed'),
    (1234, '2025-11-02', 3, 8, 'Showroom', 'Completed'),
    (1235, '2025-11-24', 2, 22, 'B2B Project', 'Completed'),
    (1236, '2025-11-25', 1, 29, 'Showroom', 'Completed'),
    (1237, '2025-11-19', 1, 19, 'B2B Project', 'Completed'),
    (1238, '2025-11-16', 1, 10, 'B2B Project', 'Completed'),
    (1239, '2025-11-26', 2, 19, 'B2B Project', 'Completed'),
    (1240, '2025-11-27', 1, 13, 'Online', 'Completed'),
    (1241, '2025-11-05', 3, 15, 'Online', 'Completed'),
    (1242, '2025-11-17', 1, 29, 'B2B Project', 'Completed'),
    (1243, '2025-11-03', 1, 13, 'B2B Project', 'Completed'),
    (1244, '2025-11-07', 1, 4, 'Referral', 'Completed'),
    (1245, '2025-11-27', 2, 20, 'Showroom', 'Completed'),
    (1246, '2025-11-14', 1, 3, 'B2B Project', 'Cancelled'),
    (1247, '2025-11-14', 2, 8, 'Referral', 'Completed'),
    (1248, '2025-12-04', 1, 4, 'B2B Project', 'Completed'),
    (1249, '2025-12-03', 1, 26, 'Referral', 'Completed'),
    (1250, '2025-12-28', 2, 19, 'Showroom', 'Completed'),
    (1251, '2025-12-20', 1, 9, 'Showroom', 'Cancelled'),
    (1252, '2025-12-18', 2, 14, 'B2B Project', 'Completed'),
    (1253, '2025-12-23', 3, 24, 'Referral', 'Completed'),
    (1254, '2025-12-07', 2, 12, 'B2B Project', 'Completed'),
    (1255, '2025-12-05', 1, 6, 'Showroom', 'Completed'),
    (1256, '2025-12-15', 2, 3, 'Online', 'Completed'),
    (1257, '2025-12-16', 2, 27, 'B2B Project', 'Completed'),
    (1258, '2025-12-07', 1, 13, 'Online', 'Completed'),
    (1259, '2025-12-20', 3, 28, 'B2B Project', 'Completed'),
    (1260, '2025-12-20', 2, 16, 'Online', 'Completed'),
    (1261, '2025-12-21', 2, 25, 'B2B Project', 'Completed'),
    (1262, '2025-12-06', 1, 13, 'B2B Project', 'Cancelled'),
    (1263, '2025-12-12', 2, 17, 'Online', 'Completed'),
    (1264, '2025-12-12', 3, 22, 'Showroom', 'Completed'),
    (1265, '2025-12-14', 2, 2, 'Online', 'Completed'),
    (1266, '2025-12-08', 1, 22, 'Showroom', 'Completed'),
    (1267, '2025-12-17', 2, 29, 'B2B Project', 'Completed'),
    (1268, '2025-12-06', 2, 23, 'Referral', 'Completed'),
    (1269, '2025-12-23', 1, 9, 'B2B Project', 'Completed'),
    (1270, '2025-12-10', 3, 6, 'Referral', 'Completed');

INSERT INTO sales_order_item (order_id, product_id, quantity, unit_price, unit_cost, discount_pct) VALUES
    (1001, 6, 9, 37242.1, 24862.39, 0.05),
    (1001, 3, 10, 6534.45, 4188.12, 0),
    (1001, 1, 10, 9644.69, 6492.89, 0.075),
    (1002, 1, 16, 9553.92, 6490.93, 0),
    (1002, 10, 3, 124507.46, 84590.05, 0),
    (1003, 2, 4, 32724.2, 21805.1, 0),
    (1004, 10, 3, 122767.53, 84215.09, 0.025),
    (1004, 8, 16, 41462.5, 28237.09, 0.025),
    (1004, 2, 9, 33081.36, 22206.29, 0),
    (1005, 3, 15, 6485.77, 4169.53, 0),
    (1005, 4, 14, 28824.3, 18112.98, 0.025),
    (1005, 8, 8, 41137.56, 27769.93, 0),
    (1005, 2, 18, 33102.38, 21890.37, 0.05),
    (1006, 3, 1, 6600.33, 4222.64, 0),
    (1006, 7, 1, 92017.39, 65411.15, 0.1),
    (1006, 6, 8, 37481.04, 25112.21, 0.05),
    (1006, 2, 10, 33140.42, 22018.93, 0.075),
    (1007, 8, 2, 41361.57, 28136.04, 0.025),
    (1008, 8, 9, 41294.28, 28133.92, 0.1),
    (1008, 4, 12, 28527.99, 18003.86, 0),
    (1008, 10, 5, 127394.86, 85497.22, 0.1),
    (1009, 6, 13, 38110.38, 24986.72, 0.05),
    (1010, 10, 3, 123003.3, 84383.54, 0.075),
    (1010, 4, 11, 28933.69, 18165.97, 0.1),
    (1010, 2, 4, 32784.75, 22127.23, 0.05),
    (1011, 7, 5, 93092.86, 65311.71, 0),
    (1012, 8, 8, 41626.58, 27946.02, 0.075),
    (1012, 5, 7, 5162.06, 2998.24, 0),
    (1013, 9, 4, 10964.32, 7524.19, 0.1),
    (1014, 7, 5, 93116.49, 65601.27, 0.025),
    (1014, 2, 8, 33595.78, 21951.26, 0.025),
    (1015, 6, 6, 38320.58, 24819.51, 0.025),
    (1016, 5, 7, 5253.46, 2989.62, 0.075),
    (1016, 10, 1, 125173.78, 84801.6, 0.075),
    (1016, 1, 5, 9591.13, 6501.5, 0),
    (1016, 6, 8, 37770.83, 25181.41, 0.05),
    (1017, 8, 1, 41076.49, 28100.27, 0.05),
    (1017, 2, 8, 33437.7, 21817.84, 0.075),
    (1018, 1, 10, 9588.46, 6544.1, 0.1),
    (1018, 9, 6, 10834.42, 7539.02, 0),
    (1018, 3, 15, 6475.12, 4180.16, 0.1),
    (1019, 7, 3, 91219.4, 65007.62, 0.05),
    (1019, 3, 7, 6502.25, 4169.35, 0.1),
    (1020, 3, 1, 6541.76, 4186.48, 0.1),
    (1020, 8, 1, 40620.37, 28018.72, 0),
    (1020, 1, 4, 9342.17, 6496.65, 0.075),
    (1021, 5, 7, 5254.32, 3025.24, 0),
    (1021, 10, 1, 123022, 85157.75, 0.05),
    (1022, 10, 5, 124787.74, 85767.68, 0.05),
    (1022, 1, 11, 9445.86, 6495.85, 0),
    (1023, 5, 10, 5183.15, 2996.04, 0.05),
    (1023, 3, 1, 6616.93, 4211.46, 0.075),
    (1023, 10, 3, 125547.6, 84742.22, 0),
    (1023, 8, 7, 40791.99, 27767.46, 0.1),
    (1024, 8, 2, 41621.33, 28100.36, 0),
    (1024, 1, 3, 9446.25, 6477.81, 0.05),
    (1025, 10, 2, 124742.36, 85793.43, 0.025),
    (1025, 3, 9, 6495.49, 4214.91, 0.1),
    (1025, 7, 2, 91790.27, 64540.56, 0.1),
    (1026, 10, 1, 124143.4, 84779.2, 0.1),
    (1026, 1, 3, 9673, 6557.96, 0),
    (1026, 2, 4, 33655.87, 21870.73, 0.1),
    (1027, 1, 11, 9340.99, 6489.11, 0.075),
    (1028, 5, 11, 5196.95, 3026.17, 0),
    (1028, 2, 11, 33271.01, 22024.33, 0.025),
    (1029, 10, 5, 124645.48, 84324.79, 0.05),
    (1029, 6, 13, 38677.68, 24989.56, 0.1),
    (1029, 5, 10, 5232.26, 2996.36, 0.1),
    (1030, 3, 8, 6446.02, 4172.2, 0.1),
    (1030, 6, 5, 38123.33, 25113.67, 0.05),
    (1030, 1, 3, 9419.25, 6441.12, 0),
    (1030, 7, 2, 91839.38, 65597.23, 0),
    (1031, 7, 1, 91795.89, 65363.35, 0.075),
    (1031, 4, 3, 28588.26, 17861.59, 0.05),
    (1031, 2, 10, 32794.04, 22111.48, 0),
    (1031, 3, 8, 6395.29, 4229.93, 0.075),
    (1032, 8, 9, 40681.26, 27731.28, 0),
    (1032, 5, 10, 5119.92, 3000.95, 0.075),
    (1032, 9, 6, 11159.65, 7476.81, 0),
    (1033, 7, 2, 91812.45, 65644.83, 0.1),
    (1033, 9, 2, 10851.94, 7551.81, 0),
    (1033, 8, 6, 40678.03, 27944.85, 0),
    (1033, 1, 5, 9657.05, 6543.03, 0.05),
    (1034, 7, 5, 92644.51, 65251.15, 0.1),
    (1035, 3, 14, 6608.49, 4221.15, 0),
    (1035, 6, 12, 38288.4, 24819.99, 0.075),
    (1036, 9, 8, 10813.94, 7474.11, 0),
    (1036, 6, 9, 38016.2, 25201.89, 0),
    (1036, 4, 2, 28981.06, 18023.11, 0.1),
    (1037, 3, 11, 6556.16, 4171.52, 0.1),
    (1037, 10, 4, 122725.55, 84695.31, 0.075),
    (1037, 8, 18, 40707.11, 28032.93, 0),
    (1037, 1, 6, 9619.21, 6485.93, 0),
    (1038, 2, 8, 33357.59, 22014.22, 0.075),
    (1038, 5, 4, 5166.42, 3016.5, 0.075),
    (1039, 2, 6, 32453.67, 22112.28, 0),
    (1040, 4, 5, 28859.13, 18031.62, 0.05),
    (1041, 4, 12, 28804.5, 17930.46, 0.1),
    (1041, 6, 7, 37792.08, 25035.4, 0),
    (1042, 5, 2, 5164.8, 3002.55, 0.075),
    (1042, 4, 6, 28412.53, 17851.54, 0.05),
    (1042, 3, 9, 6458.12, 4160.31, 0.1),
    (1042, 10, 1, 126641.89, 84924.53, 0.1),
    (1043, 7, 2, 91234.71, 64584.26, 0.075),
    (1043, 3, 1, 6426.04, 4168.58, 0.05),
    (1044, 2, 8, 33497.04, 22162.92, 0.1),
    (1044, 1, 2, 9608.43, 6535.32, 0),
    (1044, 3, 8, 6598.99, 4231.25, 0.1),
    (1044, 5, 10, 5145.55, 3018, 0.075),
    (1045, 7, 2, 92204.08, 65495.56, 0.075),
    (1045, 4, 7, 28668.94, 17857.11, 0),
    (1045, 1, 7, 9372.91, 6513.51, 0.075),
    (1045, 5, 8, 5270.06, 2996.28, 0.075),
    (1046, 8, 4, 40330.31, 28017.81, 0),
    (1046, 5, 10, 5204.68, 2987.8, 0.025),
    (1047, 10, 1, 124120.81, 84332.26, 0),
    (1048, 3, 11, 6522.59, 4232.88, 0.025),
    (1048, 2, 6, 33303.32, 22188.46, 0.075),
    (1048, 9, 6, 10898.81, 7559.23, 0),
    (1049, 8, 5, 41664.81, 27810.37, 0),
    (1050, 4, 4, 28359.33, 18119.33, 0),
    (1050, 1, 8, 9414.6, 6518.46, 0),
    (1050, 2, 7, 33572.83, 21993.33, 0),
    (1051, 4, 2, 28190.49, 17860.61, 0.075),
    (1051, 5, 5, 5173.04, 3001.97, 0.1),
    (1051, 7, 2, 92984.27, 64455.99, 0),
    (1052, 7, 1, 90593.03, 64663.25, 0.075),
    (1052, 1, 9, 9358.65, 6542.09, 0.1),
    (1052, 5, 4, 5137.97, 2986.37, 0.025),
    (1053, 1, 2, 9372.55, 6440.2, 0),
    (1053, 3, 7, 6549.69, 4180.19, 0),
    (1053, 5, 3, 5281.87, 3015.77, 0),
    (1053, 4, 6, 28400.63, 17827.1, 0),
    (1054, 3, 3, 6614, 4227.06, 0.05),
    (1054, 10, 3, 122641.82, 85012.93, 0.075),
    (1054, 2, 1, 33353.33, 22164.78, 0.075),
    (1055, 1, 5, 9359.66, 6559.21, 0.1),
    (1056, 4, 10, 28764.17, 18054.71, 0.05),
    (1056, 3, 9, 6385.74, 4221.09, 0.075),
    (1056, 5, 6, 5131.34, 3018.21, 0),
    (1056, 7, 3, 90534.85, 65276.44, 0),
    (1057, 4, 4, 28022.66, 17896.79, 0.075),
    (1057, 8, 10, 40264.39, 27875.28, 0.1),
    (1057, 6, 1, 37887.98, 24893.34, 0),
    (1057, 9, 7, 11139.6, 7470.49, 0.05),
    (1058, 3, 8, 6577.08, 4199.57, 0.075),
    (1058, 7, 3, 93746.83, 65005.76, 0),
    (1058, 8, 3, 40251.56, 27799.29, 0),
    (1059, 2, 9, 33396.75, 21781.89, 0.05),
    (1060, 2, 2, 33328.71, 22176.28, 0);

INSERT INTO sales_order_item (order_id, product_id, quantity, unit_price, unit_cost, discount_pct) VALUES
    (1061, 9, 1, 11112.79, 7479.51, 0.1),
    (1061, 3, 2, 6479.75, 4187.09, 0.075),
    (1061, 8, 7, 40869.88, 28226.06, 0.025),
    (1061, 5, 5, 5195.7, 2990.13, 0.05),
    (1062, 8, 5, 40437.71, 27940.11, 0.075),
    (1062, 2, 1, 33502.2, 21996.56, 0.075),
    (1063, 5, 11, 5302.28, 2993.4, 0.05),
    (1063, 6, 6, 38250.63, 24878.35, 0.075),
    (1063, 10, 5, 127441.65, 84439.08, 0.05),
    (1064, 8, 9, 41713.49, 28046.04, 0.075),
    (1064, 9, 7, 10800.17, 7534.02, 0),
    (1064, 7, 4, 91437.5, 64481.95, 0.1),
    (1064, 6, 12, 38156.4, 24885.22, 0.025),
    (1065, 9, 11, 10830.42, 7531.38, 0.1),
    (1066, 10, 5, 125298.04, 85513.97, 0.075),
    (1067, 8, 13, 41026.31, 28113.87, 0.05),
    (1067, 9, 11, 10819.22, 7524, 0.075),
    (1068, 3, 4, 6489.99, 4204.21, 0),
    (1069, 2, 17, 32549.2, 22127.08, 0),
    (1069, 10, 3, 125644.36, 84984.16, 0),
    (1069, 8, 9, 40685.7, 28091.42, 0),
    (1069, 5, 12, 5180.04, 2984.27, 0),
    (1070, 4, 1, 28732.73, 17924.75, 0.1),
    (1070, 2, 5, 33359.22, 21860.54, 0),
    (1070, 10, 2, 125616.13, 85203.4, 0.025),
    (1071, 8, 15, 41435.99, 28185.38, 0),
    (1071, 9, 7, 11205.85, 7495.09, 0),
    (1072, 8, 4, 40300.8, 28200.95, 0.075),
    (1072, 2, 1, 33512.81, 22086.79, 0.1),
    (1073, 10, 5, 123857.76, 85064.44, 0),
    (1073, 6, 7, 37825.08, 25033.46, 0),
    (1073, 8, 17, 41316.02, 27939.94, 0.05),
    (1074, 7, 2, 90231.69, 65031.27, 0.05),
    (1074, 9, 9, 10984.96, 7481.05, 0.05),
    (1075, 1, 4, 9664.5, 6521.81, 0.075),
    (1075, 4, 13, 28312.93, 18131.5, 0.025),
    (1075, 9, 11, 10832.15, 7486.84, 0.025),
    (1076, 5, 9, 5228.13, 2974.78, 0.025),
    (1076, 1, 12, 9667.56, 6535.76, 0.05),
    (1076, 7, 4, 93044.34, 65185.39, 0.05),
    (1077, 3, 6, 6373.42, 4186.49, 0.1),
    (1078, 5, 9, 5157.25, 2997.69, 0.075),
    (1078, 2, 10, 32803.24, 21866.98, 0.1),
    (1078, 4, 8, 29014.58, 18024.6, 0),
    (1078, 10, 3, 125063.68, 85730.79, 0),
    (1079, 7, 3, 92160.65, 64422.24, 0.1),
    (1079, 10, 1, 124915.93, 84386.58, 0.05),
    (1079, 1, 3, 9362.44, 6472.97, 0.05),
    (1079, 9, 3, 11206.34, 7524.93, 0),
    (1080, 8, 15, 40919.96, 28114.97, 0.025),
    (1081, 2, 14, 32558.61, 21901.79, 0),
    (1081, 4, 14, 28134.76, 18146.79, 0),
    (1082, 3, 3, 6596.26, 4159.17, 0.05),
    (1082, 4, 6, 28092.85, 18029.01, 0.1),
    (1083, 5, 8, 5238.26, 2993.45, 0),
    (1083, 8, 1, 41611.34, 27742.08, 0.025),
    (1083, 6, 7, 37724.81, 24835.26, 0.1),
    (1084, 1, 16, 9426.68, 6435.47, 0),
    (1084, 6, 17, 37939.18, 24997.47, 0),
    (1085, 8, 9, 41172.63, 27855.86, 0.075),
    (1086, 10, 2, 122876.69, 85230.86, 0),
    (1086, 8, 7, 40937.15, 27916.27, 0.025),
    (1086, 1, 1, 9415.5, 6447.23, 0),
    (1087, 2, 13, 32834.68, 22131.23, 0),
    (1087, 3, 11, 6531.34, 4175.13, 0.1),
    (1087, 6, 17, 37672.59, 25217.8, 0.1),
    (1088, 8, 10, 41368.13, 27915.91, 0.025),
    (1088, 1, 1, 9516.49, 6530.69, 0.025),
    (1089, 8, 10, 41213.03, 28010.86, 0.025),
    (1090, 2, 10, 32457.41, 21837.2, 0.1),
    (1091, 9, 5, 11219.81, 7502.57, 0.1),
    (1091, 7, 1, 92529.72, 65440.49, 0),
    (1091, 5, 1, 5161.26, 2983.99, 0),
    (1091, 1, 10, 9606.72, 6517.19, 0),
    (1092, 4, 8, 28623.52, 18021.78, 0.05),
    (1092, 5, 10, 5251.58, 2976.73, 0.025),
    (1093, 3, 12, 6567.65, 4228.61, 0.05),
    (1094, 6, 12, 38159.49, 25130.95, 0.075),
    (1095, 5, 13, 5301.2, 3014.16, 0.1),
    (1095, 3, 14, 6548.77, 4215.53, 0.075),
    (1095, 4, 17, 29053.16, 17916.36, 0.025),
    (1095, 2, 6, 32967.48, 21819.85, 0.075),
    (1096, 7, 1, 93838.53, 64367.69, 0.05),
    (1096, 2, 4, 33345.34, 22146.77, 0),
    (1096, 6, 10, 38620.7, 25174.2, 0.05),
    (1096, 1, 10, 9388, 6521.17, 0.025),
    (1097, 5, 3, 5155.71, 2997.94, 0.025),
    (1097, 2, 2, 33343.21, 22123.98, 0.05),
    (1097, 7, 3, 91195.93, 64682.52, 0),
    (1097, 10, 2, 126670.23, 85629.73, 0),
    (1098, 8, 4, 41252.54, 28265.64, 0.1),
    (1098, 2, 6, 32452.71, 22020.33, 0.05),
    (1099, 2, 8, 32847.6, 22143.42, 0),
    (1099, 1, 3, 9485.18, 6436.03, 0.025),
    (1100, 9, 6, 11207.36, 7436.2, 0.05),
    (1100, 10, 1, 124417.79, 84663.3, 0.025),
    (1100, 5, 6, 5192.34, 2994.2, 0.025),
    (1100, 6, 7, 37939.22, 25037.9, 0.075),
    (1101, 7, 3, 92211.96, 65170.58, 0),
    (1101, 2, 18, 33212.18, 22091.9, 0.025),
    (1101, 3, 12, 6560.67, 4233.16, 0.025),
    (1102, 10, 1, 124839.4, 85075.88, 0),
    (1102, 3, 1, 6534.09, 4173.55, 0),
    (1102, 9, 1, 10809.63, 7456.76, 0.1),
    (1102, 7, 2, 91897.08, 65641.36, 0.075),
    (1103, 1, 7, 9566.93, 6444.02, 0),
    (1103, 10, 2, 126474.85, 84213.26, 0.025),
    (1104, 4, 5, 28278.7, 18041.26, 0.075),
    (1104, 10, 2, 123295.83, 85171.42, 0),
    (1105, 9, 12, 11215.32, 7493.94, 0.05),
    (1106, 1, 6, 9372.82, 6441.86, 0),
    (1106, 10, 2, 124949.74, 84937.41, 0),
    (1106, 3, 6, 6412.55, 4164.23, 0.05),
    (1106, 9, 6, 10831.09, 7463.74, 0),
    (1107, 10, 2, 126143.79, 84236.49, 0.05),
    (1107, 5, 8, 5215.34, 2971.58, 0.1),
    (1107, 6, 2, 37354.26, 24978.64, 0),
    (1107, 3, 1, 6583.28, 4173.39, 0),
    (1108, 2, 7, 32630.4, 21905.74, 0.05),
    (1108, 9, 2, 11197.19, 7572.67, 0.1),
    (1108, 3, 8, 6419.43, 4179.53, 0),
    (1109, 10, 2, 124553.89, 84585, 0.075),
    (1109, 4, 6, 28814.98, 18030.04, 0.05),
    (1109, 5, 1, 5180.75, 3013.94, 0.05),
    (1110, 10, 2, 126367.13, 85629.93, 0.1),
    (1111, 5, 9, 5141.43, 3002.98, 0),
    (1111, 4, 11, 28964.75, 17840.8, 0),
    (1111, 2, 9, 33100.89, 22205.75, 0.1),
    (1111, 9, 8, 11157.01, 7488.97, 0.075),
    (1112, 10, 4, 124902.38, 84700.25, 0.05),
    (1112, 5, 15, 5302.88, 2986.49, 0),
    (1112, 1, 7, 9328.36, 6477.11, 0),
    (1113, 6, 10, 37332.79, 25141.92, 0.075),
    (1113, 2, 9, 32852.07, 22011.72, 0.075),
    (1114, 3, 3, 6553.68, 4177.85, 0.025),
    (1114, 7, 2, 91456.89, 64896.08, 0),
    (1114, 6, 6, 37762.48, 25030.57, 0.025),
    (1115, 9, 9, 10897.72, 7564.38, 0.1),
    (1115, 8, 8, 41577.34, 28031.44, 0.1),
    (1115, 6, 8, 38132.87, 25000.45, 0.075),
    (1115, 1, 11, 9452.37, 6545.8, 0.05),
    (1116, 6, 5, 37523.34, 24896.28, 0.025),
    (1117, 6, 8, 38679.57, 25141.58, 0.05),
    (1117, 2, 17, 33112.65, 22131.67, 0.075),
    (1118, 10, 5, 123367.53, 84666.48, 0.025),
    (1119, 5, 6, 5197.23, 3004.07, 0.025),
    (1119, 2, 3, 32417.38, 22128.45, 0),
    (1119, 7, 2, 92244.26, 65100.36, 0),
    (1119, 10, 3, 123542.49, 85809.84, 0.1),
    (1120, 6, 7, 38298.03, 25012.92, 0.1);

INSERT INTO sales_order_item (order_id, product_id, quantity, unit_price, unit_cost, discount_pct) VALUES
    (1120, 10, 3, 127406.68, 85027.9, 0),
    (1120, 1, 7, 9514.8, 6497.58, 0),
    (1121, 5, 1, 5116.86, 3025.02, 0.075),
    (1122, 4, 15, 28629.89, 17953.95, 0.025),
    (1122, 8, 14, 41540.12, 28241.76, 0.1),
    (1123, 1, 1, 9577.03, 6516.5, 0.025),
    (1123, 4, 2, 28169.6, 17838.75, 0.05),
    (1123, 8, 2, 41179.54, 28026.06, 0.025),
    (1124, 4, 5, 27930.2, 17930.8, 0.025),
    (1125, 1, 2, 9507.22, 6440.64, 0.075),
    (1125, 6, 4, 38242.29, 24829.88, 0.075),
    (1125, 2, 2, 32994.29, 21981.53, 0),
    (1125, 9, 4, 11191.92, 7499.3, 0.05),
    (1126, 7, 3, 91079.61, 64985.03, 0.1),
    (1127, 10, 3, 125740.95, 84952.36, 0.075),
    (1127, 9, 6, 11052.4, 7549.64, 0.05),
    (1127, 2, 3, 32965.63, 21834.36, 0.075),
    (1127, 7, 2, 92206.39, 64404.57, 0.1),
    (1128, 4, 13, 28219.47, 18030.01, 0.075),
    (1128, 10, 5, 125518.56, 84681.31, 0),
    (1128, 2, 8, 33648.61, 21895.03, 0.05),
    (1128, 9, 15, 11110.56, 7432.52, 0),
    (1129, 3, 9, 6545.05, 4232.55, 0.075),
    (1129, 10, 3, 123012.9, 84922.46, 0.05),
    (1129, 2, 6, 32791.59, 21940.97, 0.05),
    (1129, 9, 6, 11144.4, 7532.74, 0.05),
    (1130, 9, 5, 10964.87, 7545.51, 0.05),
    (1130, 7, 2, 93687.24, 64458.68, 0.1),
    (1131, 3, 9, 6623.76, 4165.58, 0.1),
    (1131, 7, 3, 91970.4, 65088.93, 0),
    (1131, 2, 13, 32350.35, 21988.7, 0),
    (1131, 1, 10, 9373.89, 6461.82, 0.05),
    (1132, 2, 7, 33598.15, 22163.64, 0.05),
    (1132, 8, 6, 41246.18, 28039.41, 0),
    (1133, 5, 2, 5142.45, 2991.58, 0.025),
    (1133, 6, 4, 38189.95, 24945.07, 0),
    (1133, 9, 4, 10870.39, 7525.06, 0.075),
    (1134, 10, 5, 126587.77, 85659.65, 0.1),
    (1134, 3, 5, 6522.06, 4233.64, 0.075),
    (1134, 9, 9, 11110.95, 7550.27, 0.05),
    (1135, 7, 1, 93250.5, 65500.67, 0.025),
    (1135, 10, 3, 125878.49, 85013.02, 0.025),
    (1135, 1, 1, 9540.92, 6506.66, 0),
    (1135, 6, 8, 37670.94, 24960.26, 0.025),
    (1136, 6, 4, 38696.54, 25028.9, 0.05),
    (1136, 9, 4, 10993.88, 7437.26, 0.1),
    (1136, 10, 1, 125517.83, 85494.33, 0.025),
    (1136, 3, 1, 6465.6, 4224.18, 0.05),
    (1137, 1, 3, 9319.62, 6458.78, 0),
    (1137, 4, 8, 28004.39, 18047.79, 0),
    (1137, 3, 7, 6468.29, 4179.7, 0.075),
    (1138, 6, 5, 37463.8, 25132.6, 0.075),
    (1138, 4, 2, 28976.71, 17938.87, 0.05),
    (1138, 5, 6, 5188.56, 3007.39, 0.025),
    (1139, 9, 1, 10878.42, 7538.2, 0.075),
    (1139, 8, 5, 40951.93, 28166.96, 0.075),
    (1139, 1, 7, 9641.12, 6521.76, 0.075),
    (1139, 2, 1, 33350.91, 22207.79, 0),
    (1140, 4, 8, 28113.97, 17919.72, 0.025),
    (1140, 2, 10, 32449.76, 22079.28, 0.05),
    (1140, 6, 3, 38454.36, 24919.11, 0),
    (1140, 1, 6, 9434.6, 6505.44, 0.1),
    (1141, 3, 8, 6626.61, 4184.06, 0),
    (1142, 8, 1, 40769.66, 27891.26, 0),
    (1143, 1, 9, 9626.82, 6454.15, 0.025),
    (1143, 3, 11, 6451.73, 4179.75, 0.075),
    (1143, 5, 8, 5294.48, 3023.11, 0),
    (1143, 9, 9, 11044.22, 7499.88, 0),
    (1144, 8, 10, 41476.62, 27894.71, 0.075),
    (1144, 6, 1, 37849.61, 25233.28, 0.1),
    (1144, 2, 1, 32871.85, 21796.57, 0.05),
    (1144, 7, 1, 90550.49, 64365.44, 0.075),
    (1145, 4, 15, 28869.35, 17847.11, 0.05),
    (1145, 1, 13, 9547.07, 6479.98, 0.1),
    (1146, 10, 3, 124309.59, 85533.43, 0),
    (1147, 2, 10, 32896.59, 21783.51, 0.05),
    (1147, 10, 3, 123144.81, 85707.5, 0),
    (1147, 8, 8, 41159.65, 28167.73, 0.1),
    (1148, 10, 2, 127355.27, 85636.25, 0.1),
    (1148, 3, 2, 6386.98, 4166.53, 0.05),
    (1148, 2, 7, 33398.72, 21960.75, 0.1),
    (1148, 7, 2, 90226.07, 65309.09, 0),
    (1149, 1, 2, 9475.21, 6483.73, 0.025),
    (1149, 8, 2, 40613.52, 27770.87, 0.075),
    (1149, 4, 10, 28240.71, 18036.08, 0.025),
    (1150, 6, 8, 38123.21, 24893.7, 0.1),
    (1151, 6, 4, 37847.15, 24795.02, 0),
    (1151, 4, 2, 28779.74, 17823.43, 0.075),
    (1151, 8, 2, 40917.71, 28049.96, 0.075),
    (1151, 5, 10, 5143.25, 3023.68, 0.025),
    (1152, 8, 7, 40269.63, 28171.67, 0),
    (1153, 2, 1, 33571.69, 22064.19, 0.05),
    (1153, 5, 7, 5203.63, 2989.67, 0),
    (1154, 2, 6, 33495.15, 22206.78, 0.075),
    (1154, 1, 8, 9349.1, 6463.02, 0.05),
    (1154, 3, 4, 6563.41, 4233.96, 0),
    (1154, 5, 3, 5171.43, 2974.59, 0.075),
    (1155, 10, 3, 125410.11, 84949.13, 0.1),
    (1155, 6, 11, 37672.48, 24770.67, 0.025),
    (1155, 2, 9, 32544.16, 22215.91, 0.025),
    (1156, 5, 6, 5114.67, 2984.44, 0.05),
    (1157, 1, 8, 9517.38, 6544.85, 0),
    (1158, 4, 13, 28572.57, 18018.09, 0.05),
    (1158, 8, 10, 41630.54, 27763.31, 0),
    (1158, 7, 5, 92947.32, 64905.53, 0),
    (1159, 5, 11, 5209.91, 2999.21, 0.025),
    (1159, 3, 4, 6558.77, 4162.74, 0.1),
    (1159, 10, 5, 124966.76, 84884.71, 0),
    (1160, 1, 13, 9561.04, 6535.14, 0.075),
    (1160, 2, 8, 33030.37, 21881.42, 0),
    (1160, 8, 6, 40805.05, 28094.65, 0),
    (1160, 6, 12, 38107.26, 24797.07, 0.05),
    (1161, 1, 5, 9554.92, 6505.91, 0),
    (1161, 8, 1, 40784.94, 27836.74, 0),
    (1161, 10, 3, 125052.35, 84838.28, 0),
    (1161, 6, 4, 38589.9, 24894.34, 0),
    (1162, 7, 5, 90374.7, 65229.52, 0),
    (1163, 6, 10, 37403.4, 25175.77, 0.05),
    (1163, 10, 4, 124877.76, 85707.05, 0.1),
    (1164, 9, 9, 11045.27, 7443.45, 0.025),
    (1164, 5, 3, 5172.89, 3009.22, 0.1),
    (1165, 4, 6, 29019.08, 18083.08, 0.1),
    (1166, 1, 8, 9464.4, 6494.82, 0),
    (1166, 6, 6, 37661.33, 24824.22, 0.1),
    (1167, 1, 11, 9625.86, 6452.65, 0),
    (1168, 10, 2, 123063.8, 85685.68, 0.025),
    (1168, 1, 2, 9455.35, 6494.59, 0),
    (1168, 6, 9, 37670.37, 24914.88, 0),
    (1168, 8, 10, 40994.45, 28252.33, 0),
    (1169, 1, 1, 9316.34, 6555, 0.075),
    (1169, 9, 2, 10812.1, 7552.08, 0),
    (1169, 4, 7, 28053.75, 17852.97, 0.075),
    (1170, 8, 9, 40628.59, 27744.14, 0.1),
    (1170, 10, 3, 123847.18, 85844.43, 0.05),
    (1170, 7, 3, 92555.01, 64765.61, 0.05),
    (1170, 6, 12, 37678.97, 24846.29, 0),
    (1171, 8, 13, 41649.93, 27849.53, 0.075),
    (1171, 2, 11, 33242.14, 22065.86, 0),
    (1171, 9, 11, 11125.28, 7523.31, 0.025),
    (1172, 5, 1, 5159.65, 2983.28, 0.025),
    (1172, 3, 6, 6552.82, 4166.9, 0.05),
    (1173, 7, 1, 91178.35, 65452.4, 0.025),
    (1173, 8, 8, 40535.5, 28001.53, 0.075),
    (1173, 6, 10, 38010.4, 25238.1, 0.025),
    (1174, 8, 1, 40810.81, 27964.79, 0.1),
    (1174, 7, 3, 91936.52, 64623.24, 0),
    (1174, 2, 8, 33145.73, 22046.1, 0.1),
    (1175, 6, 7, 38749.69, 25115.23, 0.025),
    (1175, 3, 5, 6548.59, 4197.99, 0.05),
    (1176, 8, 10, 40777.09, 28122, 0.075);

INSERT INTO sales_order_item (order_id, product_id, quantity, unit_price, unit_cost, discount_pct) VALUES
    (1176, 3, 3, 6383.17, 4225.44, 0.025),
    (1176, 1, 1, 9459.55, 6507.3, 0.05),
    (1176, 10, 1, 127242.25, 85513.04, 0.1),
    (1177, 4, 10, 27979.51, 18110.87, 0.1),
    (1178, 5, 7, 5154.29, 3017.58, 0.075),
    (1178, 10, 1, 126663.85, 85354.56, 0.1),
    (1178, 6, 8, 37514, 25150.42, 0.075),
    (1178, 7, 1, 92948.87, 65479.19, 0),
    (1179, 4, 6, 28695.82, 18073.05, 0.075),
    (1180, 1, 8, 9622.38, 6463.5, 0),
    (1180, 8, 14, 40578.1, 27916.99, 0.1),
    (1180, 7, 3, 90426.66, 64426.06, 0.1),
    (1181, 7, 3, 93335.28, 65442.76, 0.1),
    (1182, 10, 1, 122710.02, 84595.99, 0.075),
    (1182, 7, 2, 90484.41, 65224.11, 0.1),
    (1183, 6, 3, 37651.24, 25236.55, 0.025),
    (1184, 3, 1, 6429.48, 4193.45, 0.05),
    (1184, 10, 1, 125865.36, 84856.88, 0.025),
    (1185, 9, 7, 11161.75, 7431.55, 0),
    (1185, 6, 5, 37955.72, 25066.71, 0.05),
    (1185, 10, 1, 124085.2, 85837.56, 0.075),
    (1185, 1, 2, 9310.56, 6545.06, 0.1),
    (1186, 9, 10, 11089.65, 7474.66, 0.1),
    (1186, 8, 8, 41158.46, 28251.18, 0.025),
    (1187, 10, 5, 126082.36, 85470.01, 0),
    (1187, 4, 9, 28780.53, 17831.46, 0.075),
    (1188, 6, 11, 38507.67, 24938.51, 0.1),
    (1189, 1, 14, 9551.01, 6512.7, 0.025),
    (1189, 8, 10, 41373.99, 28074.35, 0.1),
    (1189, 9, 10, 10868.92, 7443.38, 0),
    (1190, 7, 2, 91119.77, 65154.81, 0),
    (1190, 10, 2, 124940.17, 85629.9, 0.025),
    (1190, 8, 1, 41406.09, 27955.85, 0),
    (1191, 3, 4, 6402.25, 4159.94, 0),
    (1191, 5, 1, 5113.65, 3002.22, 0.05),
    (1191, 7, 1, 93451.22, 64930.54, 0),
    (1192, 4, 4, 28884.78, 17989.33, 0.1),
    (1193, 1, 11, 9646.26, 6490.08, 0.1),
    (1193, 6, 17, 37388.92, 25062.3, 0.05),
    (1194, 10, 2, 123573.46, 85248.16, 0),
    (1194, 2, 7, 33292.25, 22080.84, 0),
    (1194, 9, 1, 10996.58, 7551.75, 0.075),
    (1195, 3, 10, 6471.86, 4164.14, 0),
    (1195, 9, 9, 11174.07, 7513.07, 0.075),
    (1196, 3, 8, 6378.4, 4208.73, 0),
    (1197, 1, 3, 9602.89, 6533.12, 0),
    (1197, 5, 10, 5133.04, 3012.69, 0.025),
    (1198, 1, 13, 9457.61, 6486.11, 0.1),
    (1198, 4, 7, 28794.92, 18094.61, 0.025),
    (1198, 9, 8, 11015.27, 7564.6, 0.1),
    (1199, 6, 7, 38542.7, 24972.35, 0.025),
    (1199, 3, 6, 6527.99, 4227.39, 0.075),
    (1200, 9, 14, 10852.16, 7457.59, 0.075),
    (1200, 3, 11, 6386.49, 4197.08, 0.075),
    (1201, 2, 1, 33059.56, 21826.51, 0.1),
    (1202, 2, 9, 32385.38, 22155.24, 0),
    (1202, 5, 3, 5145.33, 3027.74, 0.05),
    (1203, 6, 5, 37367.67, 25243.92, 0.05),
    (1204, 9, 7, 10869.53, 7479.68, 0.05),
    (1204, 3, 12, 6484.37, 4211.03, 0.075),
    (1205, 9, 10, 10897.52, 7485.09, 0.1),
    (1206, 4, 3, 28461.87, 18023.04, 0),
    (1207, 6, 10, 38389.32, 25121.68, 0.025),
    (1207, 5, 7, 5258.48, 3011.25, 0.075),
    (1207, 1, 3, 9546.67, 6545.47, 0.05),
    (1207, 8, 2, 41079.39, 27972.49, 0.1),
    (1208, 6, 13, 38531.78, 24857.32, 0.025),
    (1208, 10, 3, 122570.49, 85693.59, 0),
    (1209, 6, 17, 37507.32, 24891.07, 0.075),
    (1209, 5, 13, 5257.76, 2995.13, 0.025),
    (1209, 3, 16, 6476.7, 4170.88, 0.025),
    (1210, 9, 1, 10953.27, 7513.44, 0.1),
    (1210, 7, 2, 93363.04, 64678.25, 0.05),
    (1210, 1, 8, 9566.11, 6441.43, 0.1),
    (1211, 9, 3, 11132.5, 7480.18, 0.025),
    (1211, 5, 3, 5289.96, 3025.05, 0.05),
    (1211, 7, 3, 90889.22, 64553.6, 0.05),
    (1211, 1, 10, 9593.59, 6550.78, 0.05),
    (1212, 6, 4, 38051.11, 25167.19, 0.1),
    (1213, 7, 2, 93219.31, 64789.54, 0.075),
    (1213, 8, 10, 40974.13, 27846.53, 0.075),
    (1213, 10, 2, 126114.63, 85841.39, 0),
    (1213, 9, 2, 11040.51, 7434.45, 0),
    (1214, 7, 3, 91153.22, 64561.52, 0.05),
    (1214, 2, 13, 33341.86, 21980.26, 0.075),
    (1214, 4, 9, 27947.23, 17911.2, 0.1),
    (1214, 8, 16, 41466.86, 27850.3, 0.1),
    (1215, 3, 9, 6511.73, 4205.55, 0.05),
    (1215, 4, 7, 28024.47, 17825.76, 0.05),
    (1215, 8, 4, 41476.32, 28154.24, 0.025),
    (1215, 10, 1, 124379.71, 84755.65, 0),
    (1216, 8, 2, 40970.87, 28157.27, 0.075),
    (1216, 9, 3, 11079.44, 7523.99, 0.025),
    (1216, 4, 5, 28647.72, 18003.96, 0.05),
    (1217, 3, 8, 6428.85, 4167.17, 0.075),
    (1217, 9, 1, 10795.96, 7447.32, 0.075),
    (1218, 5, 7, 5201.94, 3004.11, 0.025),
    (1218, 4, 9, 28761.69, 17941.29, 0.1),
    (1218, 2, 8, 32910.03, 22091.58, 0.025),
    (1218, 10, 5, 127280.98, 84465.7, 0.025),
    (1219, 4, 1, 28425.21, 18089.58, 0.1),
    (1219, 7, 1, 91429.71, 64965.55, 0.05),
    (1219, 8, 1, 41094.06, 28110.67, 0),
    (1219, 9, 3, 10875.31, 7488.68, 0),
    (1220, 4, 6, 28462.94, 18014.89, 0),
    (1220, 7, 3, 91463.94, 64499.52, 0.05),
    (1220, 2, 2, 32860.35, 21783.9, 0),
    (1220, 9, 1, 10861.87, 7485.55, 0),
    (1221, 3, 7, 6400.23, 4232.31, 0.025),
    (1221, 10, 3, 127162.23, 85148.97, 0.025),
    (1221, 4, 4, 28162.3, 18069.68, 0),
    (1221, 8, 3, 41397.47, 27868.97, 0.05),
    (1222, 5, 9, 5226.81, 3024.07, 0),
    (1222, 1, 10, 9614.2, 6437.5, 0.025),
    (1223, 1, 7, 9606.24, 6559.76, 0),
    (1223, 2, 7, 32352.45, 22176.33, 0.1),
    (1223, 9, 7, 11135.8, 7559.16, 0.075),
    (1223, 3, 10, 6406.94, 4241.08, 0),
    (1224, 3, 4, 6554.66, 4201.17, 0),
    (1224, 7, 3, 91445.98, 65582.16, 0.05),
    (1224, 8, 10, 41037.6, 28110.39, 0.025),
    (1224, 5, 14, 5161.85, 2980.32, 0.025),
    (1225, 1, 7, 9587.88, 6483.66, 0.05),
    (1225, 5, 6, 5131.59, 3014.08, 0),
    (1226, 1, 8, 9417.95, 6440.19, 0.1),
    (1226, 5, 9, 5100.33, 2973.31, 0.075),
    (1226, 6, 5, 37279.14, 24818.92, 0),
    (1227, 4, 6, 28510.85, 18128.9, 0),
    (1227, 5, 3, 5283.25, 2985.55, 0.075),
    (1228, 10, 3, 126228.64, 84809.14, 0),
    (1229, 3, 14, 6459.9, 4231.98, 0.075),
    (1230, 7, 3, 90576.3, 65420.35, 0),
    (1230, 6, 11, 37443.53, 24763.83, 0),
    (1230, 1, 12, 9389.83, 6560.61, 0.025),
    (1231, 2, 8, 33456.7, 22030.42, 0),
    (1231, 10, 3, 123561.58, 84589.63, 0.1),
    (1232, 8, 9, 41313.45, 28197.77, 0.1),
    (1232, 5, 6, 5265.36, 2983.45, 0),
    (1232, 2, 6, 32917.84, 22205.71, 0.1),
    (1232, 6, 6, 38484.27, 25223.84, 0),
    (1233, 10, 1, 123757.67, 85731.09, 0),
    (1234, 9, 3, 10877.48, 7523.65, 0.05),
    (1235, 4, 16, 28458.75, 18030.11, 0.1),
    (1236, 10, 1, 126314.66, 84273.67, 0.05),
    (1237, 9, 6, 11207.82, 7558.42, 0.05),
    (1238, 2, 13, 33300.96, 21925.55, 0.1),
    (1238, 7, 5, 90392.26, 65517.61, 0.025),
    (1238, 5, 13, 5199.66, 2990.52, 0),
    (1238, 3, 13, 6511.31, 4239.53, 0),
    (1239, 8, 10, 41530.55, 27967.97, 0);

INSERT INTO sales_order_item (order_id, product_id, quantity, unit_price, unit_cost, discount_pct) VALUES
    (1240, 1, 2, 9443.45, 6446.61, 0),
    (1240, 10, 3, 126531.12, 84634.45, 0.05),
    (1240, 7, 1, 90189.85, 65185.07, 0),
    (1240, 6, 2, 38472.25, 25089.53, 0.1),
    (1241, 8, 9, 41237.87, 27849.29, 0.075),
    (1241, 3, 4, 6402.39, 4218.82, 0.1),
    (1242, 10, 5, 124060.09, 84219.61, 0),
    (1242, 9, 12, 10963.65, 7468.17, 0),
    (1242, 5, 5, 5276.57, 3000.92, 0.025),
    (1243, 6, 12, 37683.58, 24978.6, 0.05),
    (1243, 4, 12, 27933.07, 17837.87, 0.05),
    (1244, 7, 1, 92424.5, 64603.92, 0),
    (1244, 3, 4, 6553.37, 4176.93, 0.1),
    (1244, 4, 1, 28308.2, 17966.98, 0.1),
    (1245, 3, 7, 6411.11, 4215.16, 0.1),
    (1246, 6, 10, 37591.1, 24928.57, 0.075),
    (1246, 4, 9, 28919.01, 18114.81, 0.05),
    (1246, 9, 7, 10884.81, 7475.01, 0.05),
    (1247, 7, 3, 91991.37, 65137.48, 0.1),
    (1247, 8, 1, 41170.97, 28024.37, 0.05),
    (1247, 3, 10, 6450.69, 4202.76, 0.05),
    (1247, 1, 7, 9575.6, 6546.87, 0),
    (1248, 3, 10, 6571.12, 4169.93, 0.075),
    (1248, 2, 10, 32833.87, 21806.53, 0.05),
    (1248, 8, 6, 41661.01, 28153.72, 0),
    (1248, 7, 4, 91382.32, 64481.03, 0),
    (1249, 7, 1, 91033.48, 64871.16, 0.025),
    (1250, 6, 1, 37637.14, 25038.67, 0.025),
    (1250, 3, 2, 6515.2, 4225.69, 0.075),
    (1250, 1, 6, 9331.28, 6512.03, 0),
    (1251, 3, 7, 6555.16, 4160.56, 0.1),
    (1252, 2, 16, 32348, 22139.87, 0.05),
    (1252, 3, 16, 6394.1, 4215.14, 0.05),
    (1252, 5, 15, 5287.46, 3027.55, 0.1),
    (1253, 5, 6, 5259.97, 3006.01, 0),
    (1254, 3, 9, 6610.49, 4206.2, 0.025),
    (1254, 10, 5, 124431.79, 85349.9, 0.05),
    (1255, 9, 9, 11204.36, 7431.68, 0.025),
    (1255, 3, 10, 6613.82, 4220.35, 0.05),
    (1255, 5, 9, 5145.6, 2983.8, 0),
    (1256, 6, 10, 38272.55, 25070.33, 0.1),
    (1256, 10, 3, 126079.13, 85186.26, 0.1),
    (1256, 5, 8, 5163.74, 3019.67, 0.075),
    (1257, 5, 8, 5114.93, 2988.9, 0),
    (1258, 7, 1, 90806.74, 65189.68, 0.05),
    (1258, 1, 10, 9479.83, 6459.31, 0),
    (1259, 7, 4, 90987.37, 64804.48, 0),
    (1259, 5, 7, 5246.3, 2988.59, 0),
    (1259, 10, 3, 122643.26, 84156.88, 0.05),
    (1259, 6, 8, 38464.08, 24944.51, 0.025),
    (1260, 8, 2, 41224.45, 28224.48, 0.075),
    (1260, 2, 6, 33167.04, 21928.81, 0.075),
    (1261, 10, 4, 124868.31, 85159.69, 0),
    (1261, 9, 10, 10945.8, 7517.01, 0),
    (1261, 4, 11, 28670.05, 18068.31, 0.075),
    (1261, 8, 11, 41542.53, 27768.88, 0.1),
    (1262, 1, 9, 9310.92, 6546.16, 0),
    (1263, 4, 10, 28872.46, 17902.2, 0.1),
    (1263, 1, 4, 9567.58, 6561.88, 0.1),
    (1263, 6, 3, 37601.41, 25043.06, 0),
    (1264, 2, 9, 32696.4, 22075.93, 0.075),
    (1265, 4, 5, 28760.92, 18032.43, 0.1),
    (1265, 8, 4, 41218.7, 27894.58, 0.05),
    (1266, 8, 9, 40597.59, 28192.84, 0),
    (1266, 4, 2, 28716.79, 17915.8, 0),
    (1266, 9, 9, 11161.56, 7550.1, 0.075),
    (1266, 6, 5, 38303.97, 25159.96, 0.1),
    (1267, 10, 3, 126558.39, 85037.72, 0.075),
    (1267, 6, 8, 38278, 24914.57, 0),
    (1268, 10, 1, 123864.88, 85646.22, 0.05),
    (1268, 2, 6, 33436.19, 22076.01, 0.025),
    (1268, 9, 6, 10854.88, 7428.01, 0.1),
    (1268, 5, 2, 5135.67, 2992.19, 0.1),
    (1269, 5, 4, 5205.78, 2987.58, 0.025),
    (1269, 3, 11, 6467.14, 4230.32, 0.075),
    (1270, 2, 1, 32341.16, 22093.42, 0.075);

INSERT INTO inventory_snapshot (snapshot_date, store_id, product_id, opening_stock, received_qty, sold_qty, closing_stock) VALUES
    ('2025-01-31', 1, 1, 57, 12, 24, 45),
    ('2025-01-31', 1, 2, 50, 26, 45, 31),
    ('2025-01-31', 1, 3, 99, 7, 42, 64),
    ('2025-01-31', 1, 4, 28, 29, 37, 20),
    ('2025-01-31', 1, 5, 55, 37, 14, 78),
    ('2025-01-31', 1, 6, 36, 14, 30, 20),
    ('2025-01-31', 1, 7, 50, 0, 6, 44),
    ('2025-01-31', 1, 8, 49, 22, 44, 27),
    ('2025-01-31', 1, 9, 81, 0, 10, 71),
    ('2025-01-31', 1, 10, 28, 2, 12, 18),
    ('2025-01-31', 2, 1, 35, 19, 5, 49),
    ('2025-01-31', 2, 2, 33, 4, 8, 29),
    ('2025-01-31', 2, 3, 52, 12, 7, 57),
    ('2025-01-31', 2, 4, 48, 4, 0, 52),
    ('2025-01-31', 2, 5, 91, 13, 7, 97),
    ('2025-01-31', 2, 6, 28, 7, 14, 21),
    ('2025-01-31', 2, 7, 50, 0, 3, 47),
    ('2025-01-31', 2, 8, 53, 7, 1, 59),
    ('2025-01-31', 2, 9, 84, 0, 0, 84),
    ('2025-01-31', 2, 10, 55, 0, 1, 54),
    ('2025-01-31', 3, 1, 45, 8, 0, 53),
    ('2025-01-31', 3, 2, 59, 1, 0, 60),
    ('2025-01-31', 3, 3, 47, 9, 0, 56),
    ('2025-01-31', 3, 4, 41, 0, 0, 41),
    ('2025-01-31', 3, 5, 56, 10, 0, 66),
    ('2025-01-31', 3, 6, 35, 0, 0, 35),
    ('2025-01-31', 3, 7, 58, 0, 0, 58),
    ('2025-01-31', 3, 8, 40, 1, 0, 41),
    ('2025-01-31', 3, 9, 47, 22, 0, 69),
    ('2025-01-31', 3, 10, 58, 0, 0, 58),
    ('2025-02-28', 1, 1, 45, 14, 22, 37),
    ('2025-02-28', 1, 2, 31, 34, 39, 26),
    ('2025-02-28', 1, 3, 64, 0, 9, 55),
    ('2025-02-28', 1, 4, 20, 15, 15, 20),
    ('2025-02-28', 1, 5, 78, 40, 45, 73),
    ('2025-02-28', 1, 6, 20, 22, 20, 22),
    ('2025-02-28', 1, 7, 44, 3, 8, 39),
    ('2025-02-28', 1, 8, 27, 32, 24, 35),
    ('2025-02-28', 1, 9, 71, 4, 8, 67),
    ('2025-02-28', 1, 10, 18, 2, 9, 11),
    ('2025-02-28', 2, 1, 49, 9, 9, 49),
    ('2025-02-28', 2, 2, 29, 0, 0, 29),
    ('2025-02-28', 2, 3, 57, 19, 19, 57),
    ('2025-02-28', 2, 4, 52, 2, 7, 47),
    ('2025-02-28', 2, 5, 97, 0, 0, 97),
    ('2025-02-28', 2, 6, 21, 18, 14, 25),
    ('2025-02-28', 2, 7, 47, 0, 2, 45),
    ('2025-02-28', 2, 8, 59, 7, 18, 48),
    ('2025-02-28', 2, 9, 84, 4, 8, 80),
    ('2025-02-28', 2, 10, 54, 1, 4, 51),
    ('2025-02-28', 3, 1, 53, 0, 0, 53),
    ('2025-02-28', 3, 2, 60, 7, 0, 67),
    ('2025-02-28', 3, 3, 56, 34, 23, 67),
    ('2025-02-28', 3, 4, 41, 0, 0, 41),
    ('2025-02-28', 3, 5, 66, 8, 0, 74),
    ('2025-02-28', 3, 6, 35, 0, 12, 23),
    ('2025-02-28', 3, 7, 58, 2, 2, 58),
    ('2025-02-28', 3, 8, 41, 0, 0, 41),
    ('2025-02-28', 3, 9, 69, 8, 0, 77),
    ('2025-02-28', 3, 10, 58, 0, 2, 56),
    ('2025-03-31', 1, 1, 37, 13, 9, 41),
    ('2025-03-31', 1, 2, 26, 5, 9, 22),
    ('2025-03-31', 1, 3, 55, 21, 19, 57),
    ('2025-03-31', 1, 4, 20, 5, 7, 18),
    ('2025-03-31', 1, 5, 73, 20, 28, 65),
    ('2025-03-31', 1, 6, 22, 10, 12, 20),
    ('2025-03-31', 1, 7, 39, 0, 9, 30),
    ('2025-03-31', 1, 8, 35, 11, 16, 30),
    ('2025-03-31', 1, 9, 67, 0, 7, 60),
    ('2025-03-31', 1, 10, 11, 1, 3, 9),
    ('2025-03-31', 2, 1, 49, 12, 0, 61),
    ('2025-03-31', 2, 2, 29, 3, 6, 26),
    ('2025-03-31', 2, 3, 57, 29, 31, 55),
    ('2025-03-31', 2, 4, 47, 0, 18, 29),
    ('2025-03-31', 2, 5, 97, 13, 29, 81),
    ('2025-03-31', 2, 6, 25, 2, 6, 21),
    ('2025-03-31', 2, 7, 45, 1, 5, 41),
    ('2025-03-31', 2, 8, 48, 7, 12, 43),
    ('2025-03-31', 2, 9, 80, 2, 7, 75),
    ('2025-03-31', 2, 10, 51, 0, 12, 39),
    ('2025-03-31', 3, 1, 53, 1, 16, 38),
    ('2025-03-31', 3, 2, 67, 1, 2, 66),
    ('2025-03-31', 3, 3, 67, 0, 8, 59),
    ('2025-03-31', 3, 4, 41, 0, 10, 31),
    ('2025-03-31', 3, 5, 74, 0, 7, 67),
    ('2025-03-31', 3, 6, 23, 2, 1, 24),
    ('2025-03-31', 3, 7, 58, 0, 3, 55),
    ('2025-03-31', 3, 8, 41, 3, 10, 34),
    ('2025-03-31', 3, 9, 77, 0, 18, 59),
    ('2025-03-31', 3, 10, 56, 0, 0, 56),
    ('2025-04-30', 1, 1, 41, 22, 19, 44),
    ('2025-04-30', 1, 2, 22, 41, 42, 21),
    ('2025-04-30', 1, 3, 57, 1, 4, 54),
    ('2025-04-30', 1, 4, 18, 22, 22, 18),
    ('2025-04-30', 1, 5, 65, 26, 21, 70),
    ('2025-04-30', 1, 6, 20, 19, 17, 22),
    ('2025-04-30', 1, 7, 30, 0, 5, 25),
    ('2025-04-30', 1, 8, 30, 28, 28, 30),
    ('2025-04-30', 1, 9, 60, 10, 12, 58),
    ('2025-04-30', 1, 10, 9, 7, 7, 9),
    ('2025-04-30', 2, 1, 61, 9, 4, 66),
    ('2025-04-30', 2, 2, 26, 7, 5, 28),
    ('2025-04-30', 2, 3, 55, 17, 0, 72),
    ('2025-04-30', 2, 4, 29, 2, 14, 17),
    ('2025-04-30', 2, 5, 81, 0, 0, 81),
    ('2025-04-30', 2, 6, 21, 9, 7, 23),
    ('2025-04-30', 2, 7, 41, 0, 0, 41),
    ('2025-04-30', 2, 8, 43, 7, 17, 33),
    ('2025-04-30', 2, 9, 75, 6, 11, 70),
    ('2025-04-30', 2, 10, 39, 0, 7, 32),
    ('2025-04-30', 3, 1, 38, 9, 0, 47),
    ('2025-04-30', 3, 2, 66, 0, 0, 66),
    ('2025-04-30', 3, 3, 59, 4, 9, 54),
    ('2025-04-30', 3, 4, 31, 5, 6, 30),
    ('2025-04-30', 3, 5, 67, 16, 8, 75),
    ('2025-04-30', 3, 6, 24, 7, 7, 24),
    ('2025-04-30', 3, 7, 55, 0, 0, 55),
    ('2025-04-30', 3, 8, 34, 9, 16, 27),
    ('2025-04-30', 3, 9, 59, 0, 7, 52),
    ('2025-04-30', 3, 10, 56, 0, 0, 56),
    ('2025-05-31', 1, 1, 44, 22, 20, 46),
    ('2025-05-31', 1, 2, 21, 18, 18, 21),
    ('2025-05-31', 1, 3, 54, 17, 0, 71),
    ('2025-05-31', 1, 4, 18, 5, 5, 18),
    ('2025-05-31', 1, 5, 70, 14, 0, 84),
    ('2025-05-31', 1, 6, 22, 19, 22, 19),
    ('2025-05-31', 1, 7, 25, 0, 1, 24),
    ('2025-05-31', 1, 8, 30, 24, 14, 40),
    ('2025-05-31', 1, 9, 58, 12, 12, 58),
    ('2025-05-31', 1, 10, 9, 7, 4, 12),
    ('2025-05-31', 2, 1, 66, 0, 2, 64),
    ('2025-05-31', 2, 2, 28, 7, 8, 27),
    ('2025-05-31', 2, 3, 72, 18, 26, 64),
    ('2025-05-31', 2, 4, 17, 15, 17, 15),
    ('2025-05-31', 2, 5, 81, 21, 22, 80),
    ('2025-05-31', 2, 6, 23, 7, 7, 23),
    ('2025-05-31', 2, 7, 41, 0, 3, 38),
    ('2025-05-31', 2, 8, 33, 13, 17, 29),
    ('2025-05-31', 2, 9, 70, 0, 6, 64),
    ('2025-05-31', 2, 10, 32, 3, 5, 30),
    ('2025-05-31', 3, 1, 47, 8, 10, 45),
    ('2025-05-31', 3, 2, 66, 0, 23, 43),
    ('2025-05-31', 3, 3, 54, 18, 12, 60),
    ('2025-05-31', 3, 4, 30, 0, 8, 22),
    ('2025-05-31', 3, 5, 75, 17, 11, 81),
    ('2025-05-31', 3, 6, 24, 14, 17, 21),
    ('2025-05-31', 3, 7, 55, 0, 3, 52),
    ('2025-05-31', 3, 8, 27, 5, 0, 32),
    ('2025-05-31', 3, 9, 52, 11, 6, 57),
    ('2025-05-31', 3, 10, 56, 0, 1, 55);

INSERT INTO inventory_snapshot (snapshot_date, store_id, product_id, opening_stock, received_qty, sold_qty, closing_stock) VALUES
    ('2025-06-30', 1, 1, 46, 8, 12, 42),
    ('2025-06-30', 1, 2, 21, 55, 41, 35),
    ('2025-06-30', 1, 3, 71, 0, 12, 59),
    ('2025-06-30', 1, 4, 18, 17, 11, 24),
    ('2025-06-30', 1, 5, 84, 0, 2, 82),
    ('2025-06-30', 1, 6, 19, 30, 28, 21),
    ('2025-06-30', 1, 7, 24, 0, 8, 16),
    ('2025-06-30', 1, 8, 40, 0, 0, 40),
    ('2025-06-30', 1, 9, 58, 6, 4, 60),
    ('2025-06-30', 1, 10, 12, 2, 2, 12),
    ('2025-06-30', 2, 1, 64, 4, 19, 49),
    ('2025-06-30', 2, 2, 27, 3, 3, 27),
    ('2025-06-30', 2, 3, 64, 6, 1, 69),
    ('2025-06-30', 2, 4, 15, 21, 17, 19),
    ('2025-06-30', 2, 5, 80, 3, 8, 75),
    ('2025-06-30', 2, 6, 23, 23, 22, 24),
    ('2025-06-30', 2, 7, 38, 0, 2, 36),
    ('2025-06-30', 2, 8, 29, 21, 24, 26),
    ('2025-06-30', 2, 9, 64, 0, 15, 49),
    ('2025-06-30', 2, 10, 30, 0, 10, 20),
    ('2025-06-30', 3, 1, 45, 8, 7, 46),
    ('2025-06-30', 3, 2, 43, 0, 15, 28),
    ('2025-06-30', 3, 3, 60, 10, 8, 62),
    ('2025-06-30', 3, 4, 22, 11, 13, 20),
    ('2025-06-30', 3, 5, 81, 11, 15, 77),
    ('2025-06-30', 3, 6, 21, 5, 0, 26),
    ('2025-06-30', 3, 7, 52, 0, 2, 50),
    ('2025-06-30', 3, 8, 32, 0, 0, 32),
    ('2025-06-30', 3, 9, 57, 19, 22, 54),
    ('2025-06-30', 3, 10, 55, 0, 9, 46),
    ('2025-07-31', 1, 1, 42, 36, 37, 41),
    ('2025-07-31', 1, 2, 35, 0, 8, 27),
    ('2025-07-31', 1, 3, 59, 37, 20, 76),
    ('2025-07-31', 1, 4, 24, 13, 17, 20),
    ('2025-07-31', 1, 5, 82, 8, 28, 62),
    ('2025-07-31', 1, 6, 21, 14, 12, 23),
    ('2025-07-31', 1, 7, 16, 3, 0, 19),
    ('2025-07-31', 1, 8, 40, 9, 15, 34),
    ('2025-07-31', 1, 9, 60, 11, 19, 52),
    ('2025-07-31', 1, 10, 12, 4, 5, 11),
    ('2025-07-31', 2, 1, 49, 1, 10, 40),
    ('2025-07-31', 2, 2, 27, 28, 28, 27),
    ('2025-07-31', 2, 3, 69, 6, 10, 65),
    ('2025-07-31', 2, 4, 19, 18, 18, 19),
    ('2025-07-31', 2, 5, 75, 1, 14, 62),
    ('2025-07-31', 2, 6, 24, 24, 25, 23),
    ('2025-07-31', 2, 7, 36, 3, 4, 35),
    ('2025-07-31', 2, 8, 26, 25, 18, 33),
    ('2025-07-31', 2, 9, 49, 11, 8, 52),
    ('2025-07-31', 2, 10, 20, 7, 12, 15),
    ('2025-07-31', 3, 1, 46, 1, 2, 45),
    ('2025-07-31', 3, 2, 28, 14, 16, 26),
    ('2025-07-31', 3, 3, 62, 7, 8, 61),
    ('2025-07-31', 3, 4, 20, 10, 10, 20),
    ('2025-07-31', 3, 5, 77, 2, 0, 79),
    ('2025-07-31', 3, 6, 26, 3, 11, 18),
    ('2025-07-31', 3, 7, 50, 0, 0, 50),
    ('2025-07-31', 3, 8, 32, 8, 8, 32),
    ('2025-07-31', 3, 9, 54, 13, 0, 67),
    ('2025-07-31', 3, 10, 46, 0, 3, 43),
    ('2025-08-31', 1, 1, 41, 21, 1, 61),
    ('2025-08-31', 1, 2, 27, 8, 8, 27),
    ('2025-08-31', 1, 3, 76, 0, 7, 69),
    ('2025-08-31', 1, 4, 20, 0, 0, 20),
    ('2025-08-31', 1, 5, 62, 20, 14, 68),
    ('2025-08-31', 1, 6, 23, 10, 12, 21),
    ('2025-08-31', 1, 7, 19, 5, 11, 13),
    ('2025-08-31', 1, 8, 34, 12, 20, 26),
    ('2025-08-31', 1, 9, 52, 11, 9, 54),
    ('2025-08-31', 1, 10, 11, 7, 9, 9),
    ('2025-08-31', 2, 1, 40, 33, 26, 47),
    ('2025-08-31', 2, 2, 27, 6, 0, 33),
    ('2025-08-31', 2, 3, 65, 6, 0, 71),
    ('2025-08-31', 2, 4, 19, 12, 13, 18),
    ('2025-08-31', 2, 5, 62, 15, 0, 77),
    ('2025-08-31', 2, 6, 23, 29, 23, 29),
    ('2025-08-31', 2, 7, 35, 2, 6, 31),
    ('2025-08-31', 2, 8, 33, 31, 29, 35),
    ('2025-08-31', 2, 9, 52, 3, 0, 55),
    ('2025-08-31', 2, 10, 15, 0, 5, 10),
    ('2025-08-31', 3, 1, 45, 14, 22, 37),
    ('2025-08-31', 3, 2, 26, 20, 19, 27),
    ('2025-08-31', 3, 3, 61, 2, 5, 58),
    ('2025-08-31', 3, 4, 20, 17, 13, 24),
    ('2025-08-31', 3, 5, 79, 0, 0, 79),
    ('2025-08-31', 3, 6, 18, 40, 35, 23),
    ('2025-08-31', 3, 7, 50, 0, 0, 50),
    ('2025-08-31', 3, 8, 32, 21, 19, 34),
    ('2025-08-31', 3, 9, 67, 13, 13, 67),
    ('2025-08-31', 3, 10, 43, 0, 4, 39),
    ('2025-09-30', 1, 1, 61, 20, 37, 44),
    ('2025-09-30', 1, 2, 27, 0, 1, 26),
    ('2025-09-30', 1, 3, 69, 0, 0, 69),
    ('2025-09-30', 1, 4, 20, 12, 17, 15),
    ('2025-09-30', 1, 5, 68, 12, 7, 73),
    ('2025-09-30', 1, 6, 21, 25, 16, 30),
    ('2025-09-30', 1, 7, 13, 6, 6, 13),
    ('2025-09-30', 1, 8, 26, 34, 33, 27),
    ('2025-09-30', 1, 9, 54, 39, 35, 58),
    ('2025-09-30', 1, 10, 9, 3, 4, 8),
    ('2025-09-30', 2, 1, 47, 13, 3, 57),
    ('2025-09-30', 2, 2, 33, 0, 0, 33),
    ('2025-09-30', 2, 3, 71, 6, 22, 55),
    ('2025-09-30', 2, 4, 18, 8, 9, 17),
    ('2025-09-30', 2, 5, 77, 13, 10, 80),
    ('2025-09-30', 2, 6, 29, 4, 11, 22),
    ('2025-09-30', 2, 7, 31, 0, 0, 31),
    ('2025-09-30', 2, 8, 35, 0, 0, 35),
    ('2025-09-30', 2, 9, 55, 26, 23, 58),
    ('2025-09-30', 2, 10, 10, 6, 6, 10),
    ('2025-09-30', 3, 1, 37, 20, 11, 46),
    ('2025-09-30', 3, 2, 27, 22, 16, 33),
    ('2025-09-30', 3, 3, 58, 21, 18, 61),
    ('2025-09-30', 3, 4, 24, 2, 10, 16),
    ('2025-09-30', 3, 5, 79, 0, 4, 75),
    ('2025-09-30', 3, 6, 23, 31, 24, 30),
    ('2025-09-30', 3, 7, 50, 0, 4, 46),
    ('2025-09-30', 3, 8, 34, 0, 0, 34),
    ('2025-09-30', 3, 9, 67, 1, 1, 67),
    ('2025-09-30', 3, 10, 39, 0, 2, 37),
    ('2025-10-31', 1, 1, 44, 23, 13, 54),
    ('2025-10-31', 1, 2, 26, 13, 13, 26),
    ('2025-10-31', 1, 3, 69, 11, 29, 51),
    ('2025-10-31', 1, 4, 15, 20, 17, 18),
    ('2025-10-31', 1, 5, 73, 38, 16, 95),
    ('2025-10-31', 1, 6, 30, 0, 10, 20),
    ('2025-10-31', 1, 7, 13, 6, 6, 13),
    ('2025-10-31', 1, 8, 27, 42, 33, 36),
    ('2025-10-31', 1, 9, 58, 12, 23, 47),
    ('2025-10-31', 1, 10, 8, 5, 3, 10),
    ('2025-10-31', 2, 1, 57, 19, 33, 43),
    ('2025-10-31', 2, 2, 33, 0, 8, 25),
    ('2025-10-31', 2, 3, 55, 24, 20, 59),
    ('2025-10-31', 2, 4, 17, 17, 15, 19),
    ('2025-10-31', 2, 5, 80, 54, 55, 79),
    ('2025-10-31', 2, 6, 22, 32, 35, 19),
    ('2025-10-31', 2, 7, 31, 0, 8, 23),
    ('2025-10-31', 2, 8, 35, 3, 10, 28),
    ('2025-10-31', 2, 9, 58, 0, 4, 54),
    ('2025-10-31', 2, 10, 10, 12, 8, 14),
    ('2025-10-31', 3, 1, 46, 3, 7, 42),
    ('2025-10-31', 3, 2, 33, 4, 9, 28),
    ('2025-10-31', 3, 3, 61, 11, 10, 62),
    ('2025-10-31', 3, 4, 16, 12, 9, 19),
    ('2025-10-31', 3, 5, 75, 0, 0, 75),
    ('2025-10-31', 3, 6, 30, 6, 9, 27),
    ('2025-10-31', 3, 7, 46, 0, 3, 43),
    ('2025-10-31', 3, 8, 34, 0, 0, 34),
    ('2025-10-31', 3, 9, 67, 0, 8, 59),
    ('2025-10-31', 3, 10, 37, 1, 3, 35);

INSERT INTO inventory_snapshot (snapshot_date, store_id, product_id, opening_stock, received_qty, sold_qty, closing_stock) VALUES
    ('2025-11-30', 1, 1, 54, 8, 14, 48),
    ('2025-11-30', 1, 2, 26, 22, 19, 29),
    ('2025-11-30', 1, 3, 51, 40, 31, 60),
    ('2025-11-30', 1, 4, 18, 13, 13, 18),
    ('2025-11-30', 1, 5, 95, 7, 24, 78),
    ('2025-11-30', 1, 6, 20, 30, 31, 19),
    ('2025-11-30', 1, 7, 13, 11, 10, 14),
    ('2025-11-30', 1, 8, 36, 12, 9, 39),
    ('2025-11-30', 1, 9, 47, 20, 18, 49),
    ('2025-11-30', 1, 10, 10, 11, 9, 12),
    ('2025-11-30', 2, 1, 43, 7, 7, 43),
    ('2025-11-30', 2, 2, 25, 10, 8, 27),
    ('2025-11-30', 2, 3, 59, 9, 17, 51),
    ('2025-11-30', 2, 4, 19, 17, 16, 20),
    ('2025-11-30', 2, 5, 79, 19, 0, 98),
    ('2025-11-30', 2, 6, 19, 4, 0, 23),
    ('2025-11-30', 2, 7, 23, 0, 3, 20),
    ('2025-11-30', 2, 8, 28, 11, 11, 28),
    ('2025-11-30', 2, 9, 54, 14, 0, 68),
    ('2025-11-30', 2, 10, 14, 1, 3, 12),
    ('2025-11-30', 3, 1, 42, 10, 0, 52),
    ('2025-11-30', 3, 2, 28, 0, 0, 28),
    ('2025-11-30', 3, 3, 62, 22, 4, 80),
    ('2025-11-30', 3, 4, 19, 5, 0, 24),
    ('2025-11-30', 3, 5, 75, 0, 0, 75),
    ('2025-11-30', 3, 6, 27, 6, 0, 33),
    ('2025-11-30', 3, 7, 43, 0, 0, 43),
    ('2025-11-30', 3, 8, 34, 5, 9, 30),
    ('2025-11-30', 3, 9, 59, 10, 3, 66),
    ('2025-11-30', 3, 10, 35, 0, 1, 34),
    ('2025-12-31', 1, 1, 48, 4, 10, 42),
    ('2025-12-31', 1, 2, 29, 14, 10, 33),
    ('2025-12-31', 1, 3, 60, 29, 31, 58),
    ('2025-12-31', 1, 4, 18, 0, 2, 16),
    ('2025-12-31', 1, 5, 78, 5, 13, 70),
    ('2025-12-31', 1, 6, 19, 7, 5, 21),
    ('2025-12-31', 1, 7, 14, 6, 6, 14),
    ('2025-12-31', 1, 8, 39, 5, 15, 29),
    ('2025-12-31', 1, 9, 49, 26, 18, 57),
    ('2025-12-31', 1, 10, 12, 0, 0, 12),
    ('2025-12-31', 2, 1, 43, 15, 10, 48),
    ('2025-12-31', 2, 2, 27, 28, 28, 27),
    ('2025-12-31', 2, 3, 51, 26, 27, 50),
    ('2025-12-31', 2, 4, 20, 23, 26, 17),
    ('2025-12-31', 2, 5, 98, 12, 33, 77),
    ('2025-12-31', 2, 6, 23, 23, 22, 24),
    ('2025-12-31', 2, 7, 20, 0, 0, 20),
    ('2025-12-31', 2, 8, 28, 30, 17, 41),
    ('2025-12-31', 2, 9, 68, 0, 16, 52),
    ('2025-12-31', 2, 10, 12, 13, 16, 9),
    ('2025-12-31', 3, 1, 52, 7, 0, 59),
    ('2025-12-31', 3, 2, 28, 9, 10, 27),
    ('2025-12-31', 3, 3, 80, 0, 0, 80),
    ('2025-12-31', 3, 4, 24, 1, 0, 25),
    ('2025-12-31', 3, 5, 75, 25, 13, 87),
    ('2025-12-31', 3, 6, 33, 0, 8, 25),
    ('2025-12-31', 3, 7, 43, 1, 4, 40),
    ('2025-12-31', 3, 8, 30, 5, 0, 35),
    ('2025-12-31', 3, 9, 66, 0, 0, 66),
    ('2025-12-31', 3, 10, 34, 0, 3, 31);

INSERT INTO monthly_budget (budget_month, store_id, sales_budget, expense_budget) VALUES
    ('2025-01-01', 1, 3500000, 630000),
    ('2025-01-01', 2, 3000000, 540000),
    ('2025-01-01', 3, 2600000, 468000),
    ('2025-02-01', 1, 3640000, 655200),
    ('2025-02-01', 2, 3120000, 561600),
    ('2025-02-01', 3, 2704000, 486720),
    ('2025-03-01', 1, 3742487.11, 673647.68),
    ('2025-03-01', 2, 3207846.1, 577412.3),
    ('2025-03-01', 3, 2780133.28, 500423.99),
    ('2025-04-01', 1, 3780000, 680400),
    ('2025-04-01', 2, 3240000, 583200),
    ('2025-04-01', 3, 2808000, 505440),
    ('2025-05-01', 1, 3742487.11, 673647.68),
    ('2025-05-01', 2, 3207846.1, 577412.3),
    ('2025-05-01', 3, 2780133.28, 500423.99),
    ('2025-06-01', 1, 3640000, 655200),
    ('2025-06-01', 2, 3120000, 561600),
    ('2025-06-01', 3, 2704000, 486720),
    ('2025-07-01', 1, 3500000, 630000),
    ('2025-07-01', 2, 3000000, 540000),
    ('2025-07-01', 3, 2600000, 468000),
    ('2025-08-01', 1, 3360000, 604800),
    ('2025-08-01', 2, 2880000, 518400),
    ('2025-08-01', 3, 2496000, 449280),
    ('2025-09-01', 1, 3257512.89, 586352.32),
    ('2025-09-01', 2, 2792153.9, 502587.7),
    ('2025-09-01', 3, 2419866.72, 435576.01),
    ('2025-10-01', 1, 3220000, 579600),
    ('2025-10-01', 2, 2760000, 496800),
    ('2025-10-01', 3, 2392000, 430560),
    ('2025-11-01', 1, 3677512.89, 661952.32),
    ('2025-11-01', 2, 3152153.9, 567387.7),
    ('2025-11-01', 3, 2731866.72, 491736.01),
    ('2025-12-01', 1, 3780000, 680400),
    ('2025-12-01', 2, 3240000, 583200),
    ('2025-12-01', 3, 2808000, 505440);

INSERT INTO operating_expense (expense_id, expense_month, store_id, expense_category, amount) VALUES
    (1, '2025-01-01', 1, 'Rent', 244500.31),
    (2, '2025-01-01', 1, 'Utilities', 79878.65),
    (3, '2025-01-01', 1, 'Logistics', 173812.64),
    (4, '2025-01-01', 1, 'Marketing', 126349.42),
    (5, '2025-01-01', 1, 'Maintenance', 64226.22),
    (6, '2025-01-01', 2, 'Rent', 195088.75),
    (7, '2025-01-01', 2, 'Utilities', 68774.04),
    (8, '2025-01-01', 2, 'Logistics', 140828.83),
    (9, '2025-01-01', 2, 'Marketing', 103884.31),
    (10, '2025-01-01', 2, 'Maintenance', 56114.56),
    (11, '2025-01-01', 3, 'Rent', 140163.12),
    (12, '2025-01-01', 3, 'Utilities', 49072.29),
    (13, '2025-01-01', 3, 'Logistics', 107795.95),
    (14, '2025-01-01', 3, 'Marketing', 78339.33),
    (15, '2025-01-01', 3, 'Maintenance', 40183.56),
    (16, '2025-02-01', 1, 'Rent', 255283.84),
    (17, '2025-02-01', 1, 'Utilities', 85492.86),
    (18, '2025-02-01', 1, 'Logistics', 171672.74),
    (19, '2025-02-01', 1, 'Marketing', 122461.25),
    (20, '2025-02-01', 1, 'Maintenance', 67081.96),
    (21, '2025-02-01', 2, 'Rent', 182000.38),
    (22, '2025-02-01', 2, 'Utilities', 63595.54),
    (23, '2025-02-01', 2, 'Logistics', 132481.75),
    (24, '2025-02-01', 2, 'Marketing', 95472.25),
    (25, '2025-02-01', 2, 'Maintenance', 53335.7),
    (26, '2025-02-01', 3, 'Rent', 164346.96),
    (27, '2025-02-01', 3, 'Utilities', 55423.09),
    (28, '2025-02-01', 3, 'Logistics', 108568.92),
    (29, '2025-02-01', 3, 'Marketing', 84457),
    (30, '2025-02-01', 3, 'Maintenance', 42889.14),
    (31, '2025-03-01', 1, 'Rent', 232234.8),
    (32, '2025-03-01', 1, 'Utilities', 80211.67),
    (33, '2025-03-01', 1, 'Logistics', 175734.9),
    (34, '2025-03-01', 1, 'Marketing', 124797.81),
    (35, '2025-03-01', 1, 'Maintenance', 66675.75),
    (36, '2025-03-01', 2, 'Rent', 180754.53),
    (37, '2025-03-01', 2, 'Utilities', 60604.12),
    (38, '2025-03-01', 2, 'Logistics', 136008.48),
    (39, '2025-03-01', 2, 'Marketing', 89859.84),
    (40, '2025-03-01', 2, 'Maintenance', 52597.04),
    (41, '2025-03-01', 3, 'Rent', 171956.09),
    (42, '2025-03-01', 3, 'Utilities', 59033.96),
    (43, '2025-03-01', 3, 'Logistics', 125446.31),
    (44, '2025-03-01', 3, 'Marketing', 91302.53),
    (45, '2025-03-01', 3, 'Maintenance', 48433.76),
    (46, '2025-04-01', 1, 'Rent', 229295.48),
    (47, '2025-04-01', 1, 'Utilities', 77689.81),
    (48, '2025-04-01', 1, 'Logistics', 161621.65),
    (49, '2025-04-01', 1, 'Marketing', 120199.61),
    (50, '2025-04-01', 1, 'Maintenance', 64102.92),
    (51, '2025-04-01', 2, 'Rent', 188704.17),
    (52, '2025-04-01', 2, 'Utilities', 67323.27),
    (53, '2025-04-01', 2, 'Logistics', 146479.89),
    (54, '2025-04-01', 2, 'Marketing', 99336.34),
    (55, '2025-04-01', 2, 'Maintenance', 54391.89),
    (56, '2025-04-01', 3, 'Rent', 177399.43),
    (57, '2025-04-01', 3, 'Utilities', 62953.4),
    (58, '2025-04-01', 3, 'Logistics', 122796.03),
    (59, '2025-04-01', 3, 'Marketing', 89545.61),
    (60, '2025-04-01', 3, 'Maintenance', 52201.91),
    (61, '2025-05-01', 1, 'Rent', 234008.03),
    (62, '2025-05-01', 1, 'Utilities', 80873.44),
    (63, '2025-05-01', 1, 'Logistics', 157713.14),
    (64, '2025-05-01', 1, 'Marketing', 112266.32),
    (65, '2025-05-01', 1, 'Maintenance', 67852.27),
    (66, '2025-05-01', 2, 'Rent', 227497.77),
    (67, '2025-05-01', 2, 'Utilities', 75423.47),
    (68, '2025-05-01', 2, 'Logistics', 150619.42),
    (69, '2025-05-01', 2, 'Marketing', 111677.43),
    (70, '2025-05-01', 2, 'Maintenance', 60127.36),
    (71, '2025-05-01', 3, 'Rent', 165444.35),
    (72, '2025-05-01', 3, 'Utilities', 57525.79),
    (73, '2025-05-01', 3, 'Logistics', 119445.88),
    (74, '2025-05-01', 3, 'Marketing', 85900.9),
    (75, '2025-05-01', 3, 'Maintenance', 49184.86),
    (76, '2025-06-01', 1, 'Rent', 243582.08),
    (77, '2025-06-01', 1, 'Utilities', 87525.76),
    (78, '2025-06-01', 1, 'Logistics', 172594.65),
    (79, '2025-06-01', 1, 'Marketing', 126719.54),
    (80, '2025-06-01', 1, 'Maintenance', 74160.58),
    (81, '2025-06-01', 2, 'Rent', 197553.38),
    (82, '2025-06-01', 2, 'Utilities', 72744.38),
    (83, '2025-06-01', 2, 'Logistics', 139582.4),
    (84, '2025-06-01', 2, 'Marketing', 102647.9),
    (85, '2025-06-01', 2, 'Maintenance', 58729.84),
    (86, '2025-06-01', 3, 'Rent', 164092.93),
    (87, '2025-06-01', 3, 'Utilities', 54820.9),
    (88, '2025-06-01', 3, 'Logistics', 118712.5),
    (89, '2025-06-01', 3, 'Marketing', 79644.5),
    (90, '2025-06-01', 3, 'Maintenance', 48411.24),
    (91, '2025-07-01', 1, 'Rent', 227701.44),
    (92, '2025-07-01', 1, 'Utilities', 74672.35),
    (93, '2025-07-01', 1, 'Logistics', 150627.25),
    (94, '2025-07-01', 1, 'Marketing', 108871.54),
    (95, '2025-07-01', 1, 'Maintenance', 61318.08),
    (96, '2025-07-01', 2, 'Rent', 184140.73),
    (97, '2025-07-01', 2, 'Utilities', 61566.89),
    (98, '2025-07-01', 2, 'Logistics', 128044.54),
    (99, '2025-07-01', 2, 'Marketing', 93203.54),
    (100, '2025-07-01', 2, 'Maintenance', 51578.05),
    (101, '2025-07-01', 3, 'Rent', 171745.31),
    (102, '2025-07-01', 3, 'Utilities', 60418.11),
    (103, '2025-07-01', 3, 'Logistics', 122195.67),
    (104, '2025-07-01', 3, 'Marketing', 94437.45),
    (105, '2025-07-01', 3, 'Maintenance', 52597.33),
    (106, '2025-08-01', 1, 'Rent', 213719.13),
    (107, '2025-08-01', 1, 'Utilities', 76487.25),
    (108, '2025-08-01', 1, 'Logistics', 161916.93),
    (109, '2025-08-01', 1, 'Marketing', 112005.64),
    (110, '2025-08-01', 1, 'Maintenance', 60910.58),
    (111, '2025-08-01', 2, 'Rent', 169977.98),
    (112, '2025-08-01', 2, 'Utilities', 59957.92),
    (113, '2025-08-01', 2, 'Logistics', 120669.86),
    (114, '2025-08-01', 2, 'Marketing', 95178.95),
    (115, '2025-08-01', 2, 'Maintenance', 53010.6),
    (116, '2025-08-01', 3, 'Rent', 146198.26),
    (117, '2025-08-01', 3, 'Utilities', 47930.01),
    (118, '2025-08-01', 3, 'Logistics', 102886.35),
    (119, '2025-08-01', 3, 'Marketing', 71699.2),
    (120, '2025-08-01', 3, 'Maintenance', 42619.47),
    (121, '2025-09-01', 1, 'Rent', 214480.89),
    (122, '2025-09-01', 1, 'Utilities', 73836.88),
    (123, '2025-09-01', 1, 'Logistics', 163288.51),
    (124, '2025-09-01', 1, 'Marketing', 117389.19),
    (125, '2025-09-01', 1, 'Maintenance', 60862.14),
    (126, '2025-09-01', 2, 'Rent', 190365.31),
    (127, '2025-09-01', 2, 'Utilities', 63010.68),
    (128, '2025-09-01', 2, 'Logistics', 138927.22),
    (129, '2025-09-01', 2, 'Marketing', 95869.22),
    (130, '2025-09-01', 2, 'Maintenance', 53417.79),
    (131, '2025-09-01', 3, 'Rent', 146650.83),
    (132, '2025-09-01', 3, 'Utilities', 48572.57),
    (133, '2025-09-01', 3, 'Logistics', 106348.79),
    (134, '2025-09-01', 3, 'Marketing', 72243.69),
    (135, '2025-09-01', 3, 'Maintenance', 41067.47),
    (136, '2025-10-01', 1, 'Rent', 231983.49),
    (137, '2025-10-01', 1, 'Utilities', 77618.67),
    (138, '2025-10-01', 1, 'Logistics', 165368.17),
    (139, '2025-10-01', 1, 'Marketing', 112737.29),
    (140, '2025-10-01', 1, 'Maintenance', 66597.79),
    (141, '2025-10-01', 2, 'Rent', 172463.96),
    (142, '2025-10-01', 2, 'Utilities', 55951.43),
    (143, '2025-10-01', 2, 'Logistics', 123634.29),
    (144, '2025-10-01', 2, 'Marketing', 83664.04),
    (145, '2025-10-01', 2, 'Maintenance', 48940.73),
    (146, '2025-10-01', 3, 'Rent', 141390.01),
    (147, '2025-10-01', 3, 'Utilities', 51946.17),
    (148, '2025-10-01', 3, 'Logistics', 109314.28),
    (149, '2025-10-01', 3, 'Marketing', 72595.57),
    (150, '2025-10-01', 3, 'Maintenance', 41792.14);

INSERT INTO operating_expense (expense_id, expense_month, store_id, expense_category, amount) VALUES
    (151, '2025-11-01', 1, 'Rent', 244706.13),
    (152, '2025-11-01', 1, 'Utilities', 79280.12),
    (153, '2025-11-01', 1, 'Logistics', 170878.62),
    (154, '2025-11-01', 1, 'Marketing', 125331.62),
    (155, '2025-11-01', 1, 'Maintenance', 68720.83),
    (156, '2025-11-01', 2, 'Rent', 196105.66),
    (157, '2025-11-01', 2, 'Utilities', 67732.25),
    (158, '2025-11-01', 2, 'Logistics', 140274.02),
    (159, '2025-11-01', 2, 'Marketing', 98880.64),
    (160, '2025-11-01', 2, 'Maintenance', 56703.93),
    (161, '2025-11-01', 3, 'Rent', 173846.77),
    (162, '2025-11-01', 3, 'Utilities', 63203.59),
    (163, '2025-11-01', 3, 'Logistics', 124918.6),
    (164, '2025-11-01', 3, 'Marketing', 92354.52),
    (165, '2025-11-01', 3, 'Maintenance', 49866.04),
    (166, '2025-12-01', 1, 'Rent', 254170.87),
    (167, '2025-12-01', 1, 'Utilities', 93247.93),
    (168, '2025-12-01', 1, 'Logistics', 179486.89),
    (169, '2025-12-01', 1, 'Marketing', 133863.89),
    (170, '2025-12-01', 1, 'Maintenance', 72544.12),
    (171, '2025-12-01', 2, 'Rent', 198906.35),
    (172, '2025-12-01', 2, 'Utilities', 68039.29),
    (173, '2025-12-01', 2, 'Logistics', 142903),
    (174, '2025-12-01', 2, 'Marketing', 102266.7),
    (175, '2025-12-01', 2, 'Maintenance', 56846.05),
    (176, '2025-12-01', 3, 'Rent', 199007.59),
    (177, '2025-12-01', 3, 'Utilities', 63372.44),
    (178, '2025-12-01', 3, 'Logistics', 130008.42),
    (179, '2025-12-01', 3, 'Marketing', 95803.41),
    (180, '2025-12-01', 3, 'Maintenance', 54832.47);

INSERT INTO purchase_order (po_id, order_date, expected_date, received_date, supplier_id, store_id, status) VALUES
    (5001, '2025-01-10', '2025-01-16', '2025-01-16', 2, 3, 'Received'),
    (5002, '2025-01-13', '2025-01-17', '2025-01-17', 4, 3, 'Received'),
    (5003, '2025-01-05', '2025-01-12', '2025-01-10', 3, 2, 'Received'),
    (5004, '2025-01-03', '2025-01-11', '2025-01-11', 5, 1, 'Received'),
    (5005, '2025-01-14', '2025-01-19', '2025-01-19', 6, 3, 'Received'),
    (5006, '2025-01-07', '2025-01-15', '2025-01-15', 5, 3, 'Received'),
    (5007, '2025-02-15', '2025-02-19', '2025-02-19', 4, 3, 'Received'),
    (5008, '2025-02-12', '2025-02-21', '2025-02-23', 1, 1, 'Received'),
    (5009, '2025-02-12', '2025-02-19', '2025-02-19', 3, 2, 'Received'),
    (5010, '2025-02-13', '2025-02-20', '2025-02-22', 3, 1, 'Received'),
    (5011, '2025-02-10', '2025-02-16', '2025-02-14', 2, 2, 'Received'),
    (5012, '2025-02-04', '2025-02-12', '2025-02-12', 5, 2, 'Received'),
    (5013, '2025-03-05', '2025-03-11', '2025-03-18', 2, 2, 'Received'),
    (5014, '2025-03-16', '2025-03-20', '2025-03-20', 4, 2, 'Received'),
    (5015, '2025-03-12', '2025-03-21', '2025-03-28', 1, 1, 'Received'),
    (5016, '2025-03-20', '2025-03-29', '2025-03-30', 1, 2, 'Received'),
    (5017, '2025-03-14', '2025-03-21', '2025-03-19', 3, 1, 'Received'),
    (5018, '2025-04-15', '2025-04-20', '2025-04-20', 6, 3, 'Received'),
    (5019, '2025-04-15', '2025-04-22', '2025-04-26', 3, 2, 'Received'),
    (5020, '2025-04-18', '2025-04-25', '2025-04-23', 3, 3, 'Received'),
    (5021, '2025-04-15', '2025-04-19', '2025-04-26', 4, 1, 'Received'),
    (5022, '2025-04-05', '2025-04-11', '2025-04-13', 2, 3, 'Received'),
    (5023, '2025-04-02', '2025-04-09', '2025-04-09', 3, 2, 'Received'),
    (5024, '2025-05-01', '2025-05-08', '2025-05-15', 3, 1, 'Received'),
    (5025, '2025-05-13', '2025-05-18', '2025-05-18', 6, 3, 'Received'),
    (5026, '2025-05-11', '2025-05-15', '2025-05-15', 4, 1, 'Received'),
    (5027, '2025-05-16', '2025-05-21', '2025-05-21', 6, 3, 'Received'),
    (5028, '2025-05-05', '2025-05-12', '2025-05-14', 3, 2, 'Received'),
    (5029, '2025-06-17', '2025-06-21', '2025-06-21', 4, 3, 'Received'),
    (5030, '2025-06-05', '2025-06-09', '2025-06-07', 4, 2, 'Received'),
    (5031, '2025-06-19', '2025-06-27', '2025-06-26', 5, 2, 'Received'),
    (5032, '2025-06-11', '2025-06-18', '2025-06-17', 3, 3, 'Received'),
    (5033, '2025-07-20', '2025-07-28', '2025-07-28', 5, 2, 'Received'),
    (5034, '2025-07-04', '2025-07-13', '2025-07-11', 1, 3, 'Received'),
    (5035, '2025-07-16', '2025-07-25', '2025-07-23', 1, 1, 'Received'),
    (5036, '2025-07-16', '2025-07-22', '2025-07-29', 2, 3, 'Received'),
    (5037, '2025-08-08', '2025-08-14', '2025-08-18', 2, 1, 'Received'),
    (5038, '2025-08-11', '2025-08-20', '2025-08-24', 1, 1, 'Received'),
    (5039, '2025-08-07', '2025-08-16', '2025-08-23', 1, 2, 'Received'),
    (5040, '2025-08-11', '2025-08-17', '2025-08-19', 2, 2, 'Received'),
    (5041, '2025-08-07', '2025-08-15', '2025-08-15', 5, 3, 'Received'),
    (5042, '2025-09-17', '2025-09-23', '2025-09-23', 2, 3, 'Received'),
    (5043, '2025-09-19', '2025-09-27', '2025-10-01', 5, 1, 'Received'),
    (5044, '2025-09-12', '2025-09-21', '2025-09-21', 1, 2, 'Received'),
    (5045, '2025-09-14', '2025-09-23', '2025-09-22', 1, 3, 'Received'),
    (5046, '2025-10-09', '2025-10-15', '2025-10-15', 2, 2, 'Received'),
    (5047, '2025-10-08', '2025-10-15', '2025-10-15', 3, 2, 'Received'),
    (5048, '2025-10-05', '2025-10-13', '2025-10-13', 5, 1, 'Received'),
    (5049, '2025-10-16', '2025-10-24', '2025-10-24', 5, 2, 'Received'),
    (5050, '2025-11-11', '2025-11-19', '2025-11-18', 5, 1, 'Received'),
    (5051, '2025-11-07', '2025-11-14', '2025-11-14', 3, 2, 'Received'),
    (5052, '2025-11-09', '2025-11-13', '2025-11-11', 4, 3, 'Received'),
    (5053, '2025-11-11', '2025-11-15', '2025-11-14', 4, 1, 'Received'),
    (5054, '2025-12-12', '2025-12-20', '2025-12-27', 5, 2, 'Received'),
    (5055, '2025-12-15', '2025-12-21', '2025-12-21', 2, 1, 'Received'),
    (5056, '2025-12-06', '2025-12-11', '2025-12-18', 6, 2, 'Received'),
    (5057, '2025-12-07', '2025-12-12', '2025-12-14', 6, 1, 'Received'),
    (5058, '2025-12-02', '2025-12-10', '2025-12-09', 5, 3, 'Received');

INSERT INTO purchase_order_item (po_id, product_id, quantity_ordered, quantity_received, unit_cost) VALUES
    (5001, 3, 49, 49, 4215.33),
    (5002, 7, 19, 18, 66312.27),
    (5002, 5, 55, 55, 2931.51),
    (5003, 4, 40, 40, 18093.93),
    (5004, 10, 34, 34, 86986.17),
    (5005, 8, 58, 55, 27851.26),
    (5005, 9, 26, 26, 7654.03),
    (5006, 10, 47, 43, 87473.58),
    (5006, 6, 50, 50, 25340.58),
    (5007, 5, 18, 18, 3011.51),
    (5008, 2, 51, 51, 22249.06),
    (5008, 1, 57, 56, 6475.91),
    (5009, 4, 43, 43, 17807.45),
    (5010, 4, 48, 48, 17780.03),
    (5011, 3, 22, 21, 4178.74),
    (5012, 10, 13, 13, 84596.62),
    (5012, 6, 50, 50, 25731.75),
    (5013, 3, 17, 17, 4203.05),
    (5014, 5, 43, 43, 3048.33),
    (5014, 7, 49, 49, 64458.37),
    (5015, 1, 12, 12, 6618.24),
    (5016, 2, 25, 24, 22063.98),
    (5016, 1, 51, 51, 6422.76),
    (5017, 4, 58, 58, 17731.07),
    (5018, 8, 15, 15, 28631.21),
    (5018, 9, 17, 17, 7397.73),
    (5019, 4, 54, 54, 18347.21),
    (5020, 4, 37, 37, 18036.19),
    (5021, 5, 48, 48, 3026.44),
    (5022, 3, 46, 46, 4280.79),
    (5023, 4, 47, 47, 18427.43),
    (5024, 4, 37, 37, 17871.12),
    (5025, 8, 37, 37, 28493.45),
    (5026, 7, 41, 41, 64742.16),
    (5027, 8, 17, 17, 28108.75),
    (5028, 4, 48, 44, 17904.88),
    (5029, 5, 21, 21, 3051.35),
    (5030, 5, 16, 16, 2934.89),
    (5030, 7, 13, 13, 63413.79),
    (5031, 10, 28, 28, 85195.45),
    (5031, 6, 11, 11, 25419.13),
    (5032, 4, 53, 49, 17794.79),
    (5033, 10, 27, 27, 85749.36),
    (5033, 6, 47, 47, 25259.93),
    (5034, 1, 25, 23, 6436.11),
    (5035, 1, 44, 42, 6543.54),
    (5035, 2, 19, 19, 21840.08),
    (5036, 3, 40, 40, 4299.11),
    (5037, 3, 34, 34, 4240.73),
    (5038, 1, 15, 15, 6645.52),
    (5038, 2, 51, 51, 22266.25),
    (5039, 2, 53, 53, 22309),
    (5039, 1, 53, 53, 6308.27),
    (5040, 3, 41, 39, 4312.62),
    (5041, 10, 48, 48, 83826.86),
    (5042, 3, 52, 52, 4117.28),
    (5043, 6, 37, 37, 25340.05),
    (5043, 10, 18, 17, 87061.22),
    (5044, 1, 50, 50, 6528.3),
    (5045, 2, 60, 56, 21555.77),
    (5046, 3, 10, 10, 4311.76),
    (5047, 4, 54, 54, 17787.14),
    (5048, 6, 49, 49, 25291.51),
    (5048, 10, 27, 27, 83404.84),
    (5049, 6, 10, 10, 24506.32),
    (5050, 10, 19, 19, 82937.98),
    (5051, 4, 54, 54, 17778.5),
    (5052, 7, 39, 39, 63488.07),
    (5053, 5, 60, 60, 2998.74),
    (5054, 10, 22, 22, 83413.99),
    (5054, 6, 41, 41, 24398.61),
    (5055, 3, 44, 44, 4118.37),
    (5056, 8, 21, 20, 28564.34),
    (5057, 8, 31, 31, 28066.12),
    (5058, 10, 49, 48, 84669.61),
    (5058, 6, 56, 52, 24304.65);

-- =====================================================================
-- 6. DATA QUALITY & VALIDATION ANALYSIS
-- =====================================================================

-- 6.1 Record counts.
SELECT 'product' AS entity, COUNT(*) AS row_count FROM product
UNION ALL SELECT 'customer', COUNT(*) FROM customer
UNION ALL SELECT 'sales_order', COUNT(*) FROM sales_order
UNION ALL SELECT 'sales_order_item', COUNT(*) FROM sales_order_item
UNION ALL SELECT 'inventory_snapshot', COUNT(*) FROM inventory_snapshot
UNION ALL SELECT 'purchase_order', COUNT(*) FROM purchase_order;

-- 6.2 Duplicate SKU check. Expected result: zero rows.
SELECT sku, COUNT(*) AS occurrences
FROM product
GROUP BY sku
HAVING COUNT(*) > 1;

-- 6.3 Invalid price/cost relationships for review.
-- A product can occasionally sell below list price due to discounting,
-- but standard list price below standard cost should be investigated.
SELECT product_id, sku, product_name, standard_cost, list_price
FROM product
WHERE list_price < standard_cost;

-- 6.4 Inventory arithmetic validation. Expected result: zero rows.
SELECT *
FROM inventory_snapshot
WHERE closing_stock <> opening_stock + received_qty - sold_qty;

-- 6.5 Sales lines with impossible or suspicious values. Expected: zero rows.
SELECT *
FROM sales_order_item
WHERE quantity <= 0
   OR unit_price < 0
   OR unit_cost < 0
   OR discount_pct NOT BETWEEN 0 AND 1;

-- 6.6 Missing foreign-key-linked information.
SELECT so.order_id
FROM sales_order so
LEFT JOIN customer c ON c.customer_id = so.customer_id
LEFT JOIN store s ON s.store_id = so.store_id
WHERE c.customer_id IS NULL
   OR s.store_id IS NULL;

-- 6.7 Cancelled-order share: useful as both data check and process KPI.
SELECT
    status,
    COUNT(*) AS order_count,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS order_pct
FROM sales_order
GROUP BY status;

-- =====================================================================
-- 7. REUSABLE BUSINESS FUNCTIONS
-- =====================================================================

-- Gross margin percentage.
DROP FUNCTION IF EXISTS fn_gross_margin_pct;
DELIMITER $$
CREATE FUNCTION fn_gross_margin_pct(
    p_revenue DECIMAL(18,2),
    p_cogs    DECIMAL(18,2)
)
RETURNS DECIMAL(10,2)
DETERMINISTIC
NO SQL
BEGIN
    RETURN CASE
        WHEN p_revenue IS NULL OR p_revenue = 0 THEN NULL
        ELSE ROUND(100 * (p_revenue - p_cogs) / p_revenue, 2)
    END;
END$$
DELIMITER ;

-- Inventory status based on closing stock, reorder level and safety stock.
DROP FUNCTION IF EXISTS fn_stock_status;
DELIMITER $$
CREATE FUNCTION fn_stock_status(
    p_closing_stock INT,
    p_reorder_level INT,
    p_safety_stock  INT
)
RETURNS VARCHAR(30)
DETERMINISTIC
NO SQL
BEGIN
    RETURN CASE
        WHEN p_closing_stock <= p_safety_stock THEN 'Critical'
        WHEN p_closing_stock <= p_reorder_level THEN 'Reorder'
        WHEN p_closing_stock <= p_reorder_level + p_safety_stock THEN 'Watch'
        ELSE 'Healthy'
    END;
END$$
DELIMITER ;

-- =====================================================================
-- 8. CORE ANALYTICAL VIEWS
-- =====================================================================

-- 8.1 Transaction-level sales view.
DROP VIEW IF EXISTS vw_sales_line;
CREATE VIEW vw_sales_line AS
SELECT
    so.order_id,
    so.order_date,
    so.store_id,
    s.store_name,
    s.store_type,
    so.customer_id,
    c.customer_name,
    c.segment AS customer_segment,
    so.channel,
    soi.product_id,
    p.sku,
    p.product_name,
    cat.category_name,
    soi.quantity,
    soi.unit_price,
    soi.unit_cost,
    soi.discount_pct,
    ROUND(soi.quantity * soi.unit_price, 2) AS gross_sales,
    ROUND(soi.quantity * soi.unit_price * soi.discount_pct, 2) AS discount_amount,
    ROUND(soi.quantity * soi.unit_price * (1 - soi.discount_pct), 2) AS net_sales,
    ROUND(soi.quantity * soi.unit_cost, 2) AS cogs,
    ROUND(
        soi.quantity * soi.unit_price * (1 - soi.discount_pct)
        - soi.quantity * soi.unit_cost,
        2
    ) AS gross_profit
FROM sales_order so
JOIN sales_order_item soi ON soi.order_id = so.order_id
JOIN product p ON p.product_id = soi.product_id
JOIN category cat ON cat.category_id = p.category_id
JOIN store s ON s.store_id = so.store_id
JOIN customer c ON c.customer_id = so.customer_id
WHERE so.status = 'Completed';

-- 8.2 Monthly sales and margin summary.
DROP VIEW IF EXISTS vw_monthly_sales;
CREATE VIEW vw_monthly_sales AS
SELECT
    DATE_FORMAT(order_date, '%Y-%m-01') AS month_key,
    SUM(net_sales) AS net_sales,
    SUM(cogs) AS cogs,
    SUM(gross_profit) AS gross_profit,
    fn_gross_margin_pct(SUM(net_sales), SUM(cogs)) AS gross_margin_pct,
    COUNT(DISTINCT order_id) AS completed_orders,
    COUNT(DISTINCT customer_id) AS active_customers
FROM vw_sales_line
GROUP BY DATE_FORMAT(order_date, '%Y-%m-01');

-- 8.3 Current inventory using the latest snapshot for every store/product.
DROP VIEW IF EXISTS vw_current_inventory;
CREATE VIEW vw_current_inventory AS
WITH ranked_inventory AS (
    SELECT
        i.*,
        ROW_NUMBER() OVER (
            PARTITION BY i.store_id, i.product_id
            ORDER BY i.snapshot_date DESC
        ) AS rn
    FROM inventory_snapshot i
)
SELECT
    ri.snapshot_date,
    ri.store_id,
    s.store_name,
    ri.product_id,
    p.sku,
    p.product_name,
    c.category_name,
    p.supplier_id,
    ri.closing_stock AS current_stock,
    p.reorder_level,
    p.safety_stock,
    fn_stock_status(ri.closing_stock, p.reorder_level, p.safety_stock) AS stock_status,
    ROUND(ri.closing_stock * p.standard_cost, 2) AS inventory_cost_value,
    ROUND(ri.closing_stock * p.list_price, 2) AS inventory_retail_value
FROM ranked_inventory ri
JOIN product p ON p.product_id = ri.product_id
JOIN category c ON c.category_id = p.category_id
JOIN store s ON s.store_id = ri.store_id
WHERE ri.rn = 1;

-- 8.4 Budget vs actual sales and expenses.
DROP VIEW IF EXISTS vw_budget_vs_actual;
CREATE VIEW vw_budget_vs_actual AS
WITH actual_sales AS (
    SELECT
        DATE_FORMAT(order_date, '%Y-%m-01') AS month_key,
        store_id,
        SUM(net_sales) AS actual_sales
    FROM vw_sales_line
    GROUP BY DATE_FORMAT(order_date, '%Y-%m-01'), store_id
),
actual_expense AS (
    SELECT
        DATE_FORMAT(expense_month, '%Y-%m-01') AS month_key,
        store_id,
        SUM(amount) AS actual_expense
    FROM operating_expense
    GROUP BY DATE_FORMAT(expense_month, '%Y-%m-01'), store_id
)
SELECT
    mb.budget_month,
    mb.store_id,
    s.store_name,
    mb.sales_budget,
    COALESCE(a.actual_sales, 0) AS actual_sales,
    ROUND(COALESCE(a.actual_sales, 0) - mb.sales_budget, 2) AS sales_variance,
    ROUND(
        100 * (COALESCE(a.actual_sales, 0) - mb.sales_budget)
        / NULLIF(mb.sales_budget, 0),
        2
    ) AS sales_variance_pct,
    mb.expense_budget,
    COALESCE(e.actual_expense, 0) AS actual_expense,
    ROUND(COALESCE(e.actual_expense, 0) - mb.expense_budget, 2) AS expense_variance,
    ROUND(
        100 * (COALESCE(e.actual_expense, 0) - mb.expense_budget)
        / NULLIF(mb.expense_budget, 0),
        2
    ) AS expense_variance_pct
FROM monthly_budget mb
JOIN store s ON s.store_id = mb.store_id
LEFT JOIN actual_sales a
  ON a.store_id = mb.store_id
 AND a.month_key = DATE_FORMAT(mb.budget_month, '%Y-%m-01')
LEFT JOIN actual_expense e
  ON e.store_id = mb.store_id
 AND e.month_key = DATE_FORMAT(mb.budget_month, '%Y-%m-01');

-- =====================================================================
-- 9. EXECUTIVE KPI SUMMARY
-- =====================================================================

SELECT
    ROUND(SUM(net_sales), 2) AS total_net_sales,
    ROUND(SUM(gross_profit), 2) AS total_gross_profit,
    fn_gross_margin_pct(SUM(net_sales), SUM(cogs)) AS gross_margin_pct,
    COUNT(DISTINCT order_id) AS completed_orders,
    COUNT(DISTINCT customer_id) AS active_customers,
    ROUND(SUM(net_sales) / NULLIF(COUNT(DISTINCT order_id), 0), 2) AS average_order_value,
    SUM(quantity) AS units_sold
FROM vw_sales_line;

-- =====================================================================
-- 10. SALES TREND, MOM GROWTH & MOVING-AVERAGE FORECAST
-- =====================================================================

-- 10.1 Monthly performance and month-over-month sales growth.
WITH monthly AS (
    SELECT
        CAST(month_key AS DATE) AS sales_month,
        net_sales,
        gross_profit,
        gross_margin_pct,
        completed_orders
    FROM vw_monthly_sales
),
with_previous AS (
    SELECT
        *,
        LAG(net_sales) OVER (ORDER BY sales_month) AS previous_month_sales
    FROM monthly
)
SELECT
    sales_month,
    ROUND(net_sales, 2) AS net_sales,
    ROUND(gross_profit, 2) AS gross_profit,
    gross_margin_pct,
    completed_orders,
    ROUND(
        100 * (net_sales - previous_month_sales)
        / NULLIF(previous_month_sales, 0),
        2
    ) AS mom_sales_growth_pct
FROM with_previous
ORDER BY sales_month;

-- 10.2 Three-month rolling average: useful for smoothing demand.
WITH monthly AS (
    SELECT
        CAST(month_key AS DATE) AS sales_month,
        net_sales
    FROM vw_monthly_sales
)
SELECT
    sales_month,
    ROUND(net_sales, 2) AS actual_sales,
    ROUND(
        AVG(net_sales) OVER (
            ORDER BY sales_month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ),
        2
    ) AS rolling_3_month_avg_sales
FROM monthly
ORDER BY sales_month;

-- 10.3 Simple next-month forecast using the latest three months.
-- This is a transparent planning estimate, not ML forecasting.
WITH monthly AS (
    SELECT
        CAST(month_key AS DATE) AS sales_month,
        net_sales
    FROM vw_monthly_sales
),
latest_three AS (
    SELECT sales_month, net_sales
    FROM monthly
    ORDER BY sales_month DESC
    LIMIT 3
)
SELECT
    DATE_ADD(MAX(sales_month), INTERVAL 1 MONTH) AS forecast_month,
    ROUND(AVG(net_sales), 2) AS three_month_moving_average_forecast
FROM latest_three;

-- =====================================================================
-- 11. BUDGETING & BUSINESS-PLANNING ANALYSIS
-- =====================================================================

-- 11.1 Monthly budget vs actual.
SELECT *
FROM vw_budget_vs_actual
ORDER BY budget_month, store_id;

-- 11.2 Year-to-date sales budget attainment by store.
SELECT
    store_id,
    store_name,
    ROUND(SUM(sales_budget), 2) AS ytd_sales_budget,
    ROUND(SUM(actual_sales), 2) AS ytd_actual_sales,
    ROUND(SUM(actual_sales) - SUM(sales_budget), 2) AS ytd_sales_variance,
    ROUND(
        100 * SUM(actual_sales) / NULLIF(SUM(sales_budget), 0),
        2
    ) AS budget_attainment_pct
FROM vw_budget_vs_actual
GROUP BY store_id, store_name
ORDER BY budget_attainment_pct DESC;

-- 11.3 Expense control by store.
SELECT
    store_id,
    store_name,
    ROUND(SUM(expense_budget), 2) AS expense_budget,
    ROUND(SUM(actual_expense), 2) AS actual_expense,
    ROUND(SUM(actual_expense) - SUM(expense_budget), 2) AS expense_variance
FROM vw_budget_vs_actual
GROUP BY store_id, store_name
ORDER BY expense_variance;

-- =====================================================================
-- 12. PRODUCT & CATEGORY PERFORMANCE
-- =====================================================================

-- 12.1 Category sales, profit and margin.
SELECT
    category_name,
    ROUND(SUM(net_sales), 2) AS net_sales,
    ROUND(SUM(gross_profit), 2) AS gross_profit,
    fn_gross_margin_pct(SUM(net_sales), SUM(cogs)) AS gross_margin_pct,
    SUM(quantity) AS units_sold
FROM vw_sales_line
GROUP BY category_name
ORDER BY net_sales DESC;

-- 12.2 Product ranking with company-sales contribution.
WITH product_sales AS (
    SELECT
        product_id,
        sku,
        product_name,
        SUM(net_sales) AS net_sales,
        SUM(gross_profit) AS gross_profit,
        SUM(quantity) AS units_sold
    FROM vw_sales_line
    GROUP BY product_id, sku, product_name
)
SELECT
    *,
    DENSE_RANK() OVER (ORDER BY net_sales DESC) AS sales_rank,
    ROUND(100 * net_sales / SUM(net_sales) OVER (), 2) AS sales_contribution_pct
FROM product_sales
ORDER BY sales_rank, product_name;

-- 12.3 ABC classification based on cumulative revenue contribution.
WITH product_sales AS (
    SELECT
        product_id,
        sku,
        product_name,
        SUM(net_sales) AS net_sales
    FROM vw_sales_line
    GROUP BY product_id, sku, product_name
),
ranked AS (
    SELECT
        *,
        SUM(net_sales) OVER (
            ORDER BY net_sales DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_sales,
        SUM(net_sales) OVER () AS total_sales
    FROM product_sales
)
SELECT
    product_id,
    sku,
    product_name,
    ROUND(net_sales, 2) AS net_sales,
    ROUND(100 * cumulative_sales / NULLIF(total_sales, 0), 2) AS cumulative_sales_pct,
    CASE
        WHEN cumulative_sales / NULLIF(total_sales, 0) <= 0.80 THEN 'A'
        WHEN cumulative_sales / NULLIF(total_sales, 0) <= 0.95 THEN 'B'
        ELSE 'C'
    END AS abc_class
FROM ranked
ORDER BY net_sales DESC;

-- =====================================================================
-- 13. STORE / OPERATIONAL PERFORMANCE
-- =====================================================================

WITH store_performance AS (
    SELECT
        store_id,
        store_name,
        SUM(net_sales) AS net_sales,
        SUM(gross_profit) AS gross_profit,
        COUNT(DISTINCT order_id) AS orders,
        SUM(quantity) AS units_sold
    FROM vw_sales_line
    GROUP BY store_id, store_name
)
SELECT
    *,
    DENSE_RANK() OVER (ORDER BY net_sales DESC) AS sales_rank,
    ROUND(net_sales / NULLIF(orders, 0), 2) AS average_order_value
FROM store_performance
ORDER BY sales_rank;

-- Channel mix, especially useful for project/B2B business.
SELECT
    channel,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(SUM(net_sales), 2) AS net_sales,
    ROUND(100 * SUM(net_sales) / SUM(SUM(net_sales)) OVER (), 2) AS sales_mix_pct,
    ROUND(SUM(gross_profit), 2) AS gross_profit
FROM vw_sales_line
GROUP BY channel
ORDER BY net_sales DESC;

-- =====================================================================
-- 14. CUSTOMER ANALYTICS
-- =====================================================================

-- 14.1 Customer lifetime value and ranking.
WITH customer_value AS (
    SELECT
        customer_id,
        customer_name,
        customer_segment,
        COUNT(DISTINCT order_id) AS order_count,
        MAX(order_date) AS last_order_date,
        SUM(net_sales) AS lifetime_sales,
        SUM(gross_profit) AS lifetime_gross_profit
    FROM vw_sales_line
    GROUP BY customer_id, customer_name, customer_segment
)
SELECT
    *,
    DENSE_RANK() OVER (ORDER BY lifetime_sales DESC) AS customer_value_rank
FROM customer_value
ORDER BY customer_value_rank, customer_name;

-- 14.2 Segment performance.
SELECT
    customer_segment,
    COUNT(DISTINCT customer_id) AS active_customers,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(SUM(net_sales), 2) AS net_sales,
    ROUND(SUM(net_sales) / NULLIF(COUNT(DISTINCT customer_id),0), 2) AS sales_per_customer
FROM vw_sales_line
GROUP BY customer_segment
ORDER BY net_sales DESC;

-- 14.3 Simple RFM-style customer prioritisation.
WITH customer_rfm AS (
    SELECT
        customer_id,
        customer_name,
        DATEDIFF(
            (SELECT MAX(order_date) FROM vw_sales_line),
            MAX(order_date)
        ) AS recency_days,
        COUNT(DISTINCT order_id) AS frequency,
        SUM(net_sales) AS monetary_value
    FROM vw_sales_line
    GROUP BY customer_id, customer_name
),
scored AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY recency_days DESC) AS recency_score,
        NTILE(4) OVER (ORDER BY frequency) AS frequency_score,
        NTILE(4) OVER (ORDER BY monetary_value) AS monetary_score
    FROM customer_rfm
)
SELECT
    customer_id,
    customer_name,
    recency_days,
    frequency,
    ROUND(monetary_value,2) AS monetary_value,
    recency_score,
    frequency_score,
    monetary_score,
    recency_score + frequency_score + monetary_score AS rfm_total_score
FROM scored
ORDER BY rfm_total_score DESC, monetary_value DESC;

-- =====================================================================
-- 15. INVENTORY ANALYTICS
-- =====================================================================

-- 15.1 Current stock health.
SELECT
    store_name,
    sku,
    product_name,
    current_stock,
    reorder_level,
    safety_stock,
    stock_status,
    inventory_cost_value
FROM vw_current_inventory
ORDER BY
    FIELD(stock_status, 'Critical','Reorder','Watch','Healthy'),
    current_stock;

-- 15.2 Average daily sales during the latest 90-day period.
WITH max_date AS (
    SELECT MAX(order_date) AS max_order_date FROM vw_sales_line
),
recent_sales AS (
    SELECT
        v.store_id,
        v.product_id,
        SUM(v.quantity) AS units_sold_90d
    FROM vw_sales_line v
    CROSS JOIN max_date m
    WHERE v.order_date > DATE_SUB(m.max_order_date, INTERVAL 90 DAY)
    GROUP BY v.store_id, v.product_id
)
SELECT
    ci.store_name,
    ci.sku,
    ci.product_name,
    ci.current_stock,
    COALESCE(rs.units_sold_90d,0) AS units_sold_90d,
    ROUND(COALESCE(rs.units_sold_90d,0) / 90, 2) AS avg_daily_units,
    CASE
        WHEN COALESCE(rs.units_sold_90d,0) = 0 THEN NULL
        ELSE ROUND(ci.current_stock / (rs.units_sold_90d / 90), 1)
    END AS estimated_days_of_stock
FROM vw_current_inventory ci
LEFT JOIN recent_sales rs
  ON rs.store_id = ci.store_id
 AND rs.product_id = ci.product_id
ORDER BY estimated_days_of_stock;

-- 15.3 Reorder recommendation using lead-time demand + safety stock.
WITH max_date AS (
    SELECT MAX(order_date) AS max_order_date FROM vw_sales_line
),
recent_sales AS (
    SELECT
        v.store_id,
        v.product_id,
        SUM(v.quantity) AS units_sold_90d
    FROM vw_sales_line v
    CROSS JOIN max_date m
    WHERE v.order_date > DATE_SUB(m.max_order_date, INTERVAL 90 DAY)
    GROUP BY v.store_id, v.product_id
),
reorder_calc AS (
    SELECT
        ci.store_id,
        ci.store_name,
        ci.product_id,
        ci.sku,
        ci.product_name,
        ci.current_stock,
        ci.reorder_level,
        ci.safety_stock,
        sup.standard_lead_days,
        COALESCE(rs.units_sold_90d, 0) / 90 AS avg_daily_units,
        CEIL(
            (COALESCE(rs.units_sold_90d, 0) / 90) * sup.standard_lead_days
            + ci.safety_stock
        ) AS target_stock
    FROM vw_current_inventory ci
    JOIN product p ON p.product_id = ci.product_id
    JOIN supplier sup ON sup.supplier_id = p.supplier_id
    LEFT JOIN recent_sales rs
      ON rs.store_id = ci.store_id
     AND rs.product_id = ci.product_id
)
SELECT
    store_name,
    sku,
    product_name,
    current_stock,
    standard_lead_days,
    ROUND(avg_daily_units,2) AS avg_daily_units,
    target_stock,
    GREATEST(target_stock - current_stock, 0) AS suggested_reorder_qty
FROM reorder_calc
WHERE current_stock <= reorder_level
   OR current_stock < target_stock
ORDER BY suggested_reorder_qty DESC, store_name, product_name;

-- 15.4 Inventory turnover by product.
-- COGS / average inventory cost value.
WITH annual_cogs AS (
    SELECT
        product_id,
        SUM(cogs) AS cogs
    FROM vw_sales_line
    GROUP BY product_id
),
avg_inventory AS (
    SELECT
        i.product_id,
        AVG(i.closing_stock * p.standard_cost) AS avg_inventory_cost
    FROM inventory_snapshot i
    JOIN product p ON p.product_id = i.product_id
    GROUP BY i.product_id
)
SELECT
    p.sku,
    p.product_name,
    ROUND(ac.cogs,2) AS annual_cogs,
    ROUND(ai.avg_inventory_cost,2) AS avg_inventory_cost,
    ROUND(ac.cogs / NULLIF(ai.avg_inventory_cost,0),2) AS inventory_turnover
FROM annual_cogs ac
JOIN avg_inventory ai ON ai.product_id = ac.product_id
JOIN product p ON p.product_id = ac.product_id
ORDER BY inventory_turnover DESC;

-- 15.5 Slow-moving products by location.
WITH last_90_sales AS (
    SELECT
        store_id,
        product_id,
        SUM(quantity) AS units_90d
    FROM vw_sales_line
    WHERE order_date > DATE_SUB(
        (SELECT MAX(order_date) FROM vw_sales_line),
        INTERVAL 90 DAY
    )
    GROUP BY store_id, product_id
)
SELECT
    ci.store_name,
    ci.sku,
    ci.product_name,
    ci.current_stock,
    COALESCE(l.units_90d,0) AS units_sold_90d,
    ci.inventory_cost_value
FROM vw_current_inventory ci
LEFT JOIN last_90_sales l
  ON l.store_id = ci.store_id
 AND l.product_id = ci.product_id
WHERE COALESCE(l.units_90d,0) <= 5
  AND ci.current_stock > 0
ORDER BY ci.inventory_cost_value DESC;

-- =====================================================================
-- 16. PROCUREMENT & SUPPLIER ANALYSIS
-- =====================================================================

-- 16.1 Supplier delivery timeliness.
SELECT
    s.supplier_id,
    s.supplier_name,
    COUNT(*) AS purchase_orders,
    ROUND(AVG(DATEDIFF(po.received_date, po.order_date)), 1) AS avg_actual_lead_days,
    s.standard_lead_days,
    SUM(CASE WHEN po.received_date <= po.expected_date THEN 1 ELSE 0 END) AS on_time_orders,
    ROUND(
        100 * SUM(CASE WHEN po.received_date <= po.expected_date THEN 1 ELSE 0 END)
        / COUNT(*),
        2
    ) AS on_time_delivery_pct
FROM purchase_order po
JOIN supplier s ON s.supplier_id = po.supplier_id
WHERE po.status = 'Received'
  AND po.received_date IS NOT NULL
GROUP BY s.supplier_id, s.supplier_name, s.standard_lead_days
ORDER BY on_time_delivery_pct DESC, avg_actual_lead_days;

-- 16.2 Purchase-order fill rate by supplier.
SELECT
    s.supplier_name,
    SUM(poi.quantity_ordered) AS qty_ordered,
    SUM(poi.quantity_received) AS qty_received,
    ROUND(
        100 * SUM(poi.quantity_received)
        / NULLIF(SUM(poi.quantity_ordered),0),
        2
    ) AS fill_rate_pct
FROM purchase_order po
JOIN purchase_order_item poi ON poi.po_id = po.po_id
JOIN supplier s ON s.supplier_id = po.supplier_id
GROUP BY s.supplier_name
ORDER BY fill_rate_pct DESC;

-- =====================================================================
-- 17. MANAGEMENT REPORTING PROCEDURE
-- =====================================================================

DROP PROCEDURE IF EXISTS sp_monthly_management_report;
DELIMITER $$
CREATE PROCEDURE sp_monthly_management_report(IN p_month DATE)
BEGIN
    DECLARE v_month_start DATE;
    DECLARE v_next_month  DATE;

    SET v_month_start = CAST(DATE_FORMAT(p_month, '%Y-%m-01') AS DATE);
    SET v_next_month = DATE_ADD(v_month_start, INTERVAL 1 MONTH);

    -- Result set 1: headline management KPIs.
    SELECT
        v_month_start AS report_month,
        ROUND(SUM(v.net_sales),2) AS net_sales,
        ROUND(SUM(v.gross_profit),2) AS gross_profit,
        fn_gross_margin_pct(SUM(v.net_sales), SUM(v.cogs)) AS gross_margin_pct,
        COUNT(DISTINCT v.order_id) AS completed_orders,
        COUNT(DISTINCT v.customer_id) AS active_customers,
        SUM(v.quantity) AS units_sold
    FROM vw_sales_line v
    WHERE v.order_date >= v_month_start
      AND v.order_date < v_next_month;

    -- Result set 2: store performance.
    SELECT
        v.store_name,
        ROUND(SUM(v.net_sales),2) AS net_sales,
        ROUND(SUM(v.gross_profit),2) AS gross_profit,
        COUNT(DISTINCT v.order_id) AS completed_orders
    FROM vw_sales_line v
    WHERE v.order_date >= v_month_start
      AND v.order_date < v_next_month
    GROUP BY v.store_id, v.store_name
    ORDER BY net_sales DESC;

    -- Result set 3: budget vs actual.
    SELECT *
    FROM vw_budget_vs_actual
    WHERE budget_month = v_month_start
    ORDER BY store_id;

    -- Result set 4: products requiring attention.
    SELECT
        store_name,
        sku,
        product_name,
        current_stock,
        reorder_level,
        stock_status
    FROM vw_current_inventory
    WHERE stock_status IN ('Critical','Reorder')
    ORDER BY store_name, stock_status, product_name;
END$$
DELIMITER ;

-- Example:
CALL sp_monthly_management_report('2025-12-15');

-- =====================================================================
-- 18. REORDER PROCEDURE
-- =====================================================================

DROP PROCEDURE IF EXISTS sp_reorder_recommendations;
DELIMITER $$
CREATE PROCEDURE sp_reorder_recommendations(IN p_store_id INT)
BEGIN
    WITH max_date AS (
        SELECT MAX(order_date) AS max_order_date FROM vw_sales_line
    ),
    recent_sales AS (
        SELECT
            v.store_id,
            v.product_id,
            SUM(v.quantity) AS units_sold_90d
        FROM vw_sales_line v
        CROSS JOIN max_date m
        WHERE v.order_date > DATE_SUB(m.max_order_date, INTERVAL 90 DAY)
          AND v.store_id = p_store_id
        GROUP BY v.store_id, v.product_id
    )
    SELECT
        ci.store_name,
        ci.sku,
        ci.product_name,
        ci.current_stock,
        ci.reorder_level,
        ci.safety_stock,
        sup.standard_lead_days,
        ROUND(COALESCE(rs.units_sold_90d,0) / 90,2) AS avg_daily_units,
        GREATEST(
            CEIL(
                (COALESCE(rs.units_sold_90d,0) / 90) * sup.standard_lead_days
                + ci.safety_stock
                - ci.current_stock
            ),
            0
        ) AS suggested_reorder_qty
    FROM vw_current_inventory ci
    JOIN product p ON p.product_id = ci.product_id
    JOIN supplier sup ON sup.supplier_id = p.supplier_id
    LEFT JOIN recent_sales rs
      ON rs.store_id = ci.store_id
     AND rs.product_id = ci.product_id
    WHERE ci.store_id = p_store_id
    ORDER BY suggested_reorder_qty DESC, ci.product_name;
END$$
DELIMITER ;

CALL sp_reorder_recommendations(1);

-- =====================================================================
-- 19. AUTOMATED / RECURRING KPI SNAPSHOT
-- =====================================================================

CREATE TABLE management_kpi_snapshot (
    report_month       DATE PRIMARY KEY,
    net_sales          DECIMAL(16,2) NOT NULL,
    gross_profit       DECIMAL(16,2) NOT NULL,
    gross_margin_pct   DECIMAL(10,2),
    completed_orders   INT NOT NULL,
    active_customers   INT NOT NULL,
    units_sold         INT NOT NULL,
    refreshed_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP
);

DROP PROCEDURE IF EXISTS sp_refresh_monthly_kpi;
DELIMITER $$
CREATE PROCEDURE sp_refresh_monthly_kpi(IN p_month DATE)
BEGIN
    DECLARE v_month_start DATE;
    DECLARE v_next_month DATE;

    SET v_month_start = CAST(DATE_FORMAT(p_month, '%Y-%m-01') AS DATE);
    SET v_next_month = DATE_ADD(v_month_start, INTERVAL 1 MONTH);

    INSERT INTO management_kpi_snapshot (
        report_month,
        net_sales,
        gross_profit,
        gross_margin_pct,
        completed_orders,
        active_customers,
        units_sold
    )
    SELECT
        v_month_start,
        ROUND(COALESCE(SUM(net_sales),0),2),
        ROUND(COALESCE(SUM(gross_profit),0),2),
        fn_gross_margin_pct(
            COALESCE(SUM(net_sales),0),
            COALESCE(SUM(cogs),0)
        ),
        COUNT(DISTINCT order_id),
        COUNT(DISTINCT customer_id),
        COALESCE(SUM(quantity),0)
    FROM vw_sales_line
    WHERE order_date >= v_month_start
      AND order_date < v_next_month
    ON DUPLICATE KEY UPDATE
        net_sales = VALUES(net_sales),
        gross_profit = VALUES(gross_profit),
        gross_margin_pct = VALUES(gross_margin_pct),
        completed_orders = VALUES(completed_orders),
        active_customers = VALUES(active_customers),
        units_sold = VALUES(units_sold);
END$$
DELIMITER ;

-- Refresh an existing month manually:
CALL sp_refresh_monthly_kpi('2025-12-01');

SELECT *
FROM management_kpi_snapshot
ORDER BY report_month;

-- OPTIONAL: MySQL Event Scheduler automation.
-- Some hosted databases do not allow CREATE EVENT, so it is intentionally
-- commented out. Enable only when your MySQL environment permits it.
--
-- SET GLOBAL event_scheduler = ON;
--
-- CREATE EVENT ev_refresh_previous_month_kpi
-- ON SCHEDULE EVERY 1 MONTH
-- STARTS TIMESTAMP(DATE_FORMAT(CURRENT_DATE + INTERVAL 1 MONTH, '%Y-%m-01'))
-- DO
--   CALL sp_refresh_monthly_kpi(CURRENT_DATE - INTERVAL 1 MONTH);

-- =====================================================================
-- 20. MANAGEMENT QUESTIONS THIS PROJECT CAN ANSWER
-- =====================================================================
-- 1. Which product categories and SKUs drive revenue and gross profit?
-- 2. Which stores and sales channels are strongest or weakest?
-- 3. Are sales meeting monthly budgets?
-- 4. Which stores are overspending against operating-expense budgets?
-- 5. Which products are at critical/reorder stock levels?
-- 6. How much stock should be reordered based on recent demand and lead time?
-- 7. Which products are slow-moving and tie up working capital?
-- 8. What is the inventory turnover by product?
-- 9. Which suppliers deliver on time and in full?
-- 10. Which customers/segments generate the most lifetime value?
-- 11. What is the month-over-month sales trend?
-- 12. What does a transparent 3-month moving-average forecast suggest?
-- 13. Which products should be classified A/B/C by sales contribution?
-- 14. What should management see in a recurring monthly KPI report?

-- =====================================================================
-- 21. PORTFOLIO / CV POSITIONING
-- =====================================================================
-- Suggested project title:
--   "Interior Fittings Sales, Inventory & Operations Analytics | MySQL"
--
-- Suggested CV bullets:
--   • Built an end-to-end MySQL analytics project for an interior-fittings
--     business covering sales, customers, inventory, budgets, expenses,
--     procurement and supplier performance.
--   • Used CTEs, window functions, views, stored functions and procedures
--     to analyse KPI trends, budget variance, customer value, product
--     performance, inventory turnover and reorder requirements.
--   • Developed a 3-month moving-average demand forecast and automated KPI
--     snapshot procedure to support recurring management reporting.
--   • Implemented data-quality controls and inventory-validation triggers,
--     improving the reliability and auditability of analytical outputs.
--
-- NOTE FOR INTERVIEWS:
-- Call this a "synthetic business analytics project", not employer data.
-- Explain the business question, the schema, the checks, the analysis and
-- the decisions the queries support.
-- =====================================================================
