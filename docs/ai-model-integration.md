# CapitalBridge AI Model Integration

## Service

CapitalBridge will use the cloned `InvoiceCheck` project as a prototype AI verification and workflow-reasoning service.

Local source:

```text
InvoiceCheck/
```

REST base URL when running locally:

```text
http://localhost:7860
```

Live hosted reference:

```text
https://huggingface.co/spaces/decent-cow26/invoice-env
```

## Boundary

The Invoice Check should run as a sidecar/backend service. The React Native app should not make final financing or authorization decisions directly from AI output.

Recommended flow:

```text
Expo app -> CapitalBridge API -> transaction evidence services -> CapitalBridge risk/financing engine -> Expo app
```

Supporting automation can provide:

- Extracted invoice fields from unstructured invoice text.
- ERP query workflow evidence.
- Schema drift recovery signals.
- Duplicate invoice flags.
- Vendor negotiation/correction workflow signals.
- Lookalike-domain and bank-account anomaly flags.

CapitalBridge must still own:

- Tenant isolation and RBAC.
- KYC and organisation permissions.
- Final human approval.
- Financing limits, fees, and settlement math.
- Audit logging.
- Banking and disbursement actions.

## Task Mapping

| AP environment task | CapitalBridge use |
| --- | --- |
| `easy` | Baseline invoice extraction and PO match |
| `medium` | Price or line-item mismatch detection |
| `hard` | ERP schema drift recovery plus duplicate invoice detection |
| `expert_negotiation` | Vendor correction workflow before approval |
| `expert_fraud` | Lookalike sender domain and bank-account anomaly screening |

## Local Run

Install the Python requirements inside the cloned service directory:

```powershell
cd InvoiceCheck
py -3.12 -m venv .venv
.venv\Scripts\python -m pip install fastapi==0.115.12 uvicorn==0.32.0 pydantic==2.5.3 requests==2.31.0 "python-dotenv>=1.0.0"
```

Then from the CapitalBridge project root:

```powershell
npm run ai:env
```

Expected endpoints:

```text
GET  /health
GET  /tasks
POST /reset?task_name=expert_fraud
POST /step?session_id=<uuid>
GET  /state?session_id=<uuid>
```

## Prototype Status

The Expo app treats Invoice Check as supporting automation and maps its tasks into CapitalBridge verification/risk concepts. Direct live HTTP calls are intentionally left for the backend/API layer so the app does not bypass financial controls.
