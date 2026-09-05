# Secure Platform Architecture

This document turns the revised product prompt into build rails for CapitalBridge. Phase 1 is the app shell and UI system; AI extraction, financing decisions, and money movement remain backend concerns.

## 1. UI Architecture

The app should present a banking-style operating console:

```text
Top bar: logo, search, alerts, active account
Sidebar: role-aware navigation
Main surface: current screen and backend-sourced workflow state
Mobile: same screens with horizontal navigation
```

The frontend must never be the authority for invoice or financing state. It renders a backend snapshot and sends commands such as `START_SCAN`, `RUN_RISK`, or `SETTLE_INVOICE`. The API validates the current database status, writes the next status, and appends audit events.

## 2. Screen List

| Screen | Primary user | Purpose |
| --- | --- | --- |
| Dashboard | SME, Buyer, Financier, Admin | Working-capital position, recent invoices, and next workflow action |
| Invoices | All roles | Canonical invoice record, PO, verification status, and document fingerprints |
| Upload | SME, Admin | Secure PDF intake and pre-extraction checks |
| Funding | SME, Financier, Admin | Advance amount, offers, acceptance lock, disbursement, and settlement |
| Risk | All roles | Verification timeline, ERP evidence, duplicate checks, fraud flags, and score |
| Transactions | SME, Financier, Admin | Ledger-style funding and settlement events |
| Notifications | All roles | Role-aware action and status notifications |
| Audit | Financier, Admin | Append-oriented critical event trail |
| Settings | All roles | Organisation, integration, security, and privacy configuration |

## 3. Component Hierarchy

```text
App
  AppLayout
    top bar
    sidebar or mobile nav
    active screen
  DashboardScreen
    MetricCard
    GlassCard
    StatusChip
  InvoicesScreen
    InfoRow
    CheckRow
    StatusChip
  UploadInvoiceScreen
    secure intake checks
  FundingScreen
    OfferCard
    MiniStat
  RiskVerificationScreen
    ScoreRow
    AI task mapping
  TransactionsScreen
  NotificationsScreen
  AuditScreen
  SettingsScreen
```

## 4. Supabase ERD

```text
auth.users
  -> profiles
  -> organisation_members -> organisations -> business_profiles

organisations
  -> buyers
  -> suppliers
  -> purchase_orders
  -> invoices
       -> invoice_files
       -> invoice_extracted_fields
       -> invoice_fingerprints
       -> verification_requests -> verification_results
       -> fraud_checks -> fraud_alerts
       -> risk_assessments -> risk_factors
       -> financing_requests -> financing_offers -> financing_agreements
       -> funding_transactions
       -> settlements -> settlement_allocations
       -> invoice_status_history
       -> audit_logs

organisations
  -> integrations -> integration_events
  -> notifications
  -> consents
  -> data_access_logs
  -> idempotency_keys
```

## 5. Workflow State

The canonical invoice status chain is:

```text
UPLOADED
SCANNING
EXTRACTED
VERIFYING
VERIFIED
RISK_ASSESSED
FINANCE_ELIGIBLE
OFFER_ACCEPTED
FUNDED
SETTLED
```

The backend should expose command endpoints or RPC functions, not direct client updates to `invoices.status`. Each command checks the expected current status, advances by exactly one valid step, writes `invoice_status_history`, and writes `audit_logs`.

## 6. RLS Design

Every business table carries `organisation_id`. Users only see rows for organisations where they have an active membership. Admin, finance, and operations roles may create or update operational records. Audit logs, status history, extracted fields, and risk outputs are append-oriented.

The Supabase service role may run system jobs, but the Expo app should use normal authenticated sessions and never receive service credentials.

## 7. Secure PDF Pipeline

1. Upload into a private Supabase Storage bucket under `{organisation_id}/{invoice_id}/original.pdf`.
2. Validate declared MIME type, magic bytes, extension, file size, and page count.
3. Generate SHA-256 and a normalized invoice fingerprint before extraction.
4. Run malware scanning in an isolated worker.
5. Extract fields into `invoice_extracted_fields` with confidence and model version.
6. Match against supplier, buyer, PO, and ERP evidence.
7. Run duplicate and fraud checks before any finance eligibility change.
8. Store only immutable file paths, hashes, and extraction evidence in the audit trail.

## 8. Duplicate Detection

Use layered matching:

| Layer | Signal |
| --- | --- |
| Exact file duplicate | SHA-256 file hash already exists |
| Normalized invoice duplicate | Supplier tax number, invoice number, amount, due date |
| Near duplicate | Similar perceptual hash or OCR text fingerprint |
| Financing duplicate | Same invoice already funded or has active agreement |
| ERP duplicate | Buyer ERP marks invoice or PO as paid, cancelled, disputed, or already approved |

## 9. Enterprise AP Reuse

Reuse the linked Invoice Check for concepts and backend-side experiments:

| Concept | CapitalBridge use |
| --- | --- |
| ERP querying | Buyer PO and invoice confirmation |
| Schema drift | Adapter resilience when ERP fields change |
| Field extraction | Invoice amount, dates, parties, line items |
| PO matching | Amount and line-item mismatch flags |
| Duplicate matching | Repeat invoice and repeat funding prevention |
| Fraud checks | Lookalike supplier domains and changed bank details |

Do not embed the RL environment directly in the Expo app. Keep it behind the API so financial controls remain enforceable.

## 10. NIST Mapping

| NIST CSF function | CapitalBridge controls |
| --- | --- |
| Identify | Asset inventory, supplier/buyer records, data classification |
| Protect | RLS, RBAC, private storage, encryption, least privilege |
| Detect | Fraud checks, duplicate alerts, anomaly scoring, audit log review |
| Respond | Dispute workflow, alert resolution, admin investigation notes |
| Recover | Immutable history, status replay, settlement reconciliation |

## 11. POPIA Mapping

| POPIA concern | Design response |
| --- | --- |
| Lawful processing | Consent records and financing purpose limitation |
| Minimality | Store only fields required for verification and financing |
| Security safeguards | Private storage, RLS, encryption, audit logs |
| Data subject access | Data access logs and organisation-scoped exports |
| Retention | Retention policy by invoice, agreement, and legal requirement |
| Cross-border transfer | Track provider region and subprocessors in integrations |

## 12. Attack And Loophole Analysis

| Risk | Control |
| --- | --- |
| Frontend state manipulation | Backend-only status transitions with expected-state checks |
| Refresh or multi-device race | Idempotency keys and row-level database transactions |
| Duplicate invoice financing | File hash, normalized fingerprint, ERP status, and active agreement checks |
| Fake buyer approval | Buyer-side authenticated membership and signed verification result |
| Supplier bank-detail fraud | Changed account detection and manual review before funding |
| Lookalike sender domain | Domain similarity check and buyer confirmation requirement |
| Direct storage access | Private bucket plus path-based RLS policies |
| AI hallucinated approval | AI output remains evidence only, never final authority |

## 13. Implementation Roadmap

| Phase | Scope |
| --- | --- |
| 1 | Desktop/mobile UI system, role navigation, backend-shaped workflow state |
| 2 | Supabase auth, organisation membership, RLS, schema migrations |
| 3 | Secure upload pipeline and private storage policies |
| 4 | Invoice extraction and ERP/PO verification service |
| 5 | Duplicate, mismatch, fraud, and risk scoring layer |
| 6 | Financing offers, acceptance lock, agreement generation |
| 7 | Funding provider sandbox, settlement allocation, ledger reconciliation |
| 8 | Admin review, disputes, monitoring, privacy export, retention jobs |
