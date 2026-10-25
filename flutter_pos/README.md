# Synorra POS — Standalone Flutter Application

A standalone, local-first Flutter Point-of-Sale (POS) terminal application for **Synorra**.

## Architecture & Features

### 1. Offline Functionality (Local-First)
- Works completely offline without requiring an active internet connection.
- Uses `shared_preferences` and local JSON storage for instant zero-latency operation.
- Orders, shift punches, restock records, and void requests are written locally and queued in FIFO order (`offline_queue_*`).
- Inventory stock deductions are immediately tracked locally even while offline.

### 2. Robust Data Synchronization
- Continuously monitors network reachability using `connectivity_plus`.
- Automatically executes two-way synchronization whenever connection is restored:
  - **Pull**: Fetches current `menu_items`, `menu_categories`, `inventory_items`, `staff_users`, and promotions from Supabase into local cache.
  - **Push**: Submits offline orders via the exact Supabase atomic RPC (`create_order_atomic`), ensuring inventory and usage logs match server transactions.
  - Pushes offline restocks via `create_restock_atomic`.
  - Pushes offline void requests and shift attendance punches.
- Visual sync badge in the top bar indicates real-time state:
  - 🟢 **Online • Synced**: All local transactions are synced with Supabase.
  - 🟡 **Offline (X queued)**: Offline mode with pending transaction count.
  - 🔵 **Syncing...**: Active synchronization in progress.

### 3. Feature Completeness
- **Payment Methods**:
  - **Cash** (with quick tender preset buttons: ₱500, ₱1,000, ₱2,000, custom tendered keypad, and real-time change calculation).
  - **GCash** (e-wallet QR/ref reference integration).
  - **Maya** (e-wallet integration).
- **Cart **:
  - Hot / Iced drink style selector.
  - Add-ons with quantity increments and price adjustments.
  - Real-time line item total, subtotal, and total due calculation.
- **Order Actions**:
  - **Proceed Order**: 
  - **Void Order**: Filter active orders by ticket number or item, require manager credentials, restore inventory stock, and update Supabase.
  - **Print / Reprint**: Full ESC/POS thermal  formatting with ticket number, barista, itemized , and store branding.
- **Sidebar Menus**:
  - **POS Terminal**: Main cash register and catalog interface.
  - **Stock Inventory**: Live ingredient stock levels, low-stock warnings, and unit costs.
  - **Restock Management**: Record inventory deliveries and purchase units.
  - **Reprint / Recent Tickets**: Access and reprint past transactions.
  - **Shift Clock In / Out**: Record barista shift attendance directly to store logs.

## Supabase Database Connection

The app connects to the existing Supabase project without altering any schema:
- Tables: `pos_state`, `staff_users`, `menu_categories`, `menu_items`, `inventory_items`, `orders`, `order_items`, `usage_logs`, `restocks`, `void_requests`, `login_activity`.
- Atomic RPCs: `create_order_atomic`, `void_order_atomic`, `create_restock_atomic`, `delete_order_atomic`.

### Setting credentials:
You can provide credentials at build or runtime:
```bash
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

## Running the App

```bash
cd flutter_pos
flutter pub get
flutter run
```
