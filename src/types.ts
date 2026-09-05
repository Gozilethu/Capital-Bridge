export type Role = 'SME' | 'Buyer' | 'Financier' | 'Admin';

export type Tab =
  | 'Dashboard'
  | 'Invoices'
  | 'Upload'
  | 'Funding'
  | 'Risk'
  | 'Transactions'
  | 'Notifications'
  | 'Audit'
  | 'Settings';

export type Tone = 'blue' | 'green' | 'amber' | 'red' | 'neutral' | 'slate';

export type InvoiceWorkflowStatus =
  | 'UPLOADED'
  | 'SCANNING'
  | 'EXTRACTED'
  | 'VERIFYING'
  | 'VERIFIED'
  | 'RISK_ASSESSED'
  | 'FINANCE_ELIGIBLE'
  | 'OFFER_ACCEPTED'
  | 'FUNDED'
  | 'SETTLED';

export type VerificationStatus = 'UNVERIFIED' | 'PENDING' | 'VERIFIED' | 'PARTIALLY_VERIFIED' | 'FAILED' | 'DISPUTED';

export type FinancingStatus = 'NOT_FINANCED' | 'ELIGIBLE' | 'OFFER_ACCEPTED' | 'ACTIVE' | 'SETTLED';

export type WorkflowCommand =
  | 'START_SCAN'
  | 'COMPLETE_EXTRACTION'
  | 'REQUEST_VERIFICATION'
  | 'COMPLETE_VERIFICATION'
  | 'RUN_RISK'
  | 'MARK_ELIGIBLE'
  | 'DISBURSE_FUNDS'
  | 'SETTLE_INVOICE';

export type Offer = {
  id: string;
  name: string;
  partner: string;
  feeBps: number;
  termDays: number;
  speed: string;
  recommended?: boolean;
  status?: string;
};

export type RiskFactor = {
  label: string;
  earned: number;
  possible: number;
  tone: Tone;
  kind: 'positive' | 'attention';
};

export type RuleWeight = {
  label: string;
  value: number;
};

export type AiTask = {
  name: string;
  difficulty: string;
  mapsTo: string;
  tone: Tone;
};

export type ApEnvironment = {
  name: string;
  source: string;
  localUrl: string;
  liveUrl: string;
};

export type NavigationItem = {
  tab: Tab;
  label: string;
  roles: Role[];
};

export type InvoiceRecord = {
  id: string;
  number: string;
  purchaseOrder: string;
  supplier: string;
  buyer: string;
  industry: string;
  amountCents: number;
  maxAdvanceCents: number;
  requestedCents: number;
  outstandingCents: number;
  dueDays: number;
  status: InvoiceWorkflowStatus;
  verificationStatus: VerificationStatus;
  financingStatus: FinancingStatus;
  fileHash: string;
  identityHash: string;
  fileName: string;
  issueDate: string | null;
  dueDate: string | null;
};

export type UploadSecurityCheck = {
  label: string;
  detail: string;
  status: 'complete' | 'active' | 'pending';
};

export type AuditEvent = {
  code: string;
  actor: string;
  detail: string;
  time: string;
};

export type NotificationItem = {
  id: string;
  title: string;
  detail: string;
  tone: Tone;
};

export type TransactionItem = {
  id: string;
  label: string;
  amountCents: number;
  status: string;
  date: string;
};

export type TransactionEventItem = {
  id: string;
  phase: string;
  label: string;
  detail: string;
  status: string;
  time: string;
  tone: Tone;
};

export type SubscriptionPlan = {
  id: string;
  code: string;
  name: string;
  description: string;
  monthlyPriceCents: number;
  currency: string;
  scanLimit: number;
  benefits: string[];
};

export type PlanStatus = {
  planId: string;
  planCode: string;
  planName: string;
  monthlyPriceCents: number;
  currency: string;
  scanLimit: number;
  scansUsed: number;
  scansRemaining: number;
  periodStart: string;
  periodEnd: string;
  requiresPayment: boolean;
};

export type UploadInvoiceInput = {
  amountCents: number;
  buyerName: string;
  dueDate: string;
  file: File;
  invoiceNumber: string;
  purchaseOrderNumber: string;
  requestedAdvanceCents: number;
  supplierName: string;
};

export type OrganisationWorkspace = {
  organisationId: string;
  organisationName: string;
  accountName: string;
  email: string;
  role: Role;
};

export type WorkflowState = {
  invoice: InvoiceRecord;
  advanceCents: number;
  acceptedOfferId: string | null;
  financingLocked: boolean;
  idempotencyKey: string | null;
  auditEvents: AuditEvent[];
  notifications: NotificationItem[];
  offers: Offer[];
  riskFactors: RiskFactor[];
  ruleWeights: RuleWeight[];
  aiTasks: AiTask[];
  apEnvironment: ApEnvironment | null;
  transactionEvents: TransactionEventItem[];
  transactions: TransactionItem[];
};

export type LoadedWorkspace = {
  workspace: OrganisationWorkspace;
  state: WorkflowState | null;
  plans: SubscriptionPlan[];
  planStatus: PlanStatus | null;
};