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

-- Order 1: Dine-in, completed, weekday lunch (triggered lunch pricing)
INSERT INTO Orders (user_id, employee_id, table_id, order_type, status, source, order_time, special_requests)
VALUES (1, 2, 3, 'dine_in', 'completed', 'walk-in', '2025-06-15 12:30:00',
        '{"spicy": "less spicy", "notes": "Small portion for child", "allergies": ["peanuts"]}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (1, 1, 2), (1, 6, 1);

-- Order 2: Delivery via Wolt, completed
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, delivery_address, special_requests)
VALUES (2, 5, 'delivery', 'completed', 'wolt', '2025-06-18 19:15:00',
        '{"street": "Korunni 45", "city": "Prague 2", "postal": "12000", "note": "2nd floor, buzzer 12"}',
        '{"notes": "Please hurry, I am hungry", "spicy": "extra"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (2, 7, 2), (2, 14, 1);

-- Order 3: Private event, completed
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, special_requests)
VALUES (3, 1, 'event', 'completed', 'phone', '2025-06-20 18:30:00',
        '{"event": "30th birthday party", "guests": 12, "notes": "Private room VIP1, vegetarian options needed"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (3, 8, 1), (3, 6, 3), (3, 9, 2);

INSERT INTO Events (order_id, event_date, location, expected_guests)
VALUES (3, '2025-06-20 18:30:00', 'Golden Dragon - VIP1 private room', 12);

-- Order 4: Dine-in, completed
INSERT INTO Orders (user_id, employee_id, table_id, order_type, status, source, order_time, special_requests)
VALUES (4, 3, 1, 'dine_in', 'completed', 'phone', '2025-06-22 13:00:00', '{"notes": "Window seat please"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (4, 10, 1), (4, 15, 2);

-- Order 5: Delivery via Bolt, completed
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, delivery_address, special_requests)
VALUES (5, 5, 'delivery', 'completed', 'bolt', '2025-07-02 20:00:00',
        '{"street": "Vinohradska 12", "city": "Prague 2", "postal": "12000"}',
        '{"notes": "No MSG please", "allergies": ["soy"]}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (5, 11, 1), (5, 7, 1);

-- Order 6: Takeaway, completed
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, special_requests)
VALUES (6, 4, 'takeaway', 'completed', 'walk-in', '2025-07-05 12:15:00', '{"notes": "Extra napkins"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (6, 2, 2), (6, 1, 1);

-- Order 7: Dine-in VIP customer, completed (high value)
INSERT INTO Orders (user_id, employee_id, table_id, order_type, status, source, order_time, special_requests)
VALUES (3, 1, 8, 'dine_in', 'completed', 'walk-in', '2025-07-10 19:30:00',
        '{"notes": "VIP customer - best service", "allergies": ["nuts"]}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (7, 8, 1), (7, 4, 2), (7, 16, 2);

-- Order 8: Delivery, completed
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, delivery_address, special_requests)
VALUES (7, 5, 'delivery', 'completed', 'wolt', '2025-07-12 18:45:00',
        '{"street": "Jilska 5", "city": "Prague 1", "postal": "11000"}',
        '{"notes": "Ring doorbell twice"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (8, 9, 1), (8, 14, 1);

-- Order 9: Dine-in, preparing (active order)
INSERT INTO Orders (user_id, employee_id, table_id, order_type, status, source, order_time, special_requests)
VALUES (1, 2, 6, 'dine_in', 'preparing', 'walk-in', '2025-08-03 12:00:00', '{"notes": "Business lunch"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (9, 13, 2), (9, 5, 2);

-- Order 10: Delivery, out_for_delivery (active order)
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, delivery_address, special_requests)
VALUES (8, 5, 'delivery', 'out_for_delivery', 'bolt', '2025-08-03 12:15:00',
        '{"street": "Ostrovni 22", "city": "Prague 1", "postal": "11000", "note": "Leave at door"}',
        '{"notes": "Extra sauce"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (10, 3, 1), (10, 16, 1);

-- Order 11: Dine-in, new (just placed)
INSERT INTO Orders (user_id, employee_id, table_id, order_type, status, source, order_time, special_requests)
VALUES (4, 6, 5, 'dine_in', 'new', 'walk-in', '2025-08-03 12:30:00', '{"notes": "Celebrating promotion"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (11, 11, 1);

-- Order 12: Event, confirmed (upcoming)
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, special_requests)
VALUES (6, 1, 'event', 'confirmed', 'phone', '2025-08-10 18:00:00',
        '{"event": "Corporate team dinner", "guests": 15, "notes": "Need separate bills"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (12, 8, 2), (12, 10, 2), (12, 16, 5);

-- Order 13: Dine-in, cancelled
INSERT INTO Orders (user_id, employee_id, table_id, order_type, status, source, order_time, special_requests)
VALUES (2, 4, 2, 'dine_in', 'cancelled', 'walk-in', '2025-07-28 19:00:00', '{"notes": "Cancelled - plans changed"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (13, 1, 2);

-- Order 14: Delivery, completed (large order)
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, delivery_address, special_requests)
VALUES (3, 5, 'delivery', 'completed', 'wolt', '2025-07-15 19:00:00',
        '{"street": "Slezska 15", "city": "Prague 2", "postal": "12000", "note": "Office party, 8th floor"}',
        '{"notes": "Include utensils and napkins", "guests": "6"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (14, 6, 2), (14, 7, 2), (14, 11, 2), (14, 14, 2);

-- Order 15: Takeaway, completed
INSERT INTO Orders (user_id, employee_id, order_type, status, source, order_time, special_requests)
VALUES (5, 4, 'takeaway', 'completed', 'website', '2025-07-20 11:45:00', '{"notes": "Lunch special"}');

INSERT INTO OrderDetails (order_id, menu_id, quantity) VALUES (15, 12, 1);

-- ============================================================
-- PAYMENTS
-- ============================================================
INSERT INTO Payments (order_id, method, amount, paid_at) VALUES
(2,  'online',  357.00,  '2025-06-18 19:20:00'),
(4,  'card',    185.00,  '2025-06-22 13:10:00'),
(5,  'qr',      388.00,  '2025-07-02 20:05:00'),
(6,  'cash',    287.00,  '2025-07-05 12:25:00'),
(7,  'card',    1245.00, '2025-07-10 20:00:00'),
(8,  'online',  218.00,  '2025-07-12 18:50:00'),
(9,  'card',    399.00,  '2025-08-03 12:10:00'),
(10, 'online',  253.00,  '2025-08-03 12:20:00'),
(14, 'online',  1245.00, '2025-07-15 19:10:00'),
(15, 'card',    139.00,  '2025-07-20 11:50:00');

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
-- DATA SUMMARY
-- ============================================================
-- Orders placed:           15
-- Completed:               11
-- Active (new/preparing):  2
-- Out for delivery:        1
-- Cancelled:               1
-- Events:                  1
-- Reservations:            6
-- Payments:                10
-- ============================================================
