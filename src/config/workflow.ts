import type { InvoiceWorkflowStatus } from '../types';

export const workflowSteps: { status: InvoiceWorkflowStatus; label: string }[] = [
  { status: 'UPLOADED', label: 'PDF uploaded' },
  { status: 'SCANNING', label: 'Secure scan' },
  { status: 'EXTRACTED', label: 'Fields extracted' },
  { status: 'VERIFYING', label: 'Buyer ERP check' },
  { status: 'VERIFIED', label: 'Invoice verified' },
  { status: 'RISK_ASSESSED', label: 'Risk assessed' },
  { status: 'FINANCE_ELIGIBLE', label: 'Finance eligible' },
  { status: 'OFFER_ACCEPTED', label: 'Offer accepted' },
  { status: 'FUNDED', label: 'Funds disbursed' },
  { status: 'SETTLED', label: 'Settlement complete' },
];