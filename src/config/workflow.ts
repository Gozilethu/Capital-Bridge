import type { InvoiceWorkflowStatus } from '../types';

export const workflowSteps: { status: InvoiceWorkflowStatus; label: string }[] = [
  { status: 'UPLOADED', label: 'Receivable captured' },
  { status: 'SCANNING', label: 'Document evidence checked' },
  { status: 'EXTRACTED', label: 'Invoice fields captured' },
  { status: 'VERIFYING', label: 'Buyer / ERP verification' },
  { status: 'VERIFIED', label: 'PO and delivery monitoring' },
  { status: 'RISK_ASSESSED', label: 'Transaction risk assessed' },
  { status: 'FINANCE_ELIGIBLE', label: 'Financier market opened' },
  { status: 'OFFER_ACCEPTED', label: 'Offer locked' },
  { status: 'FUNDED', label: 'Funds disbursed' },
  { status: 'SETTLED', label: 'Payment settled' },
];