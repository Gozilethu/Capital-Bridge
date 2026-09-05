import { workflowSteps } from '../config/workflow';
import type { InvoiceWorkflowStatus, Tone, WorkflowCommand, WorkflowState } from '../types';

export const statusOrder: InvoiceWorkflowStatus[] = workflowSteps.map((step) => step.status);

export const workflowTransitions: Record<
  WorkflowCommand,
  {
    expected: InvoiceWorkflowStatus;
    next: InvoiceWorkflowStatus;
    code: string;
    detail: string;
  }
> = {
  START_SCAN: {
    expected: 'UPLOADED',
    next: 'SCANNING',
    code: 'PDF_SECURITY_SCAN_STARTED',
    detail: 'File type, MIME, magic bytes, hash, and malware checks started',
  },
  COMPLETE_EXTRACTION: {
    expected: 'SCANNING',
    next: 'EXTRACTED',
    code: 'INVOICE_EXTRACTED',
    detail: 'Invoice fields extracted into reviewable values',
  },
  REQUEST_VERIFICATION: {
    expected: 'EXTRACTED',
    next: 'VERIFYING',
    code: 'ERP_VERIFICATION_REQUESTED',
    detail: 'Buyer ERP verification requested for invoice and purchase order',
  },
  COMPLETE_VERIFICATION: {
    expected: 'VERIFYING',
    next: 'VERIFIED',
    code: 'ERP_VERIFICATION_COMPLETED',
    detail: 'Supplier, buyer, amount, PO, and unpaid status matched',
  },
  RUN_RISK: {
    expected: 'VERIFIED',
    next: 'RISK_ASSESSED',
    code: 'RISK_ASSESSMENT_COMPLETED',
    detail: 'Explainable invoice risk assessment completed',
  },
  MARK_ELIGIBLE: {
    expected: 'RISK_ASSESSED',
    next: 'FINANCE_ELIGIBLE',
    code: 'FINANCING_REQUESTED',
    detail: 'Maximum advance and financing request created',
  },
  DISBURSE_FUNDS: {
    expected: 'OFFER_ACCEPTED',
    next: 'FUNDED',
    code: 'FUNDS_DISBURSED',
    detail: 'Funding disbursement recorded by banking provider',
  },
  SETTLE_INVOICE: {
    expected: 'FUNDED',
    next: 'SETTLED',
    code: 'SETTLEMENT_PROCESSED',
    detail: 'Principal, fee, and SME remainder reconciled',
  },
};

export function statusIndex(status: InvoiceWorkflowStatus) {
  return statusOrder.indexOf(status);
}

export function hasReached(current: InvoiceWorkflowStatus, target: InvoiceWorkflowStatus) {
  return statusIndex(current) >= statusIndex(target);
}

export function statusTone(status: InvoiceWorkflowStatus): Tone {
  if (status === 'SETTLED' || status === 'FUNDED' || status === 'FINANCE_ELIGIBLE') {
    return 'green';
  }

  if (status === 'VERIFYING' || status === 'RISK_ASSESSED' || status === 'OFFER_ACCEPTED') {
    return 'blue';
  }

  if (status === 'SCANNING' || status === 'EXTRACTED' || status === 'VERIFIED') {
    return 'amber';
  }

  return 'neutral';
}

export function statusLabel(status: InvoiceWorkflowStatus) {
  return status.replace(/_/g, ' ');
}

export function nextCommandForState(state: WorkflowState): WorkflowCommand | null {
  const command = (Object.keys(workflowTransitions) as WorkflowCommand[]).find(
    (item) => workflowTransitions[item].expected === state.invoice.status,
  );

  return command ?? null;
}

export function commandLabel(command: WorkflowCommand | null) {
  if (command === 'START_SCAN') {
    return 'Start secure scan';
  }

  if (command === 'COMPLETE_EXTRACTION') {
    return 'Complete extraction';
  }

  if (command === 'REQUEST_VERIFICATION') {
    return 'Request ERP verification';
  }

  if (command === 'COMPLETE_VERIFICATION') {
    return 'Confirm verification';
  }

  if (command === 'RUN_RISK') {
    return 'Run risk assessment';
  }

  if (command === 'MARK_ELIGIBLE') {
    return 'Mark finance eligible';
  }

  if (command === 'DISBURSE_FUNDS') {
    return 'Record disbursement';
  }

  if (command === 'SETTLE_INVOICE') {
    return 'Record settlement';
  }

  return 'No action available';
}

export function availableWorkingCapitalCents(state: WorkflowState) {
  if (hasReached(state.invoice.status, 'FINANCE_ELIGIBLE') && !hasReached(state.invoice.status, 'FUNDED')) {
    return state.invoice.maxAdvanceCents;
  }

  if (hasReached(state.invoice.status, 'FUNDED')) {
    return state.advanceCents;
  }

  return 0;
}

export function upcomingSettlementCents(state: WorkflowState, feeCents: number) {
  if (!hasReached(state.invoice.status, 'OFFER_ACCEPTED')) {
    return 0;
  }

  return state.advanceCents + feeCents;
}