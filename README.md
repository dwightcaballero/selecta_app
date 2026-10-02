# Selecta Ops

A Flutter mobile application for **Selecta field sales operations**, serving two primary roles:

- **Salesman** — Manage daily deliveries, journey plans (PJP), scanning, returns, credits, and tasks
- **Dealer** — Manage inventory, purchase orders, Hapi Store coverage, and distribution KPIs

---

## Features

### Operations
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

---

## Version

Current: 1.0.0+25
