import type {
  AiTask,
  ApEnvironment,
  AuditEvent,
  FinancingStatus,
  InvoiceRecord,
  InvoiceWorkflowStatus,
  LoadedWorkspace,
  Offer,
  OrganisationWorkspace,
  PlanStatus,
  RiskFactor,
  Role,
  SubscriptionPlan,
  Tone,
  TransactionItem,
  UploadInvoiceInput,
  VerificationStatus,
  WorkflowCommand,
  WorkflowState,
} from '../types';
import { workflowTransitions } from '../utils/workflow';
import { supabase } from './supabase';

export type OnboardingInput = {
  fullName: string;
  organisationName: string;
  accountType: Role;
};

export async function completeUserOnboarding(input: OnboardingInput) {
  const { error } = await supabase.rpc('complete_user_onboarding', {
    input_account_type: roleToOrganisationType(input.accountType),
    input_full_name: input.fullName.trim(),
    input_organisation_name: input.organisationName.trim(),
  });

  if (error) {
    throw new Error(error.message);
  }
}

export async function loadWorkspace(): Promise<LoadedWorkspace | null> {
  const { data: userData, error: userError } = await supabase.auth.getUser();

  if (userError) {
    throw new Error(userError.message);
  }

  const user = userData.user;

  if (!user) {
    return null;
  }

  const { data: memberRows, error: memberError } = await supabase
    .from('organisation_members')
    .select('organisation_id, role')
    .eq('user_id', user.id)
    .eq('status', 'ACTIVE')
    .limit(1);

  if (memberError) {
    throw new Error(memberError.message);
  }

  const member = memberRows?.[0] as { organisation_id: string; role: string } | undefined;

  if (!member) {
    return null;
  }

  const { data: organisationRow, error: organisationError } = await supabase
    .from('organisations')
    .select('*')
    .eq('id', member.organisation_id)
    .single();

  if (organisationError) {
    throw new Error(organisationError.message);
  }

  const { data: profileRow } = await supabase.from('profiles').select('*').eq('id', user.id).maybeSingle();
  const organisation = organisationRow as Record<string, unknown>;
  const profile = (profileRow ?? {}) as Record<string, unknown>;
  const role = roleFromOrganisationType(String(organisation.organisation_type ?? 'SME'));

  const workspace: OrganisationWorkspace = {
    accountName: String(profile.full_name ?? user.email ?? 'Account'),
    email: String(user.email ?? profile.email ?? ''),
    organisationId: member.organisation_id,
    organisationName: String(organisation.trading_name ?? organisation.legal_name ?? 'Organisation'),
    role,
  };

  const [plans, planStatus, state] = await Promise.all([
    loadSubscriptionPlans(),
    loadPlanStatus(),
    loadWorkflowState(workspace),
  ]);

  return { workspace, state, plans, planStatus };
}

export async function createInvoiceUploadInDatabase(workspace: OrganisationWorkspace, input: UploadInvoiceInput) {
  assertPdfFile(input.file);

  const fileHash = await sha256File(input.file);
  const { data, error } = await supabase.rpc('create_invoice_upload', {
    input_amount: fromCents(input.amountCents),
    input_buyer_name: input.buyerName.trim(),
    input_byte_size: input.file.size,
    input_due_date: input.dueDate || null,
    input_file_sha256: fileHash,
    input_invoice_number: input.invoiceNumber.trim(),
    input_mime_type: input.file.type || 'application/pdf',
    input_original_filename: input.file.name,
    input_purchase_order_number: input.purchaseOrderNumber.trim() || null,
    input_requested_advance: fromCents(input.requestedAdvanceCents),
    input_supplier_name: input.supplierName.trim(),
    target_organisation_id: workspace.organisationId,
  });

  if (error) {
    throw new Error(error.message);
  }

  const result = data as { storage_path?: string } | null;
  const storagePath = result?.storage_path;

  if (!storagePath) {
    throw new Error('The database did not return a storage path for this invoice.');
  }

  const { error: uploadError } = await supabase.storage.from('invoice-documents').upload(storagePath, input.file, {
    contentType: input.file.type || 'application/pdf',
    upsert: false,
  });

  if (uploadError) {
    throw new Error(uploadError.message);
  }

  return result;
}

export async function advanceWorkflowInDatabase(state: WorkflowState, command: WorkflowCommand) {
  const transition = workflowTransitions[command];

  const { error } = await supabase.rpc('advance_invoice_status', {
    actor_service: 'capitalbridge-api',
    event_code: transition.code,
    event_detail: transition.detail,
    expected_status: transition.expected,
    next_status: transition.next,
    target_invoice_id: state.invoice.id,
  });

  if (error) {
    throw new Error(error.message);
  }
}

export async function updateRequestedAdvanceInDatabase(state: WorkflowState, nextAmountCents: number) {
  const { error } = await supabase.rpc('update_requested_advance', {
    requested_amount: fromCents(nextAmountCents),
    target_invoice_id: state.invoice.id,
  });

  if (error) {
    throw new Error(error.message);
  }
}

export async function acceptOfferInDatabase(offerId: string) {
  const { error } = await supabase.rpc('accept_financing_offer', {
    input_idempotency_key: `offer-${offerId}-${Date.now()}`,
    target_offer_id: offerId,
  });

  if (error) {
    throw new Error(error.message);
  }
}

export async function selectSubscriptionPlanInDatabase(planId: string) {
  const { error } = await supabase.rpc('select_subscription_plan', {
    target_plan_id: planId,
  });

  if (error) {
    throw new Error(error.message);
  }
}

async function loadWorkflowState(workspace: OrganisationWorkspace): Promise<WorkflowState | null> {
  const invoiceRow = await loadInvoiceRow(workspace.organisationId);

  if (!invoiceRow) {
    return null;
  }

  const invoice = mapInvoice(invoiceRow);
  const financingRequest = await loadFinancingRequest(invoice.id);
  const offers = financingRequest ? await loadOffers(financingRequest.id) : [];
  const acceptedOffer = offers.find((offer) => offer.status === 'ACCEPTED') ?? null;
  const riskFactors = await loadRiskFactors(workspace.organisationId, invoice.id);
  const transactions = await loadTransactions(workspace.organisationId, invoice.id);
  const auditEvents = await loadAuditEvents(workspace.organisationId, invoice.id);
  const notifications = await loadNotifications(workspace.organisationId, invoice.id);
  const integration = await loadApEnvironment(workspace.organisationId);

  return {
    acceptedOfferId: acceptedOffer?.id ?? null,
    advanceCents: invoice.requestedCents,
    aiTasks: integration.tasks,
    apEnvironment: integration.environment,
    auditEvents,
    financingLocked: Boolean(acceptedOffer) || statusHasFinancingLock(invoice.status),
    idempotencyKey: null,
    invoice,
    notifications,
    offers,
    riskFactors,
    ruleWeights: riskFactors.map((factor) => ({
      label: factor.label,
      value: factor.possible > 0 ? Math.round((factor.earned / factor.possible) * 100) : 0,
    })),
    transactions,
  };
}

async function loadSubscriptionPlans(): Promise<SubscriptionPlan[]> {
  const { data, error } = await supabase
    .from('subscription_plans')
    .select('*')
    .eq('active', true)
    .order('monthly_price_cents', { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    benefits: Array.isArray(row.benefits) ? (row.benefits as string[]) : [],
    code: String(row.code ?? ''),
    currency: String(row.currency ?? 'ZAR'),
    description: String(row.description ?? ''),
    id: String(row.id),
    monthlyPriceCents: Number(row.monthly_price_cents ?? 0),
    name: String(row.name ?? 'Plan'),
    scanLimit: Number(row.scan_limit ?? 0),
  }));
}

async function loadPlanStatus(): Promise<PlanStatus | null> {
  const { data, error } = await supabase.rpc('get_plan_status');

  if (error) {
    throw new Error(error.message);
  }

  const row = data as Record<string, unknown> | null;

  if (!row) {
    return null;
  }

  return {
    currency: String(row.currency ?? 'ZAR'),
    monthlyPriceCents: Number(row.monthly_price_cents ?? 0),
    periodEnd: String(row.period_end ?? ''),
    periodStart: String(row.period_start ?? ''),
    planCode: String(row.plan_code ?? ''),
    planId: String(row.plan_id ?? ''),
    planName: String(row.plan_name ?? ''),
    requiresPayment: Boolean(row.requires_payment),
    scanLimit: Number(row.scan_limit ?? 0),
    scansRemaining: Number(row.scans_remaining ?? 0),
    scansUsed: Number(row.scans_used ?? 0),
  };
}

async function loadInvoiceRow(organisationId: string) {
  const { data, error } = await supabase
    .from('invoices')
    .select('*, buyers(legal_name), suppliers(legal_name), purchase_orders(po_number), invoice_files(original_filename, sha256), invoice_fingerprints(fingerprint_hash)')
    .eq('organisation_id', organisationId)
    .order('created_at', { ascending: false })
    .limit(1);

  if (error) {
    throw new Error(error.message);
  }

  return (data?.[0] as Record<string, unknown> | undefined) ?? null;
}

async function loadFinancingRequest(invoiceId: string) {
  const { data, error } = await supabase
    .from('financing_requests')
    .select('*')
    .eq('invoice_id', invoiceId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new Error(error.message);
  }

  return data as { id: string } | null;
}

async function loadOffers(financingRequestId: string): Promise<Offer[]> {
  const { data, error } = await supabase
    .from('financing_offers')
    .select('*')
    .eq('financing_request_id', financingRequestId)
    .order('created_at', { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  return ((data ?? []) as Record<string, unknown>[]).map((row, index) => ({
    feeBps: Number(row.fee_bps ?? 0),
    id: String(row.id),
    name: String(row.offer_name ?? 'Funding offer'),
    partner: String(row.financier_name ?? 'CapitalBridge financier'),
    recommended: index === 0,
    speed: String((row.metadata as Record<string, unknown> | undefined)?.speed ?? 'Same day'),
    status: String(row.status ?? 'OPEN'),
    termDays: Number(row.term_days ?? 0),
  }));
}

async function loadRiskFactors(organisationId: string, invoiceId: string): Promise<RiskFactor[]> {
  const { data: assessmentRows, error: assessmentError } = await supabase
    .from('risk_assessments')
    .select('id')
    .eq('organisation_id', organisationId)
    .eq('invoice_id', invoiceId)
    .order('created_at', { ascending: false })
    .limit(1);

  if (assessmentError) {
    throw new Error(assessmentError.message);
  }

  const assessment = assessmentRows?.[0] as { id: string } | undefined;

  if (!assessment) {
    return [];
  }

  const { data, error } = await supabase
    .from('risk_factors')
    .select('*')
    .eq('risk_assessment_id', assessment.id)
    .order('created_at', { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  return ((data ?? []) as Record<string, unknown>[]).map((row) => {
    const earned = Number(row.earned_score ?? 0);
    const possible = Number(row.max_score ?? 0);
    const ratio = possible > 0 ? earned / possible : 0;

    return {
      earned,
      kind: ratio >= 0.8 ? 'positive' : 'attention',
      label: String(row.label ?? row.code ?? 'Risk factor'),
      possible,
      tone: toneForRatio(ratio),
    };
  });
}

async function loadTransactions(organisationId: string, invoiceId: string): Promise<TransactionItem[]> {
  const { data, error } = await supabase
    .from('funding_transactions')
    .select('*')
    .eq('organisation_id', organisationId)
    .eq('invoice_id', invoiceId)
    .order('created_at', { ascending: false });

  if (error) {
    throw new Error(error.message);
  }

  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    amountCents: toCents(row.amount),
    date: formatDate(row.posted_at ?? row.created_at),
    id: String(row.id),
    label: String(row.transaction_type ?? 'Transaction').replace(/_/g, ' '),
    status: String(row.status ?? 'PENDING'),
  }));
}

async function loadAuditEvents(organisationId: string, invoiceId: string): Promise<AuditEvent[]> {
  const { data, error } = await supabase
    .from('audit_logs')
    .select('*')
    .eq('organisation_id', organisationId)
    .eq('invoice_id', invoiceId)
    .order('created_at', { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    actor: String(row.actor_service ?? 'CapitalBridge'),
    code: String(row.event_code ?? 'EVENT'),
    detail: String(row.event_detail ?? ''),
    time: formatTime(row.created_at),
  }));
}

async function loadNotifications(organisationId: string, invoiceId: string): Promise<WorkflowState['notifications']> {
  const { data, error } = await supabase
    .from('notifications')
    .select('*')
    .eq('organisation_id', organisationId)
    .eq('invoice_id', invoiceId)
    .order('created_at', { ascending: false })
    .limit(20);

  if (error) {
    throw new Error(error.message);
  }

  return ((data ?? []) as Record<string, unknown>[]).map((row) => ({
    detail: String(row.body ?? ''),
    id: String(row.id),
    title: String(row.title ?? 'Notification'),
    tone: normaliseTone(row.tone),
  }));
}

async function loadApEnvironment(organisationId: string): Promise<{ environment: ApEnvironment | null; tasks: AiTask[] }> {
  const { data, error } = await supabase
    .from('integrations')
    .select('*')
    .eq('organisation_id', organisationId)
    .eq('provider', 'Invoice Check')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new Error(error.message);
  }

  if (!data) {
    return { environment: null, tasks: [] };
  }

  const row = data as Record<string, unknown>;
  const metadata = (row.metadata ?? {}) as Record<string, unknown>;
  const tasks = Array.isArray(metadata.tasks) ? metadata.tasks : [];

  return {
    environment: {
      liveUrl: String(metadata.live_url ?? ''),
      localUrl: String(metadata.local_url ?? ''),
      name: String(row.provider ?? 'Invoice Check'),
      source: String(metadata.source ?? ''),
    },
    tasks: tasks.map((task) => {
      const item = task as Record<string, unknown>;

      return {
        difficulty: String(item.difficulty ?? ''),
        mapsTo: String(item.maps_to ?? ''),
        name: String(item.name ?? ''),
        tone: normaliseTone(item.tone),
      };
    }),
  };
}

function mapInvoice(row: Record<string, unknown>): InvoiceRecord {
  const fileRows = Array.isArray(row.invoice_files) ? (row.invoice_files as Record<string, unknown>[]) : [];
  const fingerprintRows = Array.isArray(row.invoice_fingerprints) ? (row.invoice_fingerprints as Record<string, unknown>[]) : [];
  const buyer = row.buyers as Record<string, unknown> | null;
  const supplier = row.suppliers as Record<string, unknown> | null;
  const purchaseOrder = row.purchase_orders as Record<string, unknown> | null;
  const file = fileRows[0] ?? {};
  const fingerprint = fingerprintRows[0] ?? {};

  return {
    amountCents: toCents(row.amount),
    buyer: String(buyer?.legal_name ?? 'Buyer not linked'),
    dueDate: row.due_date ? String(row.due_date) : null,
    dueDays: daysUntil(row.due_date),
    fileHash: String(row.file_hash ?? file.sha256 ?? ''),
    fileName: String(file.original_filename ?? `${String(row.invoice_number ?? 'invoice')}.pdf`),
    financingStatus: String(row.financing_status ?? 'NOT_FINANCED') as FinancingStatus,
    id: String(row.id),
    identityHash: String(row.invoice_fingerprint ?? fingerprint.fingerprint_hash ?? ''),
    industry: String(row.industry ?? ''),
    issueDate: row.issue_date ? String(row.issue_date) : null,
    maxAdvanceCents: toCents(row.max_advance),
    number: String(row.invoice_number ?? 'Invoice'),
    outstandingCents: toCents(row.outstanding_amount),
    purchaseOrder: String(row.purchase_order_number ?? purchaseOrder?.po_number ?? ''),
    requestedCents: toCents(row.requested_advance),
    status: String(row.status ?? 'UPLOADED') as InvoiceWorkflowStatus,
    supplier: String(supplier?.legal_name ?? 'Supplier not linked'),
    verificationStatus: String(row.verification_status ?? 'UNVERIFIED') as VerificationStatus,
  };
}

function assertPdfFile(file: File) {
  const isPdfName = file.name.toLowerCase().endsWith('.pdf');
  const isPdfMime = !file.type || file.type === 'application/pdf';

  if (!isPdfName || !isPdfMime) {
    throw new Error('Please choose a PDF invoice file.');
  }

  if (file.size > 10 * 1024 * 1024) {
    throw new Error('PDF invoices must be 10 MB or smaller.');
  }
}

async function sha256File(file: File) {
  if (!globalThis.crypto?.subtle) {
    throw new Error('This browser cannot hash files securely. Try a modern browser.');
  }

  const buffer = await file.arrayBuffer();
  const digest = await globalThis.crypto.subtle.digest('SHA-256', buffer);
  const bytes = Array.from(new Uint8Array(digest));

  return bytes.map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function roleFromOrganisationType(value: string): Role {
  if (value === 'BUYER') {
    return 'Buyer';
  }

  if (value === 'FINANCIER') {
    return 'Financier';
  }

  if (value === 'ADMIN') {
    return 'Admin';
  }

  return 'SME';
}

function roleToOrganisationType(role: Role) {
  if (role === 'Buyer') {
    return 'BUYER';
  }

  if (role === 'Financier') {
    return 'FINANCIER';
  }

  if (role === 'Admin') {
    return 'ADMIN';
  }

  return 'SME';
}

function statusHasFinancingLock(status: InvoiceWorkflowStatus) {
  return ['OFFER_ACCEPTED', 'FUNDED', 'SETTLED'].includes(status);
}

function toCents(value: unknown) {
  return Math.round(Number(value ?? 0) * 100);
}

function fromCents(value: number) {
  return Number((value / 100).toFixed(2));
}

function daysUntil(value: unknown) {
  if (!value) {
    return 0;
  }

  const dueDate = new Date(String(value));
  const today = new Date();
  const diff = dueDate.getTime() - today.getTime();

  return Math.max(0, Math.ceil(diff / 86_400_000));
}

function formatTime(value: unknown) {
  if (!value) {
    return '--:--';
  }

  return new Date(String(value)).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function formatDate(value: unknown) {
  if (!value) {
    return 'Pending';
  }

  return new Date(String(value)).toLocaleDateString();
}

function normaliseTone(value: unknown): Tone {
  if (value === 'blue' || value === 'green' || value === 'amber' || value === 'red' || value === 'slate') {
    return value;
  }

  return 'neutral';
}

function toneForRatio(ratio: number): Tone {
  if (ratio >= 0.8) {
    return 'green';
  }

  if (ratio >= 0.55) {
    return 'amber';
  }

  return 'red';
}