# Golden Dragon Prague - Entity Relationship Description

## Overview

This document describes the entity-relationship model for the Golden Dragon Prague database. The model consists of 13 tables with clear relationships and business rules.

---

## Entities

### 1. Users
**Description**: Customer accounts with loyalty program integration

**Primary Key**: user_id (SERIAL)

**Key Attributes**:
- `username`: Unique login identifier
- `full_name`: Display name
- `email`: Contact email (unique)
- `loyalty_points`: Accumulated via trigger on order completion
- `role`: customer, staff, or vip

**Relationships**:
- One user → Many orders
- One user → Many reservations

### 2. Employees
**Description**: Restaurant staff

**Primary Key**: employee_id (SERIAL)

**Key Attributes**:
- `full_name`: Staff member name
- `role`: chef, waiter, manager, delivery_driver, owner
- `is_active`: Soft delete flag

**Relationships**:
- One employee → Many orders (as handler)
- One employee → One user (if also a system user)

### 3. MenuCategories
**Description**: Menu organization hierarchy

**Primary Key**: category_id (SERIAL)

**Key Attributes**:
- `name_cz`: Czech name for kitchen staff
- `name_en`: English name for POS/tourists
- `display_order`: UI ordering

**Relationships**:
- One category → Many menus

### 4. Menus
**Description**: Individual dishes

**Primary Key**: menu_id (SERIAL)

**Key Attributes**:
- `name_cz`, `name_en`: Bilingual names
- `price_regular`, `price_lunch`: Dual pricing
- `spice_level`: 0-5 scale
- `estimated_prep_minutes`: Kitchen SLA

**Relationships**:
- One menu → Many order details
- One menu → One inventory record
- One menu → Many allergens (via MenuAllergens)

### 5. Allergens
**Description**: EU-mandated allergen declarations

**Primary Key**: allergen_id (SERIAL)

**Key Attributes**:
- `code`: EU allergen number (1-14)
- `name_en`, `name_cz`: Bilingual names

**Relationships**:
- One allergen → Many menus (via MenuAllergens)

### 6. MenuAllergens
**Description**: Junction table for menu-allergen many-to-many

**Primary Key**: (menu_id, allergen_id)

**Relationships**:
- Many-to-many: Menus ↔ Allergens

### 7. Inventory
**Description**: Current stock levels

**Primary Key**: inventory_id (SERIAL)

**Key Attributes**:
- `quantity`: Current stock (>= 0)
- `last_updated`: Auto-updated by trigger

**Relationships**:
- One-to-one with Menus (UNIQUE constraint)

### 8. RestaurantTables
**Description**: Physical tables in the restaurant

**Primary Key**: table_id (SERIAL)

**Key Attributes**:
- `table_number`: Display name (T01, VIP1, etc.)
- `capacity`: Seating capacity
- `zone`: main, window, private, terrace

**Relationships**:
- One table → Many orders (for dine-in)
- One table → Many reservations

### 9. Reservations
**Description**: Table bookings

**Primary Key**: reservation_id (SERIAL)

**Key Attributes**:
- `reservation_time`: Booking timestamp
- `party_size`: Number of guests
- `status`: pending, confirmed, cancelled, no_show

**Relationships**:
- Many reservations → One user
- Many reservations → One table

### 10. Orders
**Description**: Central business entity - all revenue flows through here

**Primary Key**: order_id (SERIAL)

**Key Attributes**:
- `order_type`: dine_in, takeaway, delivery, event
- `status`: new → confirmed → preparing → ready → served/completed/cancelled
- `source`: walk-in, phone, website, wolt, bolt
- `special_requests`: JSONB (diet, allergies, notes)
- `delivery_address`: JSONB (street, city, postal, note)
- Financial: subtotal, vat_amount, total, delivery_fee, discount_amount

**Relationships**:
- Many orders → One user
- Many orders → One employee (handler)
- Many orders → One table (for dine-in)
- One order → Many order details
- One order → One event (optional)
- One order → Many payments

### 11. OrderDetails
**Description**: Order line items

**Primary Key**: order_detail_id (SERIAL)

**Key Attributes**:
- `quantity`: Items ordered (> 0)
- `unit_price`: Price at order time
- `line_note`: Per-item special instructions
- `spice_override`: Customer customization

**Relationships**:
- Many details → One order
- Many details → One menu

### 12. Payments
**Description**: Payment records (supports split payments)

**Primary Key**: payment_id (SERIAL)

**Key Attributes**:
- `method`: cash, card, qr, voucher, online
- `amount`: Payment amount
- `reference`: External transaction ID

**Relationships**:
- Many payments → One order

### 13. Events
**Description**: Private events and large catering orders

**Primary Key**: event_id (SERIAL)

**Key Attributes**:
- `event_date`: When the event occurs
- `location`: Usually VIP room name or external address
- `expected_guests`: Headcount for kitchen planning

**Relationships**:
- One event → One order (for billing)

---

## Relationship Cardinality

```
Users (1) ────────────────────────────────────────────────── (N) Orders
    │                                                            │
    │ (1)                                                       │ (N)
    │                                                            │
    └───────────────────────────────── (N) Reservations          │
                                                                 │
                                                                 ▼
                                                          OrderDetails
                                                                 │
                                          (N) ─────────────────┘
                                          │                    │ (1)
                                          │                    │
                                          ▼                    ▼
                                      Menus ←──────────────────┘
                                          │
                                          │ (N)
                                          │
                                          ▼
                                     MenuAllergens ←── (1) Allergens

RestaurantTables (1) <──────────── (N) Orders
                       <──────────── (N) Reservations

Employees (1) <───────────── (N) Orders

Events (1) <────────────── (N) Orders
```

---

## Normalization

### 3NF Compliance

| Table | 1NF | 2NF | 3NF | Notes |
|-------|-----|-----|-----|-------|
| Users | Yes | Yes | Yes | No partial/transitive deps |
| Menus | Yes | Yes | Yes | Category name via FK |
| OrderDetails | Yes | Yes | Yes | Price denormalized for history |
| Orders | Yes | Yes | Yes | Financials computed by trigger |
| Others | Yes | Yes | Yes | All compliant |

### Denormalization Justifications

1. **OrderDetails.unit_price**: Captures price at order time for historical accuracy
2. **Orders.subtotal/vat_amount/total**: Pre-computed for query performance
3. **dim_customer in star schema**: SCD Type 2 with validity dates

---

## Constraints Summary

| Type | Tables | Purpose |
|------|--------|---------|
| PRIMARY KEY | All 13 tables | Unique row identification |
| FOREIGN KEY | Orders, OrderDetails, etc. | Referential integrity |
| UNIQUE | Users.email, Menus.menu_id (in Inventory), etc. | Business rule enforcement |
| CHECK | Orders.status, Users.role, etc. | Enum validation |
| NOT NULL | Critical fields (user_id, order_time, etc.) | Required data enforcement |

---

## Index Coverage

All foreign keys and frequently filtered columns are indexed. See `02_indexes.sql` for full list.

---

*This ERD documentation provides a complete reference for understanding the data model, useful for both technical discussions and business stakeholder communication.*
