# CapitalBridge

AI-powered invoice-to-cash and purchase-order financing prototype for SMEs.

CapitalBridge helps an SME turn a verified unpaid invoice or confirmed purchase order into short-term working capital. The current repository contains an Expo React Native mobile prototype plus a cloned AI verification sidecar.

## Current App

- Expo React Native frontend.
- Expo web support through React Native Web.
- Supabase Auth sign-up/sign-in gate before workspace access.
- Supabase/PostgreSQL-backed invoice, offer, risk, notification, audit, and transaction records.
- Desktop banking-style shell with top bar, sidebar, and restrained glass panels.
- Role switcher for SME, Buyer, Financier, and Admin views.
- Backend-owned invoice lifecycle from upload to settlement via Supabase RPCs.
- Explainable risk factors with a derived trust score.
- Partial funding selection and transparent fee display.
- Invoice Check mapping for extraction, ERP, duplicate, mismatch, and fraud concepts.
- Audit trail for critical workflow events.

## Architecture Notes

- The old `stage`-driven UI model has been removed.
- The frontend now displays a `WorkflowState` snapshot and sends guarded commands.
- Production state lives in Supabase/PostgreSQL and advances through backend RPC/API calls.
- See `docs/secure-platform-architecture.md` and `supabase/migrations/001_initial_schema.sql`.

## Run Frontend

```powershell
npm install
npm run start
```

For web:

```powershell
npm run web
```

Metro web runs at:

```text
http://localhost:8081
```

## Run AI Sidecar

The AI sidecar is cloned into:

```text
InvoiceCheck/
```

It exposes a FastAPI service for AP workflow tasks such as invoice extraction, ERP schema drift, duplicate detection, negotiation, and lookalike-domain fraud checks.

```powershell
npm run ai:env
```

AI API docs:

```text
http://localhost:7860/docs
```

## Verify

```powershell
npm run typecheck
```

## Prototype Boundary

This is a hackathon prototype. Mock ERP, mock banking, synthetic data, and simulated settlement must stay clearly labelled. Final authorization, tenant isolation, financing decisions, and money movement should live in the backend layer, not inside the mobile client.
"# CapitalBridge" 
