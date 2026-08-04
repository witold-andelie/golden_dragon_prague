-- ============================================================
-- Golden Dragon Prague - Sample Data
--
-- All timestamps are set in the past (2024-2025) to ensure
-- queries return meaningful historical results for analysis.
--
-- Data Volume:
--   - 8 employees (mixed Chinese + Czech names, realistic for Prague)
--   - 8 customers (including VIP with high loyalty)
--   - 17 dishes across 6 categories
--   - 14 EU allergens correctly linked to dishes
--   - 10 tables with realistic layout
--   - 15+ orders across all channels and statuses
--   - Multiple reservations
--   - Payment records
--
-- Run: psql -U postgres -d golden_dragon_prague -f sql/07_data.sql
-- ============================================================

-- ============================================================
-- EMPLOYEES (8 staff members)
-- ============================================================
INSERT INTO Employees (full_name, role, phone, hire_date) VALUES
('Li Wei',     'owner',            '+420 777 123 456', '2020-01-15'),
('Jana Novakova', 'waiter',        '+420 608 555 111', '2022-03-10'),
('Petr Svoboda', 'chef',           '+420 602 334 778', '2021-06-01'),
('Mei Chen',   'chef',             '+420 777 889 001', '2021-08-15'),
('Tomas Dvorak', 'delivery_driver', '+420 731 222 333', '2023-01-20'),
('Anna Kovarova', 'waiter',        '+420 608 777 222', '2023-05-01'),
('Chen Wei',   'manager',          '+420 777 999 888', '2020-06-01'),
('Lucie Cerna', 'waiter',          '+420 608 111 333', '2024-02-01');

-- ============================================================
-- USERS (8 customers)
-- ============================================================
INSERT INTO Users (username, full_name, email, phone, role, loyalty_points, created_at) VALUES
('jan.novak',    'Jan Novak',       'jan.novak@email.cz',    '721 334 556', 'customer', 245,  '2023-01-10'),
('maria.k',      'Maria Kralova',   'maria.k@email.cz',      '603 112 445', 'customer', 120,  '2023-02-15'),
('wei.zhang',    'Wei Zhang',       'wei.zhang@seznam.cz',   '777 555 888', 'vip',      890,  '2022-11-01'),
('petr.h',       'Petr Horak',      'petr.horak@gmail.com',  '608 999 001', 'customer', 65,   '2024-01-05'),
('sophia.li',    'Sophia Li',       'sophia@dragon.cz',      '602 123 789', 'customer', 310,  '2023-06-20'),
('klara.b',      'Klara Benesova',  NULL,                    '720 445 667', 'customer', 40,   '2024-03-10'),
('martin.v',     'Martin Vojtech',  'martin@email.cz',       '721 888 999', 'customer', 180,  '2023-08-15'),
('elena.c',      'Elena Cerna',     'elena@seznam.cz',       '602 777 444', 'vip',      520,  '2022-09-01');

-- ============================================================
-- MENU CATEGORIES (6 categories)
-- ============================================================
INSERT INTO MenuCategories (name_cz, name_en, display_order) VALUES
('Předkrmy',        'Starters',           1),
('Polévky',         'Soups',              2),
('Hlavní jídla',    'Main Courses',       3),
('Obědová nabídka', 'Lunch Menu',         4),
('Přílohy & Rýže',  'Sides & Rice',       5),
('Nápoje',          'Beverages',          6);

-- ============================================================
-- MENU ITEMS (17 dishes with CZK prices)
-- ============================================================
INSERT INTO Menus (category_id, name_cz, name_en, description, price_regular, price_lunch, spice_level, estimated_prep_minutes) VALUES
(1, 'Jarní závitky (4 ks)',           'Spring Rolls (4 pcs)',           'Crispy vegetable spring rolls with sweet chili dip',               129, 109, 1, 10),
(1, 'Křupavé kuřecí nugety',           'Crispy Chicken Nuggets',         'Breaded chicken nuggets with fries',                              139, NULL, 1, 12),
(1, 'Gyoza vepřové (6 ks)',           'Pork Gyoza (6 pcs)',              'Pan-fried pork dumplings with soy dipping sauce',                 149, NULL, 2, 15),
(2, 'Kuřecí polévka se zázvorem',     'Chicken Ginger Soup',            'Clear chicken broth with fresh ginger and scallions',              89,  69, 2, 8),
(2, 'Kyselá a pálivá polévka',         'Hot & Sour Soup',                'Classic spicy and sour soup with tofu and bamboo shoots',          95,  75, 4, 10),
(3, 'Kung Pao kuře s rýží',           'Kung Pao Chicken with Rice',     'Spicy stir-fried chicken with peanuts and dried chilies',         189, 149, 4, 18),
(3, 'Smažené nudle se zeleninou a kuřetem', 'Stir-fried Noodles with Chicken', 'Wok-fried egg noodles with vegetables',         179, 139, 2, 14),
(3, 'Pekingská kachna (1/4)',         'Peking Duck (1/4)',              'Roasted Peking duck with pancakes and hoisin sauce',              249, NULL, 1, 25),
(3, 'Mapo tofu s rýží',               'Mapo Tofu with Rice',            'Silky tofu in spicy chili bean sauce',                            169, 129, 5, 15),
(3, 'Sladkokyselá vepřová s ananasem','Sweet & Sour Pork',              'Battered pork with pineapple in tangy sweet sauce',               185, 145, 1, 16),
(3, 'Hovězí v černé pepřové omáčce', 'Beef in Black Pepper Sauce',     'Tender beef strips in aromatic black pepper sauce',              199, 159, 3, 18),
(4, 'Obědové menu A - Kung Pao + polévka', 'Lunch Set A - Kung Pao + Soup', 'Kung Pao Chicken with choice of soup',                        149, 149, 3, 20),
(4, 'Obědové menu B - Nudle + polévka',    'Lunch Set B - Noodles + Soup',  'Stir-fried Noodles with choice of soup',                     139, 139, 2, 18),
(5, 'Smažená rýže se zeleninou',     'Vegetable Fried Rice',           'Wok-fried rice with mixed vegetables',                            99,  79, 1, 8),
(5, 'Jasmínová rýže',                 'Jasmine Rice',                   'Steamed fragrant jasmine rice',                                   49, NULL, 0, 5),
(6, 'Čínský zelený čaj',              'Chinese Green Tea',              'Premium Chinese green tea, refillable',                           59, NULL, 0, 3),
(6, 'Coca Cola 0.33l',                'Coca Cola 0.33l',               'Ice cold Coca-Cola',                                               55, NULL, 0, 1);

-- ============================================================
-- ALLERGENS (14 EU mandatory)
-- ============================================================
INSERT INTO Allergens (code, name_en, name_cz) VALUES
('1',  'Cereals containing gluten',         'Obiloviny obsahující lepek'),
('2',  'Crustaceans',                        'Korýši'),
('3',  'Eggs',                              'Vejce'),
('4',  'Fish',                              'Ryby'),
('5',  'Peanuts',                           'Arašídy'),
('6',  'Soybeans',                          'Sója'),
('7',  'Milk',                              'Mléko'),
('8',  'Nuts',                              'Skořápkové plody'),
('9',  'Celery',                            'Celer'),
('10', 'Mustard',                           'Hořčice'),
('11', 'Sesame seeds',                      'Sezam'),
('12', 'Sulphur dioxide and sulphites',     'Oxid siřičitý a siřičitany'),
('13', 'Lupin',                             'Vlčí bob'),
('14', 'Molluscs',                          'Měkkýši');

-- ============================================================
-- MENU ALLERGENS (realistic allergen mappings)
-- Kung Pao Chicken correctly has peanuts - critical safety info
-- ============================================================
INSERT INTO MenuAllergens (menu_id, allergen_id) VALUES
(1, 1), (1, 6),                          -- Spring Rolls: gluten, soy
(3, 1), (3, 3), (3, 6), (3, 7),          -- Gyoza: gluten, eggs, soy, milk
(6, 1), (6, 5), (6, 6), (6, 8),          -- Kung Pao: gluten, PEANUTS, soy, nuts
(7, 1), (7, 6),                          -- Noodles: gluten, soy
(9, 6), (9, 7),                          -- Mapo Tofu: soy, milk
(10, 1), (10, 3), (10, 7),               -- Sweet & Sour: gluten, eggs, milk
(12, 1), (12, 3), (12, 6);              -- Lunch Set A: gluten, eggs, soy

-- ============================================================
-- INVENTORY (realistic stock levels)
-- ============================================================
INSERT INTO Inventory (menu_id, quantity) VALUES
(1,  85),   -- Spring Rolls
(2,  120),  -- Chicken Nuggets
(3,  45),   -- Gyoza
(4,  200),  -- Chicken Soup
(5,  60),   -- Hot & Sour Soup
(6,  30),   -- Kung Pao Chicken
(7,  75),   -- Stir-fried Noodles
(8,  15),   -- Peking Duck (limited)
(9,  40),   -- Mapo Tofu
(10, 90),   -- Sweet & Sour Pork
(11, 55),   -- Beef Black Pepper
(12, 50),   -- Lunch Set A
(13, 65),   -- Lunch Set B
(14, 150),  -- Vegetable Fried Rice
(15, 300),  -- Jasmine Rice
(16, 200),  -- Green Tea
(17, 180);  -- Coca Cola

-- ============================================================
-- RESTAURANT TABLES (10 tables, realistic Prague layout)
-- ============================================================
INSERT INTO RestaurantTables (table_number, capacity, zone) VALUES
('T01',  2, 'main'),
('T02',  2, 'main'),
('T03',  4, 'main'),
('T04',  4, 'window'),
('T05',  4, 'window'),
('T06',  6, 'main'),
('T07',  6, 'private'),
('VIP1', 8, 'private'),
('VIP2', 10, 'private'),
('T10',  2, 'terrace');

-- ============================================================
-- RESERVATIONS
-- ============================================================
INSERT INTO Reservations (user_id, table_id, reservation_time, party_size, notes, status) VALUES
(1, 3, '2025-06-15 19:00:00', 4, 'Birthday celebration - bringing cake', 'completed'),
(3, 7, '2025-06-20 18:30:00', 6, 'Company dinner, need projector', 'completed'),
(2, 4, '2025-07-10 12:30:00', 2, 'Anniversary lunch', 'completed'),
(5, 9, '2025-07-25 19:00:00', 8, 'Business dinner - VIP room', 'confirmed'),
(6, 3, '2025-08-05 18:00:00', 4, 'Family gathering', 'pending'),
(4, 10, '2025-08-12 12:00:00', 2, 'Quick lunch', 'confirmed');

-- ============================================================
-- ORDERS (15 orders across all channels and statuses)
-- Timestamps spread across past months for realistic analysis
-- ============================================================

-- Order 1: Dine-in, completed, weekday lunch (triggers lunch pricing)
--
-- Monday. This used to be dated 2025-06-15, which is a SUNDAY - so the comment
-- claimed lunch pricing that the trigger never applied. It was not alone: NOT
-- ONE of the fifteen seed orders fell inside Mon-Fri 11:00-14:30, so
-- price_lunch, get_effective_price(), is_lunch_window(),
-- v_lunch_vs_dinner_analysis and fact_orders.is_lunch_order were all dead
-- weight against this data - the lunch analysis view returned a single
-- 'Regular Pricing' row and looked perfectly healthy while doing it.
-- Orders 1, 9, 11 and 15 now land in the window; 4 sits just past it.
INSERT INTO Orders (user_id, employee_id, table_id, order_type, status, source, order_time, special_requests)
VALUES (1, 2, 3, 'dine_in', 'confirmed', 'walk-in', '2025-06-16 12:30:00',
        '{"spicy": "less spicy", "notes": "Small portion for child", "allergies": ["peanuts"]}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (1, 1, 2), (1, 6, 1);

-- Order 2: Delivery via Wolt, completed
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, delivery_address, special_requests)
VALUES (2, 5, 'delivery', 'confirmed', 'wolt', '2025-06-18 19:15:00',
        '{"street": "Korunni 45", "city": "Prague 2", "postal": "12000", "note": "2nd floor, buzzer 12"}',
        '{"notes": "Please hurry, I am hungry", "spicy": "extra"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (2, 7, 2), (2, 14, 1);

-- Order 3: Private event, completed
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, special_requests)
VALUES (3, 1, 'event', 'confirmed', 'phone', '2025-06-20 18:30:00',
        -- The 'diet' key is what Query 7 in 09_analytics_queries.sql and the GIN
        -- example in docs/ARCHITECTURE.md both search for. No seed order carried
        -- one, so both demonstrated the feature by returning nothing. The notes
        -- here already said vegetarian; this states it in the field meant to
        -- hold it.
        '{"event": "30th birthday party", "guests": 12, "diet": "vegetarian", "notes": "Private room VIP1, vegetarian options needed"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (3, 8, 1), (3, 6, 3), (3, 9, 2);

INSERT INTO Events (order_id, event_date, location, expected_guests)
VALUES (3, '2025-06-20 18:30:00', 'Golden Dragon - VIP1 private room', 12);

-- Order 4: Dine-in, completed - REGRESSION WITNESS for the lunch cut-off
--
-- Monday 14:45: a weekday, after 14:30, so this is REGULAR pricing. The old
-- rule `EXTRACT(HOUR ...) BETWEEN 11 AND 14` accepted everything up to 14:59
-- and would have charged this order lunch prices. Keeping one seed order in
-- the 14:30-14:59 gap means that bug can never come back unnoticed: it would
-- change this order's subtotal from 283.00 to 243.00 the moment it did.
INSERT INTO Orders (user_id, employee_id, table_id, order_type, status, source, order_time, special_requests)
VALUES (4, 3, 1, 'dine_in', 'confirmed', 'phone', '2025-06-23 14:45:00', '{"notes": "Window seat please"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (4, 10, 1), (4, 15, 2);

-- Order 5: Delivery via Bolt, completed
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, delivery_address, special_requests)
VALUES (5, 5, 'delivery', 'confirmed', 'bolt', '2025-07-02 20:00:00',
        '{"street": "Vinohradska 12", "city": "Prague 2", "postal": "12000"}',
        '{"notes": "No MSG please", "allergies": ["soy"]}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (5, 11, 1), (5, 7, 1);

-- Order 6: Takeaway, completed
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, special_requests)
VALUES (6, 4, 'takeaway', 'confirmed', 'walk-in', '2025-07-05 12:15:00', '{"notes": "Extra napkins"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (6, 2, 2), (6, 1, 1);

-- Order 7: Dine-in VIP customer, completed (high value)
INSERT INTO Orders (user_id, employee_id, table_id, order_type, status, source, order_time, special_requests)
VALUES (3, 1, 8, 'dine_in', 'confirmed', 'walk-in', '2025-07-10 19:30:00',
        '{"notes": "VIP customer - best service", "allergies": ["nuts"]}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (7, 8, 1), (7, 4, 2), (7, 16, 2);

-- Order 8: Delivery, completed
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, delivery_address, special_requests)
VALUES (7, 5, 'delivery', 'confirmed', 'wolt', '2025-07-12 18:45:00',
        '{"street": "Jilska 5", "city": "Prague 1", "postal": "11000"}',
        '{"notes": "Ring doorbell twice"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (8, 9, 1), (8, 14, 1);

-- Order 9: Dine-in, preparing (active order), weekday lunch
-- The 9/10/11 "currently active" cluster moves from Sunday 2025-08-03 to
-- Monday 2025-08-04 so that a "Business lunch" is actually served at lunch.
INSERT INTO Orders (user_id, employee_id, table_id, order_type, status, source, order_time, special_requests)
-- Enters as 'confirmed'; moved to 'preparing' in the ORDER LIFECYCLE block.
VALUES (1, 2, 6, 'dine_in', 'confirmed', 'walk-in', '2025-08-04 12:00:00', '{"notes": "Business lunch"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (9, 13, 2), (9, 5, 2);

-- Order 10: Delivery, out_for_delivery (active order)
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, delivery_address, special_requests)
-- Enters as 'confirmed'; walked to 'out_for_delivery' in the LIFECYCLE block.
VALUES (8, 5, 'delivery', 'confirmed', 'bolt', '2025-08-04 12:15:00',
        '{"street": "Ostrovni 22", "city": "Prague 1", "postal": "11000", "note": "Leave at door"}',
        '{"notes": "Extra sauce"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (10, 3, 1), (10, 16, 1);

-- Order 11: Dine-in, new (just placed)
INSERT INTO Orders (user_id, employee_id, table_id, order_type, status, source, order_time, special_requests)
VALUES (4, 6, 5, 'dine_in', 'new', 'walk-in', '2025-08-04 12:30:00', '{"notes": "Celebrating promotion"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (11, 11, 1);

-- Order 12: Event, confirmed (upcoming) - enters as 'new', confirmed below
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, special_requests)
VALUES (6, 1, 'event', 'new', 'phone', '2025-08-10 18:00:00',
        '{"event": "Corporate team dinner", "guests": 15, "notes": "Need separate bills"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (12, 8, 2), (12, 10, 2), (12, 16, 5);

-- Order 13: Dine-in, cancelled (see the ORDER LIFECYCLE block below - this row
-- is inserted as 'confirmed' and cancelled there, because a cancellation has to
-- be a transition for the restock trigger to see it).
INSERT INTO Orders (user_id, employee_id, table_id, order_type, status, source, order_time, special_requests)
VALUES (2, 4, 2, 'dine_in', 'confirmed', 'walk-in', '2025-07-28 19:00:00', '{"notes": "Cancelled - plans changed"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (13, 1, 2);

-- Order 14: Delivery, completed (large order)
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, delivery_address, special_requests)
VALUES (3, 5, 'delivery', 'confirmed', 'wolt', '2025-07-15 19:00:00',
        '{"street": "Slezska 15", "city": "Prague 2", "postal": "12000", "note": "Office party, 8th floor"}',
        '{"notes": "Include utensils and napkins", "guests": "6"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (14, 6, 2), (14, 7, 2), (14, 11, 2), (14, 14, 2);

-- Order 15: Takeaway, completed
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, special_requests)
-- Monday. Was 2025-07-20, a Sunday, despite ordering a Lunch Set off the
-- lunch menu and saying so in its own notes.
VALUES (5, 4, 'takeaway', 'confirmed', 'website', '2025-07-21 11:45:00', '{"notes": "Lunch special"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (15, 12, 1);

-- ============================================================
-- FINALIZE ALL ORDERS
-- Triggers compute_order_totals and apply delivery fees
-- ============================================================
SELECT finalize_order(1);
SELECT finalize_order(2);
SELECT finalize_order(3);
SELECT finalize_order(4);
SELECT finalize_order(5);
SELECT finalize_order(6);
SELECT finalize_order(7);
SELECT finalize_order(8);
SELECT finalize_order(9);
SELECT finalize_order(10);
SELECT finalize_order(11);
SELECT finalize_order(12);
SELECT finalize_order(13);
SELECT finalize_order(14);
SELECT finalize_order(15);

-- ============================================================
-- ORDER LIFECYCLE
--
-- Every order above is inserted at the status it ENTERED the system with, then
-- walked forward to its real status here. That is not decoration: three of the
-- seven triggers fire on AFTER UPDATE OF status, so an order inserted straight
-- at its final status never touches any of them.
--
-- Seeding the final status directly left all three dead in a fresh build:
--
--   trg_order_cancel_restock - order 13's two Spring Rolls were deducted from
--       Inventory when the line item was added and never came back, because
--       nothing ever transitioned the order INTO 'cancelled'. Stock was
--       permanently understated by every cancelled order in the seed.
--   trg_order_audit_log      - OrderAuditLog was empty in every fresh build,
--       while the docs advertised it as a compliance audit trail.
--   trg_order_status         - loyalty points were never awarded, so
--       Users.loyalty_points was a hand-typed number with no relationship to
--       the orders sitting in the same file - the same drift that made the
--       payment amounts wrong.
--
-- Users.loyalty_points as seeded is therefore an OPENING BALANCE (history from
-- before this dataset). The points earned by orders 1-8, 14 and 15 are added on
-- top by the trigger, exactly as they would be in production.
-- ============================================================
UPDATE Orders SET status = 'confirmed'        WHERE order_id = 12;
UPDATE Orders SET status = 'preparing'        WHERE order_id = 9;
UPDATE Orders SET status = 'preparing'        WHERE order_id = 10;
UPDATE Orders SET status = 'out_for_delivery' WHERE order_id = 10;
UPDATE Orders SET status = 'cancelled'        WHERE order_id = 13;
UPDATE Orders SET status = 'completed'        WHERE order_id IN (1, 2, 3, 4, 5, 6, 7, 8, 14, 15);

-- OrderAuditLog.changed_at defaults to NOW(), which would stamp this whole
-- backdated dataset with the build time and make the audit trail useless for
-- any time-based query. Anchor each entry to its order instead.
UPDATE OrderAuditLog a
SET changed_at = o.order_time + INTERVAL '45 minutes'
FROM Orders o
WHERE o.order_id = a.order_id;

-- ============================================================
-- PAYMENTS
--
-- Must come AFTER finalize_order: what a guest pays is the VAT-inclusive
-- Orders.total, and that number does not exist until the order is finalized.
--
-- The amounts are DERIVED from that total, never typed in. They used to be
-- hand-written VAT-exclusive figures that had drifted from the totals the
-- triggers compute - order 4 was recorded as 185.00 against a real 316.96,
-- order 14 as 1245.00 against 1491.84 - so nine of the ten payments were
-- silently short. v_order_summary reported them all as PAID only because its
-- own payment logic was broken too; with that fixed they showed up as PARTIAL,
-- which is what a books-don't-balance state should look like.
--
-- Deriving the amount means a menu price change, a VAT rate change or a new
-- line item can never desynchronise the seed data again: the payment follows
-- whatever the order actually came to.
--
-- Orders 1, 3, 11, 12 and 13 deliberately have no payment row, so the UNPAID
-- and PARTIAL branches of v_order_summary stay exercised by the seed data:
--   1, 3  - completed, invoiced on account (settled outside this system)
--   11    - dine-in still open, guest has not asked for the bill
--   12    - event confirmed for a future date, deposit not yet taken
--   13    - cancelled before service, nothing to collect
-- Order 9 pays a 200 CZK deposit on an order still being prepared, which is
-- the one genuine PARTIAL in the data.
-- ============================================================
INSERT INTO Payments (order_id, method, amount, paid_at)
SELECT v.order_id, v.method, o.total, v.paid_at
FROM (VALUES
    (2,  'online', TIMESTAMP '2025-06-18 19:20:00'),
    (4,  'card',   TIMESTAMP '2025-06-23 14:55:00'),
    (5,  'qr',     TIMESTAMP '2025-07-02 20:05:00'),
    (6,  'cash',   TIMESTAMP '2025-07-05 12:25:00'),
    (7,  'card',   TIMESTAMP '2025-07-10 20:00:00'),
    (8,  'online', TIMESTAMP '2025-07-12 18:50:00'),
    (10, 'online', TIMESTAMP '2025-08-04 12:20:00'),
    (14, 'online', TIMESTAMP '2025-07-15 19:10:00'),
    (15, 'card',   TIMESTAMP '2025-07-21 11:50:00')
) AS v(order_id, method, paid_at)
JOIN Orders o ON o.order_id = v.order_id;

-- The one intentional partial payment: a deposit on an in-progress order.
INSERT INTO Payments (order_id, method, amount, paid_at, reference)
VALUES (9, 'card', 200.00, '2025-08-04 12:10:00', 'Deposit - balance due on collection');

-- ============================================================
-- DATA SUMMARY
-- ============================================================
-- Counts below are by Orders.status and must sum to "Orders placed".
-- They previously claimed 11 completed orders against 10 in the data, and
-- omitted the confirmed one entirely, so the totals did not add up - which
-- makes the block useless as the sanity check it is meant to be.
--
-- Orders placed:           15
--   completed:             10   (1-8, 14, 15)
--   confirmed:              1   (12 - future event)
--   preparing:              1   (9)
--   new:                    1   (11)
--   out_for_delivery:       1   (10)
--   cancelled:              1   (13)
--
-- Orders with order_type = 'event':  2   (3 completed, 12 upcoming)
-- Rows in Events:                    1   (only order 3 has been scheduled)
-- Reservations:                      6   (3 completed, 2 confirmed, 1 pending)
-- Payments:                         10   (9 paid in full, 1 deposit on order 9)
--   fully paid:                      9
--   partial:                         1   (9)
--   unpaid:                          5   (1, 3, 11, 12, 13)
--
-- OrderAuditLog rows:               15   (one per status transition above:
--                                        10 completions, 12 confirmed,
--                                        9 preparing, 10 preparing +
--                                        out_for_delivery, 13 cancelled.
--                                        Order 11 never moves off 'new'.)
--
-- Users.loyalty_points is an opening balance PLUS points earned here. After the
-- lifecycle block runs the balances are 253 / 130 / 956 / 71 / 321 / 49 / 187 /
-- 520 - one point per full 50 CZK of each completed order, on top of the
-- seeded history. Elena Cerna (user 8) has no orders, so her 520 is untouched;
-- she is the zero-activity case the RFM and NTILE queries need.
--
-- Inventory reflects the cancellation: order 13's 2 Spring Rolls are returned,
-- so menu_id 1 settles at 82 of its seeded 85 (orders 1 and 6 consumed 3).
-- ============================================================
