-- ============================================================
-- Golden Dragon Prague - Triggers
--
-- Trigger Architecture:
-- - BEFORE triggers: Validation and data preparation
-- - AFTER triggers: Side effects (inventory, totals, loyalty points)
-- - Conditional triggers: WHEN clause for precise event detection
--
-- Run: psql -U postgres -d golden_dragon_prague -f sql/04_triggers.sql
-- ============================================================

-- ============================================================
-- TRIGGER 1: Inventory Stock Check (BEFORE INSERT)
-- Validates sufficient stock exists before allowing order
--
-- Business Rule: Prevent overselling (negative inventory)
-- ============================================================
CREATE OR REPLACE FUNCTION trg_check_inventory()
RETURNS TRIGGER AS $$
DECLARE
    v_stock INT;
BEGIN
    SELECT quantity INTO v_stock
    FROM Inventory
    WHERE menu_id = NEW.menu_id;

    IF v_stock IS NULL OR v_stock < NEW.quantity THEN
        RAISE EXCEPTION 'Insufficient stock for menu_id=% (requested: %, available: %)',
            NEW.menu_id, NEW.quantity, COALESCE(v_stock, 0);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orderdetail_before
BEFORE INSERT ON OrderDetails
FOR EACH ROW
EXECUTE FUNCTION trg_check_inventory();

COMMENT ON TRIGGER trg_orderdetail_before ON OrderDetails IS 'Validates stock availability before order line item is created. Prevents overselling.';
COMMENT ON FUNCTION trg_check_inventory() IS 'BEFORE INSERT trigger function: checks if requested quantity is in stock. Raises exception if insufficient.';

-- ============================================================
-- TRIGGER 2: Dynamic Pricing + Inventory Deduction (BEFORE INSERT)
-- Automatically applies correct price (lunch vs regular) at order time
--
-- Business Rule: Price is locked at order moment (supports price history)
-- ============================================================
CREATE OR REPLACE FUNCTION trg_set_unit_price()
RETURNS TRIGGER AS $$
DECLARE
    v_order_time TIMESTAMP;
BEGIN
    -- An explicitly supplied price wins (manual adjustment, back-dated import).
    IF NEW.unit_price IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Price against the ORDER's timestamp, not wall-clock NOW(). Back-filled or
    -- historical rows would otherwise be priced at whatever window the import
    -- happens to run in, which is how lunch/regular prices get mixed up.
    SELECT o.order_time INTO v_order_time
    FROM Orders o
    WHERE o.order_id = NEW.order_id;

    -- LOCALTIMESTAMP, not NOW(): NOW() is timestamptz and get_effective_price()
    -- takes timestamp. timestamptz -> timestamp is only an assignment cast, so
    -- passing NOW() fails function resolution at runtime.
    NEW.unit_price := get_effective_price(NEW.menu_id, COALESCE(v_order_time, LOCALTIMESTAMP));

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_price_before
BEFORE INSERT ON OrderDetails
FOR EACH ROW
EXECUTE FUNCTION trg_set_unit_price();

COMMENT ON TRIGGER trg_set_price_before ON OrderDetails IS 'Automatically sets unit_price using dynamic pricing (lunch vs regular). Ensures price consistency at order time.';
COMMENT ON FUNCTION trg_set_unit_price() IS 'BEFORE INSERT: applies get_effective_price() at the parent order''s order_time to capture the correct price. Leaves an explicitly supplied unit_price untouched.';

-- ============================================================
-- TRIGGER 3: Inventory Deduction + Order Total Recalculation (AFTER INSERT)
-- Deducts stock and recalculates order totals after each line item
--
-- Business Rules:
-- - Stock decreases when order is placed
-- - Order totals recalculate automatically
-- ============================================================
CREATE OR REPLACE FUNCTION trg_after_order_detail()
RETURNS TRIGGER AS $$
BEGIN
    -- Deduct inventory
    UPDATE Inventory
    SET quantity    = quantity - NEW.quantity,
        last_updated = NOW()
    WHERE menu_id = NEW.menu_id;

    -- Recalculate order totals (subtotal + VAT + delivery fee)
    PERFORM finalize_order(NEW.order_id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orderdetail_after
AFTER INSERT ON OrderDetails
FOR EACH ROW
EXECUTE FUNCTION trg_after_order_detail();

COMMENT ON TRIGGER trg_orderdetail_after ON OrderDetails IS 'AFTER INSERT: deducts inventory and recalculates order totals (subtotal, VAT, delivery fee).';
COMMENT ON FUNCTION trg_after_order_detail() IS 'AFTER INSERT trigger: updates Inventory.quantity and calls finalize_order() to recalculate financials.';

-- ============================================================
-- TRIGGER 4: Order Status Validation + Loyalty Points (AFTER UPDATE)
-- Validates status transitions and awards loyalty points
--
-- Business Rules:
-- - "out_for_delivery" only valid for delivery orders
-- - Completed orders earn loyalty points (1 per FULL 50 CZK spent)
-- - Leaving 'completed' (cancellation, refund) takes those points back
-- ============================================================
CREATE OR REPLACE FUNCTION trg_order_status_change()
RETURNS TRIGGER AS $$
DECLARE
    v_points INT;
BEGIN
    -- Validation: out_for_delivery only for delivery orders
    IF NEW.status = 'out_for_delivery' AND NEW.order_type != 'delivery' THEN
        RAISE EXCEPTION 'Status "out_for_delivery" is only valid for delivery orders (current type: %)', NEW.order_type;
    END IF;

    IF NEW.user_id IS NULL THEN
        RETURN NEW;   -- walk-in / phone order with no account to credit
    END IF;

    -- Loyalty points: award when order transitions to completed.
    -- FLOOR, not a cast: "1 point per 50 CZK spent" means full 50 CZK blocks.
    -- NUMERIC::INT rounds half-up, so a 275 CZK order used to earn 6 points for
    -- 5.5 blocks; and GREATEST(1, ...) handed a free point to 0 CZK orders.
    IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' THEN
        v_points := FLOOR(COALESCE(NEW.total, 0) / 50)::INT;
        IF v_points > 0 THEN
            UPDATE Users
            SET loyalty_points = loyalty_points + v_points
            WHERE user_id = NEW.user_id;
        END IF;

    -- Reversal: an order that leaves 'completed' (cancelled, refunded) must not
    -- leave the points it earned behind.
    ELSIF OLD.status = 'completed' AND NEW.status IS DISTINCT FROM 'completed' THEN
        v_points := FLOOR(COALESCE(OLD.total, 0) / 50)::INT;
        IF v_points > 0 THEN
            UPDATE Users
            SET loyalty_points = GREATEST(0, loyalty_points - v_points)
            WHERE user_id = NEW.user_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_status
AFTER UPDATE OF status ON Orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION trg_order_status_change();

COMMENT ON TRIGGER trg_order_status ON Orders IS 'AFTER status UPDATE: validates status transitions and awards loyalty points on completion. Fires only when status actually changes.';
COMMENT ON FUNCTION trg_order_status_change() IS 'AFTER UPDATE trigger: prevents invalid status transitions and awards loyalty points. Uses WHEN clause for efficiency.';

-- ============================================================
-- TRIGGER 5: Reservation Conflict Prevention (BEFORE INSERT/UPDATE)
-- Prevents double-booking the same table at overlapping times
--
-- Business Rule: No table can have overlapping confirmed/pending reservations
-- ============================================================
CREATE OR REPLACE FUNCTION trg_reservation_conflict()
RETURNS TRIGGER AS $$
BEGIN
    -- Only bookings that actually hold the table need checking. Cancelling or
    -- closing out a reservation must never be blocked by a conflict check.
    IF NEW.status NOT IN ('pending', 'confirmed') THEN
        RETURN NEW;
    END IF;

    -- On UPDATE the row being saved is still visible to the SELECT inside
    -- is_table_available(), so it would conflict with itself. Exclude it.
    IF NOT is_table_available(
           NEW.table_id,
           NEW.reservation_time,
           120,
           CASE WHEN TG_OP = 'UPDATE' THEN OLD.reservation_id ELSE NULL END
       ) THEN
        RAISE EXCEPTION 'Reservation conflict: Table % is unavailable at %.',
            NEW.table_id, NEW.reservation_time;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reservation_check
BEFORE INSERT OR UPDATE ON Reservations
FOR EACH ROW
EXECUTE FUNCTION trg_reservation_conflict();

COMMENT ON TRIGGER trg_reservation_check ON Reservations IS 'BEFORE INSERT/UPDATE: prevents overlapping reservations. Uses is_table_available() function.';
COMMENT ON FUNCTION trg_reservation_conflict() IS 'BEFORE trigger: checks table availability before saving reservation. Raises exception on conflict.';

-- ============================================================
-- TRIGGER 6: Audit Trail for Order Changes
-- Logs all status changes for compliance and debugging
--
-- Business Value: Data lineage for tax audits, dispute resolution
-- ============================================================
CREATE TABLE IF NOT EXISTS OrderAuditLog (
    audit_id      SERIAL PRIMARY KEY,
    order_id      INT NOT NULL,
    old_status    VARCHAR(25),
    new_status    VARCHAR(25),
    changed_by    VARCHAR(120),
    changed_at    TIMESTAMP DEFAULT NOW(),
    notes         TEXT
);

COMMENT ON TABLE OrderAuditLog IS 'Audit trail for order status changes. Required for tax compliance and dispute resolution.';

CREATE OR REPLACE FUNCTION trg_order_audit()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO OrderAuditLog (order_id, old_status, new_status, changed_by, notes)
        VALUES (
            NEW.order_id,
            OLD.status,
            NEW.status,
            CURRENT_USER,
            'Status changed from ' || OLD.status || ' to ' || NEW.status
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_audit_log
AFTER UPDATE OF status ON Orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION trg_order_audit();

COMMENT ON TRIGGER trg_order_audit_log ON Orders IS 'AFTER UPDATE: logs status changes to OrderAuditLog for compliance and debugging.';
COMMENT ON FUNCTION trg_order_audit() IS 'Audit trail trigger: records who changed order status and when.';

-- ============================================================
-- TRIGGER 7: Inventory Restock on Cancellation (AFTER UPDATE)
-- Returns the reserved stock when an order is cancelled
--
-- Business Rule: stock is deducted the moment a line item is added
-- (trg_orderdetail_after). Without the mirror-image operation here, every
-- cancellation permanently destroyed inventory: the dishes were never cooked
-- but the stock never came back, so low-stock alerts and reorder planning
-- drifted further from reality with every cancelled order.
-- ============================================================
CREATE OR REPLACE FUNCTION trg_restock_on_cancel()
RETURNS TRIGGER AS $$
BEGIN
    -- Aggregate first: an order may list the same dish on several lines, and
    -- an UPDATE ... FROM would otherwise apply only one of the matching rows.
    UPDATE Inventory i
    SET quantity     = i.quantity + agg.qty,
        last_updated = NOW()
    FROM (
        SELECT menu_id, SUM(quantity) AS qty
        FROM OrderDetails
        WHERE order_id = NEW.order_id
        GROUP BY menu_id
    ) agg
    WHERE i.menu_id = agg.menu_id;

    RETURN NULL;  -- AFTER trigger: return value is ignored
END;
$$ LANGUAGE plpgsql;

-- The WHEN clause makes this fire only on the TRANSITION into 'cancelled', so
-- re-saving an already-cancelled order can never restock the same items twice.
CREATE TRIGGER trg_order_cancel_restock
AFTER UPDATE OF status ON Orders
FOR EACH ROW
WHEN (NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled')
EXECUTE FUNCTION trg_restock_on_cancel();

COMMENT ON TRIGGER trg_order_cancel_restock ON Orders IS 'AFTER status UPDATE to cancelled: returns the order''s quantities to Inventory. Fires only on the transition, so it cannot double-restock.';
COMMENT ON FUNCTION trg_restock_on_cancel() IS 'Reverses the inventory deduction made by trg_after_order_detail() when an order is cancelled.';

-- ============================================================
-- TRIGGER SUMMARY
-- ============================================================
-- Trigger Name              | Table         | Timing    | Event          | Purpose
-- --------------------------|---------------|-----------|----------------|-------------------------------
-- trg_orderdetail_before    | OrderDetails  | BEFORE    | INSERT         | Stock validation
-- trg_set_price_before      | OrderDetails  | BEFORE    | INSERT         | Dynamic pricing
-- trg_orderdetail_after     | OrderDetails  | AFTER     | INSERT         | Inventory deduction + totals
-- trg_order_status          | Orders        | AFTER     | UPDATE(status)  | Status validation + loyalty
-- trg_reservation_check     | Reservations  | BEFORE    | INSERT/UPDATE   | Conflict prevention
-- trg_order_audit_log       | Orders        | AFTER     | UPDATE(status)  | Audit trail
-- trg_order_cancel_restock  | Orders        | AFTER     | UPDATE(status)  | Inventory restock on cancel
--
-- Trigger Execution Order:
-- 1. BEFORE: trg_check_inventory (validate stock)
-- 2. BEFORE: trg_set_unit_price (set price)
-- 3. INSERT OrderDetails row
-- 4. AFTER: trg_after_order_detail (deduct inventory, recalc totals)
-- 5. [Later] Status update triggers trg_order_status + trg_order_audit
-- ============================================================
