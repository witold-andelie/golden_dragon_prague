-- ============================================================
-- Golden Dragon Prague - Schema Definition (English Version)
-- Realistic Chinese Restaurant Database for Prague, Czech Republic
--
-- Business Context:
--   - Prices in CZK (Czech Koruna)
--   - 12% VAT for restaurant services (Czech law)
--   - 14 EU allergens mandatory labeling
--   - Lunch specials: Mon-Fri 11:00-14:30
--   - Multiple sales channels: dine-in, takeaway, delivery, events
--   - Table reservations with conflict prevention
--   - Loyalty program: 1 point per 50 CZK spent
--
-- Run: psql -U postgres -f sql/01_schema.sql
-- ============================================================

-- ============================================================
-- TABLE 1: Employees
-- Restaurant staff including chefs, waiters, delivery drivers, owner
-- ============================================================
CREATE TABLE Employees (
    employee_id   SERIAL PRIMARY KEY,
    full_name     VARCHAR(120) NOT NULL,
    role          VARCHAR(30) NOT NULL
        CHECK (role IN ('chef', 'waiter', 'manager', 'delivery_driver', 'owner')),
    phone         VARCHAR(20),
    hire_date     DATE DEFAULT CURRENT_DATE,
    is_active     BOOLEAN DEFAULT TRUE
);

COMMENT ON TABLE Employees IS 'Restaurant staff. Role determines operational permissions and task assignments.';
COMMENT ON COLUMN Employees.role IS 'chef: kitchen staff; waiter: front-of-house; manager: supervisor; delivery_driver: logistics; owner: business owner';

-- ============================================================
-- TABLE 2: Users
-- Customers with loyalty program integration
-- ============================================================
CREATE TABLE Users (
    user_id        SERIAL PRIMARY KEY,
    username       VARCHAR(80) NOT NULL UNIQUE,
    full_name      VARCHAR(120),
    email          VARCHAR(120) UNIQUE,
    phone          VARCHAR(20),
    role           VARCHAR(20) NOT NULL DEFAULT 'customer'
        CHECK (role IN ('customer', 'staff', 'vip')),
    loyalty_points INT DEFAULT 0,
    created_at     TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE Users IS 'Customer accounts with loyalty points tracking. VIP customers get priority service.';
COMMENT ON COLUMN Users.loyalty_points IS 'Accumulated via trigger: 1 point per 50 CZK spent on completed orders';
COMMENT ON COLUMN Users.role IS 'customer: regular diner; staff: restaurant employees; vip: high-value customers';

-- ============================================================
-- TABLE 3: MenuCategories
-- Hierarchical menu organization
-- ============================================================
CREATE TABLE MenuCategories (
    category_id   SERIAL PRIMARY KEY,
    name_cz       VARCHAR(60) NOT NULL,
    name_en       VARCHAR(60),
    display_order INT DEFAULT 10
);

COMMENT ON TABLE MenuCategories IS 'Menu categorization for POS and online ordering. Czech names for local staff, English for tourists.';
COMMENT ON COLUMN MenuCategories.name_cz IS 'Czech category name used by kitchen staff';
COMMENT ON COLUMN MenuCategories.name_en IS 'English name for international customers';

-- ============================================================
-- TABLE 4: Menus
-- Individual dishes with dual pricing (regular vs lunch)
-- ============================================================
CREATE TABLE Menus (
    menu_id               SERIAL PRIMARY KEY,
    category_id           INT REFERENCES MenuCategories(category_id),
    name_cz               VARCHAR(100) NOT NULL,
    name_en               VARCHAR(100) NOT NULL,
    description           TEXT,
    price_regular         NUMERIC(8,2) NOT NULL,
    price_lunch           NUMERIC(8,2),
    spice_level           SMALLINT DEFAULT 2
        CHECK (spice_level BETWEEN 0 AND 5),
    is_available          BOOLEAN DEFAULT TRUE,
    estimated_prep_minutes INT DEFAULT 12
);

COMMENT ON TABLE Menus IS 'Menu items with Czech and English names. Supports time-based pricing (lunch specials).';
COMMENT ON COLUMN Menus.price_regular IS 'Standard price applicable outside lunch hours';
COMMENT ON COLUMN Menus.price_lunch IS 'Discounted price during lunch special window (Mon-Fri 11:00-14:30). NULL if no lunch pricing.';
COMMENT ON COLUMN Menus.spice_level IS '0=none, 1=mild, 2=medium, 3=hot, 4=very hot, 5=extreme';
COMMENT ON COLUMN Menus.estimated_prep_minutes IS 'Kitchen SLA target. Used for order prioritization.';

-- ============================================================
-- TABLE 5: Allergens
-- EU-mandated 14 major allergens
-- ============================================================
CREATE TABLE Allergens (
    allergen_id SERIAL PRIMARY KEY,
    code        VARCHAR(5) NOT NULL UNIQUE,
    name_en     VARCHAR(80) NOT NULL,
    name_cz     VARCHAR(80)
);

COMMENT ON TABLE Allergens IS 'EU Regulation 1169/2011 mandatory allergen declarations. Critical for kitchen safety and legal compliance.';

-- ============================================================
-- TABLE 6: MenuAllergens
-- Many-to-many: which allergens each dish contains
-- ============================================================
CREATE TABLE MenuAllergens (
    menu_id     INT REFERENCES Menus(menu_id) ON DELETE CASCADE,
    allergen_id INT REFERENCES Allergens(allergen_id) ON DELETE CASCADE,
    PRIMARY KEY (menu_id, allergen_id)
);

COMMENT ON TABLE MenuAllergens IS 'Allergen declarations per dish. Kitchen uses this to prevent cross-contamination and warn customers.';

-- ============================================================
-- TABLE 7: Inventory
-- Current stock levels per menu item
-- ============================================================
CREATE TABLE Inventory (
    inventory_id  SERIAL PRIMARY KEY,
    menu_id       INT UNIQUE REFERENCES Menus(menu_id),
    quantity      INT NOT NULL DEFAULT 50 CHECK (quantity >= 0),
    last_updated  TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE Inventory IS 'Real-time stock levels. Triggers auto-deduct on order. CHECK prevents negative stock.';

-- ============================================================
-- TABLE 8: RestaurantTables
-- Physical tables in the restaurant
-- ============================================================
CREATE TABLE RestaurantTables (
    table_id    SERIAL PRIMARY KEY,
    table_number VARCHAR(10) NOT NULL UNIQUE,
    capacity    SMALLINT NOT NULL,
    zone        VARCHAR(30) DEFAULT 'main'
        CHECK (zone IN ('main', 'window', 'terrace', 'private')),
    is_active   BOOLEAN DEFAULT TRUE
);

COMMENT ON TABLE RestaurantTables IS 'Physical seating layout. Zones: main (standard), window (view seating), terrace (outdoor), private (VIP rooms).';

-- ============================================================
-- TABLE 9: Reservations
-- Table bookings with conflict detection
-- ============================================================
CREATE TABLE Reservations (
    reservation_id   SERIAL PRIMARY KEY,
    user_id          INT REFERENCES Users(user_id),
    table_id         INT REFERENCES RestaurantTables(table_id),
    reservation_time TIMESTAMP NOT NULL,
    party_size       SMALLINT NOT NULL,
    status           VARCHAR(20) DEFAULT 'confirmed'
        CHECK (status IN ('pending','confirmed','cancelled','no_show')),
    notes            TEXT,
    created_at       TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE Reservations IS 'Table bookings. Trigger prevents double-booking at overlapping times. 2-hour default duration buffer.';

-- ============================================================
-- TABLE 10: Orders
-- Core business entity - all revenue flows through here
-- ============================================================
CREATE TABLE Orders (
    order_id          SERIAL PRIMARY KEY,
    user_id           INT REFERENCES Users(user_id),
    employee_id       INT REFERENCES Employees(employee_id),
    table_id          INT REFERENCES RestaurantTables(table_id),
    order_type        VARCHAR(20) NOT NULL
        CHECK (order_type IN ('dine_in','takeaway','delivery','event')),
    status            VARCHAR(25) NOT NULL DEFAULT 'new'
        CHECK (status IN ('new','confirmed','preparing','ready','served','out_for_delivery','completed','cancelled')),
    source            VARCHAR(30) DEFAULT 'walk-in'
        CHECK (source IN ('walk-in','phone','website','wolt','bolt','uber_eats')),
    order_time        TIMESTAMP DEFAULT NOW(),
    delivery_address  JSONB,
    special_requests  JSONB,
    subtotal          NUMERIC(10,2),
    vat_rate          NUMERIC(4,2) DEFAULT 0.12,
    vat_amount        NUMERIC(10,2),
    total             NUMERIC(10,2),
    delivery_fee      NUMERIC(8,2) DEFAULT 0,
    discount_amount   NUMERIC(8,2) DEFAULT 0
);

COMMENT ON TABLE Orders IS 'Central order entity. Financial totals computed by triggers. JSONB fields store flexible order metadata.';
COMMENT ON COLUMN Orders.order_type IS 'dine_in: eat at restaurant; takeaway: customer picks up; delivery: third-party delivery; event: private catering';
COMMENT ON COLUMN Orders.status IS 'new→confirmed→preparing→ready→served/out_for_delivery→completed/cancelled';
COMMENT ON COLUMN Orders.source IS 'Revenue attribution: walk-in, phone, website, Wolt, Bolt, Uber Eats';
COMMENT ON COLUMN Orders.delivery_address IS 'JSONB: {street, city, postal, note} for delivery orders';
COMMENT ON COLUMN Orders.special_requests IS 'JSONB: flexible metadata like {spicy:"less", allergies:["peanuts"], notes:"..."}';
COMMENT ON COLUMN Orders.vat_rate IS 'Czech restaurant VAT = 12% (reduced rate for food service)';

-- ============================================================
-- TABLE 11: OrderDetails
-- Line items - one row per menu item per order
-- ============================================================
CREATE TABLE OrderDetails (
    order_detail_id SERIAL PRIMARY KEY,
    order_id        INT REFERENCES Orders(order_id) ON DELETE CASCADE,
    menu_id         INT REFERENCES Menus(menu_id),
    quantity        INT NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(8,2) NOT NULL,
    line_note       TEXT,
    spice_override  SMALLINT
);

COMMENT ON TABLE OrderDetails IS 'Order line items. unit_price captures price at order time (supports price history).';
COMMENT ON COLUMN OrderDetails.unit_price IS 'Price captured at order time. May differ from current menu price (lunch vs regular).';
COMMENT ON COLUMN OrderDetails.line_note IS 'Per-item special instructions: "extra spicy", "no onions", etc.';
COMMENT ON COLUMN OrderDetails.spice_override IS 'Customer can override default spice level for this item';

-- ============================================================
-- TABLE 12: Payments
-- Supports split payments across multiple methods
-- ============================================================
CREATE TABLE Payments (
    payment_id  SERIAL PRIMARY KEY,
    order_id    INT REFERENCES Orders(order_id),
    method      VARCHAR(20)
        CHECK (method IN ('cash','card','qr','voucher','online')),
    amount      NUMERIC(10,2) NOT NULL,
    paid_at     TIMESTAMP DEFAULT NOW(),
    reference   VARCHAR(100)
);

COMMENT ON TABLE Payments IS 'Payment records. Multiple payments per order supported (split checks).';
COMMENT ON COLUMN Payments.method IS 'cash, card, qr (Czech QR payments), voucher (gift card), online (Wolt/Bolt payin)';

-- ============================================================
-- TABLE 13: Events
-- Large private events / catering orders
-- ============================================================
CREATE TABLE Events (
    event_id         SERIAL PRIMARY KEY,
    order_id         INT REFERENCES Orders(order_id),
    event_date       TIMESTAMP NOT NULL,
    location         VARCHAR(200) NOT NULL,
    expected_guests  INT,
    setup_notes      TEXT
);

COMMENT ON TABLE Events IS 'Private events and large catering orders. Linked to Orders for billing.';
COMMENT ON COLUMN Events.location IS 'Usually a VIP room name or external address';
COMMENT ON COLUMN Events.expected_guests IS 'Headcount for kitchen planning and ingredient ordering';

-- ============================================================
-- SCHEMA CONSTRAINTS SUMMARY
-- ============================================================
-- Primary Keys: All tables have SERIAL PKs
-- Foreign Keys: Enforce referential integrity across all relationships
-- Check Constraints: Role enums, status enums, quantity > 0, quantity >= 0
-- Unique Constraints: email, username, table_number, menu_id (inventory)
-- Not Null: Critical business fields enforced
--
-- Design Philosophy:
-- - 3NF for operational tables (no redundant data)
-- - JSONB for flexible/variable attributes (special_requests, delivery_address)
-- - ENUM-like VARCHAR + CHECK for status fields (allows future expansion)
-- ============================================================
