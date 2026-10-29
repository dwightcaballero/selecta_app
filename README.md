# Selecta Ops

A Flutter mobile application for **Selecta field sales operations**, serving two primary roles:

- **Salesman** — Manage daily deliveries, journey plans (PJP), scanning, returns, credits, and tasks
- **Dealer** — Manage inventory, purchase orders, Hapi Store coverage, and distribution KPIs

---

## Features

### Operations
- 🏪 **Hapi Store Self-Ordering** — Dedicated store portal for Hapi Stores to order directly from their assigned dealer, view available products with stock-safety badges, track order lifecycle progress, and reorder past deliveries with 1-click
- 📋 **Dealer Store Orders Inbox** — Dealer review screen with line-by-line quantity adjustments, mandatory delivery date assignment, real-time price synchronization, and automated pre-sell delivery doc creation with inventory reservations
- 📦 **Book Order / Picklist / Delivery** — Full order-to-delivery workflow
- 🔄 **Returns & Bad Orders** — Capture and track returned goods
- 💳 **Credit Management** — Track unpaid accounts per store
- 🗺️ **Pre-Journey Plan (PJP)** — Daily route scheduling and store visit tracking
- 📷 **Proof of Visit / Placement** — Photo capture for store compliance
- 🔍 **Barcode Scanning** — Product scanning via `mobile_scanner`
- 🖨️ **Thermal Printing** — Bluetooth receipt printing via `print_bluetooth_thermal`

### KPI & Analytics
- 📊 **Dashboard KPIs** — Sales, Throughput, Buying Stores, Placement, Scanning, Expansion
- 📈 **MerchBlitz Tracking** — Campaign survey tracking per store
- 💰 **Expense Tracking** — Daily field expense logging

### AI & Smart Features
- 🤖 **Ask Sedy (Gemini AI)** — In-app AI assistant for operational insights
- 📄 **Invoice AI Scanning** — AI-powered invoice-to-PO reconciliation using Gemini Vision

### Settings & Admin
- 🔐 **Role-Based Access** — Dealer and Salesman views with separate permissions
- ⚙️ **Super Admin Panel** — AI settings, role switching, error log management
- 🔔 **Error Logging** — Persistent crash logs with Firebase Firestore upload

---

## Architecture

```
lib/
├── data/           # Constants, helpers, notifiers, global variables
├── models/         # Firestore data models (Configuration, Delivery, Users, ...)
├── dto/            # Data Transfer Objects for UI binding
├── services/       # Firebase/API access layer (one service per domain)
├── controllers/    # Business logic layer (one controller per feature)
└── views/
    ├── pages/
    │   ├── dashboard/  # Main operational pages
    │   ├── sidebar/    # Settings, inventory, admin pages
    │   └── others/     # Auth, login, register, profile
    └── widgets/        # Shared reusable widgets
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) |
| Auth | Firebase Authentication |
| Database | Cloud Firestore + Firebase Realtime Database |
| Storage | Firebase Storage |
| AI | Google Gemini (google_generative_ai) |
| Charts | fl_chart |
| Maps | flutter_map + geolocator |
| Scanning | mobile_scanner |
| Printing | print_bluetooth_thermal |
| State | ValueNotifier + SharedPreferences |

---

## Getting Started

### Prerequisites
- Flutter SDK ^3.12.1
- Firebase project configured (see firebase_options.dart)
- Android SDK / Xcode (for iOS builds)

### Setup

```bash
flutter pub get
flutter run
```

### First-time Admin Setup
After first launch, tap the welcome banner **5 times** to access the Super Admin panel.
Set your admin password immediately from the **Admin Password** card.

## Firebase Cost Optimization & Zero-Tier Quota Guards

To guarantee the app operates completely within the Firebase Blaze free tier limits:

1. **Storage Security & Caching**:
   - `storage.rules` enforce authenticated user ownership on uploads, `< 2MB` image size, and `image/*` MIME type checks.
   - All uploaded images specify `cacheControl: 'public, max-age=31536000'`.
   - Update APK checks are cached for 6 hours in `SharedPreferences` to prevent redundant Storage metadata requests.
2. **Catalog Caching & Version Signatures**:
   - `catalog_meta/version` is checked on launch (1 read) rather than re-reading all products (~400 reads).
   - In-memory `ProductCatalogCache` provides 5-minute TTL caching across inventory, picklists, and reporting workflows.
3. **Bounded Realtime Streams**:
   - All high-frequency streams (`tasks`, `scout_routes`, `proof_of_visit`, `badorder_batch`, `error_logs`) use `.limit(...)` and server-side date range constraints.
   - Store order and inventory queries filter on `isInventoryReplenished: false` to avoid re-billing historical records.
4. **GPS Tracking Efficiency**:
   - Scout tracking records points at a 20m distance threshold and flushes incrementally using `FieldValue.arrayUnion()`.
   - Hard cap of 500 GPS points per route session prevents oversized document downloads.
5. **Automated Regression Guard**:
   ```bash
   ./scripts/cost_regression_check.sh
   ```
   Run this script in CI or before committing to verify no unbounded `.snapshots()` or raw collection reads have been introduced.

---

## Version

Current: 1.0.0+56

