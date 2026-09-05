# Frontend Structure

The Expo UI is organized under `src/` so each concern has a clear home.

```text
App.tsx                 Root Expo shell and backend-shaped state snapshot
src/
  components/           Reusable UI building blocks
  data/                 Supabase-backed workspace state, offers, risk factors, and transaction evidence
  screens/              One screen per product area
  theme/                Shared React Native styles
  utils/                Money, risk, and workflow helper functions
```

## Screens

| Screen | Purpose |
| --- | --- |
| `DashboardScreen` | Working-capital summary, recent invoices, next workflow command, risk snapshot |
| `InvoicesScreen` | Canonical invoice record, PO, verification fields, document fingerprints |
| `UploadInvoiceScreen` | Secure PDF intake, hash, MIME, malware, and extraction checks |
| `FundingScreen` | Advance amount, offer comparison, acceptance lock, disbursement and settlement |
| `RiskVerificationScreen` | Buyer/ERP evidence, PO and delivery monitoring, duplicate prevention, and transaction risk |
| `TransactionsScreen` | Ledger-style funding and settlement events |
| `NotificationsScreen` | Role-aware status and action notifications |
| `AuditScreen` | Append-oriented event trail and risk-rule weights |
| `SettingsScreen` | Organisation, integration, security, and privacy settings |

## Components

Reusable components include the desktop/mobile `AppLayout`, restrained `GlassCard` panels, `MetricCard`, badges, status chips, info rows, check rows, metrics, workflow steps, offer cards, and bottom navigation for smaller screens.

## Workflow State

The old local `stage` model has been removed. The app now uses a backend-shaped `WorkflowState` snapshot with a transaction evidence chain:

```text
UPLOADED -> SCANNING -> EXTRACTED -> VERIFYING -> VERIFIED -> RISK_ASSESSED -> FINANCE_ELIGIBLE -> OFFER_ACCEPTED -> FUNDED -> SETTLED
```

For the prototype, `src/utils/workflow.ts` simulates server-side command handling. In production, the same commands should call Supabase/API functions that validate the current status and write audit events in the database.

## Financial UI Rules

- Currency values are represented in integer cents in the frontend demo.
- Fees are calculated through `src/utils/money.ts`.
- Risk score display is derived from visible risk factors through `src/utils/risk.ts`.
- The mobile app presents evidence and demo state only. Production-grade authorization and financial decisions belong in the backend.
