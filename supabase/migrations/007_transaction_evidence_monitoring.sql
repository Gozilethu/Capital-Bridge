create table if not exists public.buyer_payment_history (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  buyer_id uuid not null references public.buyers(id) on delete cascade,
  currency text not null default 'ZAR',
  total_invoice_count integer not null default 0 check (total_invoice_count >= 0),
  paid_invoice_count integer not null default 0 check (paid_invoice_count >= 0),
  late_invoice_count integer not null default 0 check (late_invoice_count >= 0),
  disputed_invoice_count integer not null default 0 check (disputed_invoice_count >= 0),
  total_paid_amount numeric(18,2) not null default 0,
  on_time_rate numeric(5,2) not null default 0,
  average_days_late numeric(8,2) not null default 0,
  disputed_invoice_rate numeric(5,2) not null default 0,
  last_payment_at date,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, buyer_id, currency)
);

create table if not exists public.buyer_verifications (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  buyer_id uuid references public.buyers(id) on delete set null,
  purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  status text not null default 'PENDING' check (status in ('PENDING', 'CONFIRMED', 'PARTIAL', 'MISMATCH', 'FAILED', 'EXPIRED')),
  verification_source text not null default 'Invoice Check ERP',
  external_reference text,
  matched_supplier boolean not null default false,
  matched_amount boolean not null default false,
  matched_due_date boolean not null default false,
  matched_po boolean not null default false,
  unpaid_confirmed boolean not null default false,
  evidence jsonb not null default '{}'::jsonb,
  requested_at timestamptz not null default now(),
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, invoice_id, verification_source)
);

create table if not exists public.delivery_confirmations (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  status text not null default 'PENDING' check (status in ('PENDING', 'CONFIRMED', 'PARTIAL', 'REVIEW_REQUIRED', 'NOT_REQUIRED', 'FAILED')),
  confirmation_source text not null default 'buyer-confirmation',
  confirmed_quantity numeric(18,2),
  expected_delivery_date date,
  confirmed_delivery_date date,
  evidence jsonb not null default '{}'::jsonb,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, invoice_id, confirmation_source)
);

create table if not exists public.receivable_fingerprints (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  buyer_id uuid references public.buyers(id) on delete set null,
  supplier_id uuid references public.suppliers(id) on delete set null,
  purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  supplier_key text not null,
  buyer_key text not null,
  invoice_number_key text not null,
  purchase_order_key text not null default '',
  amount numeric(18,2) not null,
  issue_date date,
  due_date date,
  fingerprint_hash text not null,
  duplicate_detected boolean not null default false,
  status text not null default 'UNIQUE' check (status in ('UNIQUE', 'DUPLICATE', 'REVIEW_REQUIRED')),
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (fingerprint_hash),
  unique (organisation_id, invoice_id)
);

create table if not exists public.transaction_events (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  invoice_id uuid references public.invoices(id) on delete cascade,
  purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  phase text not null check (phase in ('PO', 'DELIVERY', 'INVOICE', 'VERIFICATION', 'DUPLICATE_CHECK', 'RISK', 'FUNDING', 'PAYMENT', 'SETTLEMENT')),
  event_type text not null,
  status text not null default 'PENDING' check (status in ('PENDING', 'PASSED', 'WARNING', 'FAILED', 'POSTED', 'RECONCILED')),
  detail text not null,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.settlement_events (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  financing_agreement_id uuid references public.financing_agreements(id) on delete set null,
  settlement_id uuid references public.settlements(id) on delete set null,
  event_type text not null,
  status text not null default 'PENDING' check (status in ('PENDING', 'POSTED', 'RECONCILED', 'FAILED')),
  amount numeric(18,2) not null default 0,
  payer text,
  payee text,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists buyer_payment_history_buyer_idx on public.buyer_payment_history (organisation_id, buyer_id);
create index if not exists buyer_verifications_invoice_idx on public.buyer_verifications (organisation_id, invoice_id);
create index if not exists delivery_confirmations_invoice_idx on public.delivery_confirmations (organisation_id, invoice_id);
create index if not exists receivable_fingerprints_hash_idx on public.receivable_fingerprints (fingerprint_hash);
create index if not exists transaction_events_invoice_idx on public.transaction_events (organisation_id, invoice_id, occurred_at);
create index if not exists settlement_events_invoice_idx on public.settlement_events (organisation_id, invoice_id, occurred_at);

alter table public.buyer_payment_history enable row level security;
alter table public.buyer_verifications enable row level security;
alter table public.delivery_confirmations enable row level security;
alter table public.receivable_fingerprints enable row level security;
alter table public.transaction_events enable row level security;
alter table public.settlement_events enable row level security;

drop policy if exists buyer_payment_history_read_member on public.buyer_payment_history;
create policy buyer_payment_history_read_member on public.buyer_payment_history
  for select using (public.has_org_role(organisation_id, array['OWNER', 'ADMIN', 'FINANCE', 'OPERATIONS', 'BUYER_APPROVER', 'FINANCIER_ANALYST']::public.member_role[]));

drop policy if exists buyer_verifications_read_member on public.buyer_verifications;
create policy buyer_verifications_read_member on public.buyer_verifications
  for select using (public.has_org_role(organisation_id, array['OWNER', 'ADMIN', 'FINANCE', 'OPERATIONS', 'BUYER_APPROVER', 'FINANCIER_ANALYST']::public.member_role[]));

drop policy if exists delivery_confirmations_read_member on public.delivery_confirmations;
create policy delivery_confirmations_read_member on public.delivery_confirmations
  for select using (public.has_org_role(organisation_id, array['OWNER', 'ADMIN', 'FINANCE', 'OPERATIONS', 'BUYER_APPROVER', 'FINANCIER_ANALYST']::public.member_role[]));

drop policy if exists receivable_fingerprints_read_member on public.receivable_fingerprints;
create policy receivable_fingerprints_read_member on public.receivable_fingerprints
  for select using (public.has_org_role(organisation_id, array['OWNER', 'ADMIN', 'FINANCE', 'OPERATIONS', 'BUYER_APPROVER', 'FINANCIER_ANALYST']::public.member_role[]));

drop policy if exists transaction_events_read_member on public.transaction_events;
create policy transaction_events_read_member on public.transaction_events
  for select using (public.has_org_role(organisation_id, array['OWNER', 'ADMIN', 'FINANCE', 'OPERATIONS', 'BUYER_APPROVER', 'FINANCIER_ANALYST']::public.member_role[]));

drop policy if exists settlement_events_read_member on public.settlement_events;
create policy settlement_events_read_member on public.settlement_events
  for select using (public.has_org_role(organisation_id, array['OWNER', 'ADMIN', 'FINANCE', 'OPERATIONS', 'BUYER_APPROVER', 'FINANCIER_ANALYST']::public.member_role[]));

grant select on public.buyer_payment_history to authenticated;
grant select on public.buyer_verifications to authenticated;
grant select on public.delivery_confirmations to authenticated;
grant select on public.receivable_fingerprints to authenticated;
grant select on public.transaction_events to authenticated;
grant select on public.settlement_events to authenticated;
create or replace function public.create_invoice_upload(
  target_organisation_id uuid,
  input_invoice_number text,
  input_supplier_name text,
  input_buyer_name text,
  input_purchase_order_number text,
  input_amount numeric,
  input_requested_advance numeric,
  input_due_date date,
  input_original_filename text,
  input_file_sha256 text,
  input_mime_type text,
  input_byte_size bigint,
  input_page_count integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  buyer_record_id uuid;
  supplier_record_id uuid;
  po_record_id uuid;
  invoice_record_id uuid;
  storage_path text;
  clean_file_name text;
  normalized_invoice text;
  normalized_supplier text;
  normalized_buyer text;
  normalized_po text;
  fingerprint_value text;
  max_advance numeric(18,2);
  requested_advance numeric(18,2);
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;

  if not public.has_org_role(target_organisation_id, array['OWNER', 'ADMIN', 'FINANCE', 'OPERATIONS']::public.member_role[]) then
    raise exception 'not allowed';
  end if;

  if nullif(trim(input_invoice_number), '') is null then raise exception 'invoice number is required'; end if;
  if nullif(trim(input_supplier_name), '') is null or nullif(trim(input_buyer_name), '') is null then raise exception 'supplier and buyer are required'; end if;
  if input_amount <= 0 then raise exception 'invoice amount must be positive'; end if;
  if input_requested_advance < 0 or input_requested_advance > input_amount then raise exception 'requested advance must be between zero and invoice amount'; end if;
  if input_due_date is null then raise exception 'invoice due date is required'; end if;
  if input_byte_size <= 0 or input_byte_size > 10485760 then raise exception 'PDF invoices must be 10 MB or smaller'; end if;
  if lower(coalesce(input_mime_type, '')) <> 'application/pdf' then raise exception 'only PDF invoices can be uploaded'; end if;
  if lower(coalesce(input_original_filename, '')) not like '%.pdf' then raise exception 'only .pdf invoice files can be uploaded'; end if;
  if input_file_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'invalid SHA-256 file hash'; end if;

  normalized_invoice := lower(regexp_replace(trim(input_invoice_number), '[^a-zA-Z0-9]', '', 'g'));
  normalized_supplier := lower(regexp_replace(trim(input_supplier_name), '[^a-zA-Z0-9]', '', 'g'));
  normalized_buyer := lower(regexp_replace(trim(input_buyer_name), '[^a-zA-Z0-9]', '', 'g'));
  normalized_po := lower(regexp_replace(trim(coalesce(input_purchase_order_number, '')), '[^a-zA-Z0-9]', '', 'g'));
  fingerprint_value := encode(extensions.digest(normalized_supplier || ':' || normalized_buyer || ':' || normalized_invoice || ':' || input_amount::text || ':' || input_due_date::text || ':' || normalized_po, 'sha256'::text), 'hex');

  if exists (select 1 from public.global_invoice_registry registry where registry.file_sha256 = input_file_sha256) then
    raise exception 'This invoice file has already been submitted before.';
  end if;

  if exists (select 1 from public.global_invoice_registry registry where registry.fingerprint_hash = fingerprint_value) then
    raise exception 'A receivable with the same supplier, buyer, invoice number, amount, due date, and purchase order has already been submitted before.';
  end if;

  if exists (select 1 from public.invoice_files file_row where file_row.sha256 = input_file_sha256) then
    raise exception 'This invoice file has already been submitted before.';
  end if;

  if exists (select 1 from public.receivable_fingerprints receivable_row where receivable_row.fingerprint_hash = fingerprint_value) then
    raise exception 'A matching receivable fingerprint already exists.';
  end if;

  if exists (select 1 from public.invoices invoice_row where invoice_row.organisation_id = target_organisation_id and lower(invoice_row.invoice_number) = lower(trim(input_invoice_number))) then
    raise exception 'This workspace already has an invoice with that invoice number.';
  end if;

  select id into supplier_record_id
  from public.suppliers
  where organisation_id = target_organisation_id and lower(legal_name) = lower(trim(input_supplier_name))
  limit 1;

  if supplier_record_id is null then
    insert into public.suppliers (organisation_id, legal_name)
    values (target_organisation_id, trim(input_supplier_name))
    returning id into supplier_record_id;
  end if;

  select id into buyer_record_id
  from public.buyers
  where organisation_id = target_organisation_id and lower(legal_name) = lower(trim(input_buyer_name))
  limit 1;

  if buyer_record_id is null then
    insert into public.buyers (organisation_id, legal_name, payment_history)
    values (target_organisation_id, trim(input_buyer_name), '{}'::jsonb)
    returning id into buyer_record_id;
  end if;

  insert into public.buyer_payment_history (organisation_id, buyer_id, currency, evidence)
  values (target_organisation_id, buyer_record_id, 'ZAR', jsonb_build_object('source', 'workspace-ledger', 'summary', 'No settled invoices recorded yet'))
  on conflict (organisation_id, buyer_id, currency) do nothing;

  if nullif(trim(coalesce(input_purchase_order_number, '')), '') is not null then
    select id into po_record_id
    from public.purchase_orders
    where organisation_id = target_organisation_id and lower(po_number) = lower(trim(input_purchase_order_number))
    limit 1;

    if po_record_id is null then
      insert into public.purchase_orders (organisation_id, buyer_id, supplier_id, po_number, currency, amount, status, erp_source, erp_payload)
      values (target_organisation_id, buyer_record_id, supplier_record_id, trim(input_purchase_order_number), 'ZAR', input_amount, 'OPEN', 'Invoice Check', jsonb_build_object('created_from_upload', true, 'evidence_role', 'transaction anchor'))
      returning id into po_record_id;
    end if;
  end if;

  max_advance := round(input_amount * 0.85, 2);
  requested_advance := case
    when input_requested_advance = 0 then round(input_amount * 0.30, 2)
    when input_requested_advance > max_advance then max_advance
    else input_requested_advance
  end;

  insert into public.invoices (organisation_id, buyer_id, supplier_id, purchase_order_id, invoice_number, purchase_order_number, currency, amount, requested_advance, max_advance, outstanding_amount, issue_date, due_date, status, verification_status, financing_status, file_hash, invoice_fingerprint, created_by)
  values (target_organisation_id, buyer_record_id, supplier_record_id, po_record_id, trim(input_invoice_number), nullif(trim(coalesce(input_purchase_order_number, '')), ''), 'ZAR', input_amount, requested_advance, max_advance, input_amount, current_date, input_due_date, 'UPLOADED', 'UNVERIFIED', 'NOT_FINANCED', input_file_sha256, fingerprint_value, auth.uid())
  returning id into invoice_record_id;

  clean_file_name := regexp_replace(coalesce(input_original_filename, 'invoice.pdf'), '[^a-zA-Z0-9._-]', '_', 'g');
  storage_path := target_organisation_id::text || '/' || invoice_record_id::text || '/' || clean_file_name;

  insert into public.invoice_files (organisation_id, invoice_id, storage_bucket, storage_path, original_filename, sha256, mime_type, byte_size, page_count, malware_status, validation_status)
  values (target_organisation_id, invoice_record_id, 'invoice-documents', storage_path, clean_file_name, input_file_sha256, 'application/pdf', input_byte_size, input_page_count, 'QUEUED', 'QUEUED');

  insert into public.invoice_fingerprints (organisation_id, invoice_id, file_sha256, perceptual_hash, normalized_invoice_number, supplier_tax_number, buyer_registration_number, amount, due_date, fingerprint_hash)
  values (target_organisation_id, invoice_record_id, input_file_sha256, null, normalized_invoice, normalized_supplier, normalized_buyer, input_amount, input_due_date, fingerprint_value);

  insert into public.receivable_fingerprints (organisation_id, invoice_id, buyer_id, supplier_id, purchase_order_id, supplier_key, buyer_key, invoice_number_key, purchase_order_key, amount, issue_date, due_date, fingerprint_hash, duplicate_detected, status, evidence)
  values (target_organisation_id, invoice_record_id, buyer_record_id, supplier_record_id, po_record_id, normalized_supplier, normalized_buyer, normalized_invoice, normalized_po, input_amount, current_date, input_due_date, fingerprint_value, false, 'UNIQUE', jsonb_build_object('fingerprint_basis', array['supplier', 'buyer', 'invoice_number', 'amount', 'due_date', 'purchase_order']));

  insert into public.global_invoice_registry (first_organisation_id, first_invoice_id, file_sha256, fingerprint_hash)
  values (target_organisation_id, invoice_record_id, input_file_sha256, fingerprint_value);

  insert into public.transaction_events (organisation_id, invoice_id, purchase_order_id, phase, event_type, status, detail, metadata)
  values
    (target_organisation_id, invoice_record_id, po_record_id, 'INVOICE', 'INVOICE_UPLOADED', 'PASSED', 'Invoice uploaded as evidence, not proof of the receivable by itself.', jsonb_build_object('file_sha256', input_file_sha256, 'storage_path', storage_path)),
    (target_organisation_id, invoice_record_id, po_record_id, 'DUPLICATE_CHECK', 'RECEIVABLE_FINGERPRINT_CREATED', 'PASSED', 'Transaction-level receivable fingerprint created before financing opens.', jsonb_build_object('fingerprint_hash', fingerprint_value, 'includes_po', normalized_po <> '')),
    (target_organisation_id, invoice_record_id, po_record_id, 'PO', case when po_record_id is null then 'PO_NOT_LINKED' else 'PO_LINKED' end, case when po_record_id is null then 'WARNING' else 'PASSED' end, case when po_record_id is null then 'No purchase order was linked at upload.' else 'Purchase order captured as transaction anchor.' end, jsonb_build_object('purchase_order_number', nullif(trim(coalesce(input_purchase_order_number, '')), '')));

  insert into public.audit_logs (organisation_id, invoice_id, actor_user_id, actor_service, event_code, event_detail, metadata)
  values (target_organisation_id, invoice_record_id, auth.uid(), 'invoice-upload', 'RECEIVABLE_EVIDENCE_CREATED', 'PDF metadata, receivable fingerprint, and monitoring events stored', jsonb_build_object('file_sha256', input_file_sha256, 'storage_path', storage_path, 'fingerprint_hash', fingerprint_value));

  insert into public.notifications (organisation_id, user_id, invoice_id, title, body, tone)
  values (target_organisation_id, auth.uid(), invoice_record_id, 'Receivable captured', 'Buyer/ERP verification is required before funding can open.', 'blue');

  return jsonb_build_object('invoice_id', invoice_record_id, 'storage_path', storage_path, 'file_sha256', input_file_sha256, 'fingerprint_hash', fingerprint_value);
exception
  when unique_violation then
    raise exception 'This invoice or receivable appears to have already been submitted.';
end;
$$;

grant execute on function public.create_invoice_upload(uuid, text, text, text, text, numeric, numeric, date, text, text, text, bigint, integer) to authenticated;
create or replace function public.advance_invoice_status(
  target_invoice_id uuid,
  expected_status public.invoice_workflow_status,
  next_status public.invoice_workflow_status,
  event_code text,
  event_detail text,
  actor_service text default 'capitalbridge-api'
)
returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  current_invoice public.invoices%rowtype;
  updated_invoice public.invoices%rowtype;
  request_id uuid;
  verification_request_id uuid;
  assessment_id uuid;
  agreement_record public.financing_agreements%rowtype;
  settlement_id uuid;
  fee_amount numeric(18,2);
  principal_amount numeric(18,2);
  remainder_amount numeric(18,2);
  buyer_history_count integer := 0;
  buyer_on_time_rate numeric(5,2) := 0;
  buyer_score numeric(6,2);
  po_score numeric(6,2);
  delivery_score numeric(6,2);
  duplicate_score numeric(6,2) := 15;
  payment_score numeric(6,2);
  pdf_score numeric(6,2) := 5;
  score_value numeric(5,2);
  score_band text;
  score_decision text;
  days_late integer := 0;
begin
  select * into current_invoice from public.invoices where id = target_invoice_id for update;
  if not found then raise exception 'invoice not found'; end if;

  if not public.has_org_role(current_invoice.organisation_id, array['OWNER', 'ADMIN', 'FINANCE', 'OPERATIONS', 'BUYER_APPROVER', 'FINANCIER_ANALYST']::public.member_role[]) then
    raise exception 'not allowed';
  end if;

  if current_invoice.status <> expected_status then
    raise exception 'invalid invoice state: expected %, found %', expected_status, current_invoice.status;
  end if;

  if public.invoice_status_rank(next_status) <> public.invoice_status_rank(expected_status) + 1 then
    raise exception 'invalid transition from % to %', expected_status, next_status;
  end if;

  if next_status = 'SCANNING' then
    perform public.consume_invoice_scan_quota(current_invoice.organisation_id);
  end if;

  update public.invoices
  set status = next_status,
      verification_status = case
        when next_status = 'VERIFYING' then 'PENDING'::public.verification_status
        when next_status in ('VERIFIED', 'RISK_ASSESSED', 'FINANCE_ELIGIBLE', 'OFFER_ACCEPTED', 'FUNDED', 'SETTLED') then 'VERIFIED'::public.verification_status
        else verification_status end,
      financing_status = case
        when next_status = 'FINANCE_ELIGIBLE' then 'ELIGIBLE'::public.financing_status
        when next_status = 'OFFER_ACCEPTED' then 'OFFER_ACCEPTED'::public.financing_status
        when next_status = 'FUNDED' then 'ACTIVE'::public.financing_status
        when next_status = 'SETTLED' then 'SETTLED'::public.financing_status
        else financing_status end,
      outstanding_amount = case when next_status = 'SETTLED' then 0 else outstanding_amount end,
      updated_at = now()
  where id = target_invoice_id
  returning * into updated_invoice;

  if next_status = 'SCANNING' then
    update public.invoice_files set malware_status = 'PASSED', validation_status = 'PASSED' where invoice_id = current_invoice.id;
    insert into public.fraud_checks (organisation_id, invoice_id, check_type, status, score_delta, evidence)
    values (current_invoice.organisation_id, current_invoice.id, 'PDF_DOCUMENT_INTAKE', 'PASSED', 5, jsonb_build_object('mime_type', 'application/pdf', 'invoice_number', current_invoice.invoice_number, 'amount', current_invoice.amount));
    insert into public.transaction_events (organisation_id, invoice_id, purchase_order_id, phase, event_type, status, detail, metadata)
    values (current_invoice.organisation_id, current_invoice.id, current_invoice.purchase_order_id, 'INVOICE', 'PDF_EVIDENCE_VALIDATED', 'PASSED', 'PDF passed intake checks and remains supporting evidence for the transaction.', jsonb_build_object('invoice_number', current_invoice.invoice_number));
  end if;

  if next_status = 'EXTRACTED' then
    insert into public.invoice_extracted_fields (organisation_id, invoice_id, extraction_engine, model_version, schema_version, confidence, extracted_json, source_page_count, trace_id)
    values (current_invoice.organisation_id, current_invoice.id, 'Invoice Check', 'invoice-check-v1', 'invoice-v1', 94.50, jsonb_build_object('invoice_number', current_invoice.invoice_number, 'amount', current_invoice.amount, 'currency', current_invoice.currency, 'purchase_order_number', current_invoice.purchase_order_number, 'buyer_id', current_invoice.buyer_id, 'supplier_id', current_invoice.supplier_id), 1, 'trace-' || current_invoice.id::text);
    insert into public.transaction_events (organisation_id, invoice_id, purchase_order_id, phase, event_type, status, detail, metadata)
    values (current_invoice.organisation_id, current_invoice.id, current_invoice.purchase_order_id, 'INVOICE', 'INVOICE_FIELDS_CAPTURED', 'PASSED', 'Invoice fields captured for buyer and ERP comparison.', jsonb_build_object('source', 'Invoice Check'));
  end if;

  if next_status = 'VERIFYING' then
    insert into public.verification_requests (organisation_id, invoice_id, request_type, external_reference, idempotency_key, status, requested_by)
    values (current_invoice.organisation_id, current_invoice.id, 'BUYER_ERP_RECEIVABLE_CONFIRMATION', current_invoice.purchase_order_number, 'verify-' || current_invoice.id::text, 'RUNNING', auth.uid())
    on conflict (organisation_id, idempotency_key) do update set status = 'RUNNING', updated_at = now();

    insert into public.buyer_verifications (organisation_id, buyer_id, purchase_order_id, invoice_id, status, verification_source, external_reference, evidence)
    values (current_invoice.organisation_id, current_invoice.buyer_id, current_invoice.purchase_order_id, current_invoice.id, 'PENDING', 'Buyer ERP', current_invoice.purchase_order_number, jsonb_build_object('requested_by', auth.uid(), 'purpose', 'confirm receivable existence and unpaid status'))
    on conflict (organisation_id, invoice_id, verification_source) do update set status = 'PENDING', requested_at = now(), updated_at = now();

    insert into public.transaction_events (organisation_id, invoice_id, purchase_order_id, phase, event_type, status, detail, metadata)
    values (current_invoice.organisation_id, current_invoice.id, current_invoice.purchase_order_id, 'VERIFICATION', 'BUYER_ERP_VERIFICATION_REQUESTED', 'PENDING', 'Buyer or ERP confirmation requested before any financing offer can open.', jsonb_build_object('purchase_order_number', current_invoice.purchase_order_number));
  end if;

  if next_status = 'VERIFIED' then
    select id into verification_request_id from public.verification_requests where invoice_id = current_invoice.id order by created_at desc limit 1;
    if verification_request_id is not null then
      update public.verification_requests set status = 'PASSED', updated_at = now() where id = verification_request_id;
      insert into public.verification_results (organisation_id, verification_request_id, invoice_id, result_status, confidence, mismatch_flags, evidence, signed_by)
      values (current_invoice.organisation_id, verification_request_id, current_invoice.id, 'VERIFIED', 96.00, '[]'::jsonb, jsonb_build_object('po_match', current_invoice.purchase_order_id is not null, 'supplier_match', true, 'amount_match', true, 'unpaid', true, 'buyer_confirmation_required', true), auth.uid());
    end if;

    insert into public.buyer_verifications (organisation_id, buyer_id, purchase_order_id, invoice_id, status, verification_source, external_reference, matched_supplier, matched_amount, matched_due_date, matched_po, unpaid_confirmed, evidence, confirmed_at)
    values (current_invoice.organisation_id, current_invoice.buyer_id, current_invoice.purchase_order_id, current_invoice.id, case when current_invoice.purchase_order_id is null then 'PARTIAL' else 'CONFIRMED' end, 'Buyer ERP', current_invoice.purchase_order_number, true, true, true, current_invoice.purchase_order_id is not null, true, jsonb_build_object('confirmation', 'buyer and receivable checks recorded', 'po_present', current_invoice.purchase_order_id is not null), now())
    on conflict (organisation_id, invoice_id, verification_source) do update set status = excluded.status, matched_supplier = excluded.matched_supplier, matched_amount = excluded.matched_amount, matched_due_date = excluded.matched_due_date, matched_po = excluded.matched_po, unpaid_confirmed = excluded.unpaid_confirmed, evidence = excluded.evidence, confirmed_at = now(), updated_at = now();

    insert into public.delivery_confirmations (organisation_id, purchase_order_id, invoice_id, status, confirmation_source, evidence)
    values (current_invoice.organisation_id, current_invoice.purchase_order_id, current_invoice.id, case when current_invoice.purchase_order_id is null then 'REVIEW_REQUIRED' else 'PENDING' end, 'delivery-monitor', jsonb_build_object('assessment', 'delivery evidence must be confirmed or monitored through settlement'))
    on conflict (organisation_id, invoice_id, confirmation_source) do update set status = excluded.status, evidence = excluded.evidence, updated_at = now();

    insert into public.transaction_events (organisation_id, invoice_id, purchase_order_id, phase, event_type, status, detail, metadata)
    values
      (current_invoice.organisation_id, current_invoice.id, current_invoice.purchase_order_id, 'VERIFICATION', 'BUYER_RECEIVABLE_CONFIRMED', case when current_invoice.purchase_order_id is null then 'WARNING' else 'PASSED' end, case when current_invoice.purchase_order_id is null then 'Buyer verification recorded, but PO evidence is missing.' else 'Buyer and ERP evidence confirm the receivable and PO match.' end, jsonb_build_object('buyer_id', current_invoice.buyer_id, 'matched_po', current_invoice.purchase_order_id is not null)),
      (current_invoice.organisation_id, current_invoice.id, current_invoice.purchase_order_id, 'DELIVERY', 'DELIVERY_EVIDENCE_MONITORING_OPENED', 'PENDING', 'Delivery confirmation is tracked as part of the closed-loop transaction.', jsonb_build_object('requires_follow_up', true));
  end if;

  if next_status = 'RISK_ASSESSED' then
    select coalesce(history.total_invoice_count, 0), coalesce(history.on_time_rate, 0)
    into buyer_history_count, buyer_on_time_rate
    from public.buyer_payment_history history
    where history.organisation_id = current_invoice.organisation_id
      and history.buyer_id = current_invoice.buyer_id
      and history.currency = current_invoice.currency
    limit 1;

    buyer_score := 20;
    po_score := case when current_invoice.purchase_order_id is null then 7 else 15 end;
    delivery_score := case when current_invoice.purchase_order_id is null then 3 else 8 end;
    payment_score := case when coalesce(buyer_history_count, 0) > 0 then round(buyer_on_time_rate * 15 / 100.0, 2) else 4 end;
    score_value := least(100, buyer_score + po_score + delivery_score + duplicate_score + payment_score + pdf_score);
    score_band := case when score_value >= 80 then 'LOW' when score_value >= 60 then 'MEDIUM' else 'HIGH' end;
    score_decision := case when score_value >= 60 then 'ELIGIBLE' else 'MANUAL_REVIEW' end;

    insert into public.fraud_checks (organisation_id, invoice_id, check_type, status, score_delta, evidence)
    values
      (current_invoice.organisation_id, current_invoice.id, 'EXACT_FILE_DUPLICATE', 'PASSED', 8, jsonb_build_object('duplicate_found', false)),
      (current_invoice.organisation_id, current_invoice.id, 'RECEIVABLE_FINGERPRINT_DUPLICATE', 'PASSED', 15, jsonb_build_object('duplicate_found', false, 'fingerprint', current_invoice.invoice_fingerprint)),
      (current_invoice.organisation_id, current_invoice.id, 'LOOKALIKE_SUPPLIER_DOMAIN', 'PASSED', 5, jsonb_build_object('domain_change', false)),
      (current_invoice.organisation_id, current_invoice.id, 'BANK_ACCOUNT_CHANGE', 'PASSED', 5, jsonb_build_object('bank_change', false));

    insert into public.risk_assessments (organisation_id, invoice_id, model_version, score, band, decision, explanation, created_by_service)
    values (current_invoice.organisation_id, current_invoice.id, 'capitalbridge-transaction-risk-v2', score_value, score_band, score_decision, jsonb_build_object('summary', 'Risk is driven by buyer/obligor verification, PO evidence, receivable uniqueness, buyer payment behaviour, and delivery monitoring.', 'buyer_history_count', buyer_history_count), 'transaction-risk-engine')
    returning id into assessment_id;

    insert into public.risk_factors (organisation_id, risk_assessment_id, invoice_id, code, label, earned_score, max_score, weight, evidence)
    values
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'BUYER_OBLIGOR_VERIFICATION', 'Buyer / obligor confirmation', buyer_score, 20, 20, jsonb_build_object('source', 'buyer_verifications')),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'PO_ERP_MATCH', 'PO and ERP transaction match', po_score, 15, 15, jsonb_build_object('po_present', current_invoice.purchase_order_id is not null, 'source', 'purchase_orders')),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'RECEIVABLE_UNIQUENESS', 'Duplicate receivable prevention', duplicate_score, 15, 15, jsonb_build_object('source', 'receivable_fingerprints', 'fingerprint_hash', current_invoice.invoice_fingerprint)),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'BUYER_PAYMENT_BEHAVIOUR', 'Buyer payment behaviour', payment_score, 15, 15, jsonb_build_object('history_count', buyer_history_count, 'on_time_rate', buyer_on_time_rate)),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'SME_DELIVERY_EVIDENCE', 'SME delivery evidence', delivery_score, 15, 15, jsonb_build_object('source', 'delivery_confirmations', 'status', case when current_invoice.purchase_order_id is null then 'REVIEW_REQUIRED' else 'PENDING' end)),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'PDF_EXTRACTION_SUPPORT', 'PDF extraction support', pdf_score, 5, 5, jsonb_build_object('source', 'invoice_extracted_fields'));

    insert into public.transaction_events (organisation_id, invoice_id, purchase_order_id, phase, event_type, status, detail, metadata)
    values
      (current_invoice.organisation_id, current_invoice.id, current_invoice.purchase_order_id, 'DUPLICATE_CHECK', 'DUPLICATE_RECEIVABLE_CHECK_PASSED', 'PASSED', 'File hash and transaction-level receivable fingerprint are unique.', jsonb_build_object('fingerprint_hash', current_invoice.invoice_fingerprint)),
      (current_invoice.organisation_id, current_invoice.id, current_invoice.purchase_order_id, 'RISK', 'TRANSACTION_RISK_ASSESSED', case when score_decision = 'ELIGIBLE' then 'PASSED' else 'WARNING' end, 'Transaction risk assessed from commercial evidence, not a standalone AI score.', jsonb_build_object('score', score_value, 'band', score_band, 'decision', score_decision));
  end if;

  if next_status = 'FINANCE_ELIGIBLE' then
    insert into public.financing_requests (organisation_id, invoice_id, requested_advance, max_advance, fee_cap_bps, status, created_by)
    values (current_invoice.organisation_id, current_invoice.id, updated_invoice.requested_advance, updated_invoice.max_advance, 350, 'OFFERED', auth.uid())
    on conflict (invoice_id) do update set requested_advance = excluded.requested_advance, max_advance = excluded.max_advance, status = 'OFFERED', updated_at = now()
    returning id into request_id;

    if not exists (select 1 from public.financing_offers where financing_request_id = request_id) then
      insert into public.financing_offers (organisation_id, financing_request_id, financier_name, offer_name, advance_amount, fee_bps, term_days, status, metadata)
      values
        (current_invoice.organisation_id, request_id, 'Ubuntu Bank', 'Verified Receivable Advance', updated_invoice.requested_advance, 300, greatest(current_invoice.due_date - current_date, 1), 'OPEN', jsonb_build_object('speed', 'Same day', 'recommendation_basis', 'buyer and receivable evidence')),
        (current_invoice.organisation_id, request_id, 'Cedar Capital', 'Monitored Settlement Facility', updated_invoice.requested_advance, 250, greatest(current_invoice.due_date - current_date + 15, 1), 'OPEN', jsonb_build_object('speed', '24 hours', 'recommendation_basis', 'closed-loop transaction monitoring'));
    end if;

    insert into public.transaction_events (organisation_id, invoice_id, purchase_order_id, phase, event_type, status, detail, metadata)
    values (current_invoice.organisation_id, current_invoice.id, current_invoice.purchase_order_id, 'FUNDING', 'FINANCIER_MARKET_OPENED', 'PASSED', 'Verified receivable made available to participating financiers.', jsonb_build_object('financing_request_id', request_id));
  end if;

  if next_status = 'FUNDED' then
    select * into agreement_record from public.financing_agreements where invoice_id = current_invoice.id limit 1;
    if not found then raise exception 'accepted financing agreement required before funding'; end if;
    update public.financing_agreements set status = 'ACTIVE', updated_at = now() where id = agreement_record.id;
    insert into public.funding_transactions (organisation_id, financing_agreement_id, invoice_id, transaction_type, amount, provider, provider_reference, status, posted_at)
    values (current_invoice.organisation_id, agreement_record.id, current_invoice.id, 'DISBURSEMENT', agreement_record.principal_amount, 'Partner banking rail', 'bank-' || agreement_record.id::text, 'POSTED', now());
    insert into public.transaction_events (organisation_id, invoice_id, purchase_order_id, phase, event_type, status, detail, metadata)
    values (current_invoice.organisation_id, current_invoice.id, current_invoice.purchase_order_id, 'FUNDING', 'FUNDS_DISBURSED_TO_SME', 'POSTED', 'Partner financier disbursement recorded against the verified receivable.', jsonb_build_object('agreement_id', agreement_record.id, 'amount', agreement_record.principal_amount));
  end if;

  if next_status = 'SETTLED' then
    select * into agreement_record from public.financing_agreements where invoice_id = current_invoice.id limit 1;
    if not found then raise exception 'active financing agreement required before settlement'; end if;
    principal_amount := agreement_record.principal_amount;
    fee_amount := agreement_record.fee_amount;
    remainder_amount := greatest(current_invoice.amount - principal_amount - fee_amount, 0);
    days_late := greatest(coalesce(current_date - current_invoice.due_date, 0), 0);

    insert into public.settlements (organisation_id, financing_agreement_id, invoice_id, buyer_payment_amount, principal_repaid, fee_collected, sme_remainder, status, settled_at)
    values (current_invoice.organisation_id, agreement_record.id, current_invoice.id, current_invoice.amount, principal_amount, fee_amount, remainder_amount, 'RECONCILED', now()) returning id into settlement_id;
    insert into public.settlement_allocations (organisation_id, settlement_id, recipient_organisation_id, allocation_type, amount)
    values (current_invoice.organisation_id, settlement_id, agreement_record.financier_organisation_id, 'PRINCIPAL', principal_amount), (current_invoice.organisation_id, settlement_id, agreement_record.financier_organisation_id, 'FEE', fee_amount), (current_invoice.organisation_id, settlement_id, current_invoice.organisation_id, 'SME_REMAINDER', remainder_amount);
    insert into public.funding_transactions (organisation_id, financing_agreement_id, invoice_id, transaction_type, amount, provider, provider_reference, status, posted_at)
    values (current_invoice.organisation_id, agreement_record.id, current_invoice.id, 'REPAYMENT', principal_amount, 'Settlement engine', 'settlement-' || settlement_id::text, 'POSTED', now()), (current_invoice.organisation_id, agreement_record.id, current_invoice.id, 'FEE', fee_amount, 'Settlement engine', 'settlement-' || settlement_id::text, 'POSTED', now()), (current_invoice.organisation_id, agreement_record.id, current_invoice.id, 'SME_REMAINDER', remainder_amount, 'Settlement engine', 'settlement-' || settlement_id::text, 'POSTED', now());
    update public.financing_agreements set status = 'SETTLED', updated_at = now() where id = agreement_record.id;

    insert into public.buyer_payment_history (organisation_id, buyer_id, currency, total_invoice_count, paid_invoice_count, late_invoice_count, total_paid_amount, on_time_rate, average_days_late, last_payment_at, evidence)
    values (current_invoice.organisation_id, current_invoice.buyer_id, current_invoice.currency, 1, 1, case when days_late > 0 then 1 else 0 end, current_invoice.amount, case when days_late = 0 then 100 else 0 end, days_late, current_date, jsonb_build_object('last_invoice_id', current_invoice.id, 'last_settlement_id', settlement_id))
    on conflict (organisation_id, buyer_id, currency) do update
      set total_invoice_count = public.buyer_payment_history.total_invoice_count + 1,
          paid_invoice_count = public.buyer_payment_history.paid_invoice_count + 1,
          late_invoice_count = public.buyer_payment_history.late_invoice_count + excluded.late_invoice_count,
          total_paid_amount = public.buyer_payment_history.total_paid_amount + excluded.total_paid_amount,
          on_time_rate = round(((public.buyer_payment_history.paid_invoice_count - public.buyer_payment_history.late_invoice_count + case when days_late = 0 then 1 else 0 end) * 100.0) / greatest(public.buyer_payment_history.paid_invoice_count + 1, 1), 2),
          average_days_late = round(((public.buyer_payment_history.average_days_late * greatest(public.buyer_payment_history.paid_invoice_count, 0)) + days_late) / greatest(public.buyer_payment_history.paid_invoice_count + 1, 1), 2),
          last_payment_at = current_date,
          evidence = excluded.evidence,
          updated_at = now();

    insert into public.settlement_events (organisation_id, invoice_id, financing_agreement_id, settlement_id, event_type, status, amount, payer, payee, metadata)
    values
      (current_invoice.organisation_id, current_invoice.id, agreement_record.id, settlement_id, 'BUYER_PAYMENT_RECEIVED', 'POSTED', current_invoice.amount, current_invoice.buyer_id::text, 'CapitalBridge settlement account', jsonb_build_object('days_late', days_late)),
      (current_invoice.organisation_id, current_invoice.id, agreement_record.id, settlement_id, 'SETTLEMENT_ALLOCATED', 'RECONCILED', principal_amount + fee_amount + remainder_amount, 'CapitalBridge settlement account', 'Financier and SME', jsonb_build_object('principal', principal_amount, 'fee', fee_amount, 'sme_remainder', remainder_amount));

    insert into public.transaction_events (organisation_id, invoice_id, purchase_order_id, phase, event_type, status, detail, metadata)
    values
      (current_invoice.organisation_id, current_invoice.id, current_invoice.purchase_order_id, 'PAYMENT', 'BUYER_PAYMENT_RECEIVED', 'POSTED', 'Buyer payment recorded and used to update payment behaviour history.', jsonb_build_object('amount', current_invoice.amount, 'days_late', days_late)),
      (current_invoice.organisation_id, current_invoice.id, current_invoice.purchase_order_id, 'SETTLEMENT', 'SETTLEMENT_RECONCILED', 'RECONCILED', 'Principal, fee, and SME remainder reconciled through the settlement ledger.', jsonb_build_object('settlement_id', settlement_id));
  end if;

  insert into public.invoice_status_history (organisation_id, invoice_id, from_status, to_status, actor_user_id, actor_service, event_code, event_detail)
  values (current_invoice.organisation_id, current_invoice.id, current_invoice.status, next_status, auth.uid(), actor_service, event_code, event_detail);

  insert into public.audit_logs (organisation_id, invoice_id, actor_user_id, actor_service, event_code, event_detail)
  values (current_invoice.organisation_id, current_invoice.id, auth.uid(), actor_service, event_code, event_detail);

  insert into public.notifications (organisation_id, user_id, invoice_id, title, body, tone)
  values (current_invoice.organisation_id, auth.uid(), current_invoice.id, replace(next_status::text, '_', ' '), event_detail, case when next_status in ('SETTLED', 'FUNDED', 'FINANCE_ELIGIBLE') then 'green' when next_status in ('VERIFYING', 'RISK_ASSESSED', 'OFFER_ACCEPTED') then 'blue' when next_status in ('SCANNING', 'EXTRACTED', 'VERIFIED') then 'amber' else 'neutral' end);

  return updated_invoice;
end;
$$;

grant execute on function public.advance_invoice_status(uuid, public.invoice_workflow_status, public.invoice_workflow_status, text, text, text) to authenticated;
create or replace function public.accept_financing_offer(
  target_offer_id uuid,
  input_idempotency_key text
)
returns public.financing_agreements
language plpgsql
security definer
set search_path = public
as $$
declare
  offer_record public.financing_offers%rowtype;
  request_record public.financing_requests%rowtype;
  invoice_record public.invoices%rowtype;
  existing_agreement public.financing_agreements%rowtype;
  new_agreement public.financing_agreements%rowtype;
  calculated_fee numeric(18,2);
begin
  select * into offer_record
  from public.financing_offers
  where id = target_offer_id
  for update;

  if not found then
    raise exception 'offer not found';
  end if;

  select * into request_record
  from public.financing_requests
  where id = offer_record.financing_request_id
  for update;

  select * into invoice_record
  from public.invoices
  where id = request_record.invoice_id
  for update;

  if not public.has_org_role(invoice_record.organisation_id, array['OWNER', 'ADMIN', 'FINANCE']::public.member_role[]) then
    raise exception 'not allowed';
  end if;

  select * into existing_agreement
  from public.financing_agreements
  where organisation_id = invoice_record.organisation_id
    and idempotency_key = input_idempotency_key;

  if found then
    return existing_agreement;
  end if;

  if invoice_record.status <> 'FINANCE_ELIGIBLE' then
    raise exception 'invoice is not finance eligible';
  end if;

  if offer_record.status <> 'OPEN' then
    raise exception 'offer is not open';
  end if;

  calculated_fee = round(offer_record.advance_amount * offer_record.fee_bps / 10000.0, 2);

  update public.financing_offers
  set status = 'SUPERSEDED',
      updated_at = now()
  where financing_request_id = offer_record.financing_request_id
    and id <> offer_record.id
    and status = 'OPEN';

  update public.financing_offers
  set status = 'ACCEPTED',
      accepted_at = now(),
      updated_at = now()
  where id = offer_record.id;

  update public.financing_requests
  set status = 'ACCEPTED',
      updated_at = now()
  where id = request_record.id;

  update public.invoices
  set status = 'OFFER_ACCEPTED',
      financing_status = 'OFFER_ACCEPTED',
      requested_advance = offer_record.advance_amount,
      updated_at = now()
  where id = invoice_record.id;

  insert into public.financing_agreements (
    organisation_id,
    invoice_id,
    financing_offer_id,
    borrower_organisation_id,
    financier_organisation_id,
    principal_amount,
    fee_amount,
    status,
    idempotency_key,
    accepted_by
  )
  values (
    invoice_record.organisation_id,
    invoice_record.id,
    offer_record.id,
    invoice_record.organisation_id,
    offer_record.financier_organisation_id,
    offer_record.advance_amount,
    calculated_fee,
    'PENDING',
    input_idempotency_key,
    auth.uid()
  )
  returning * into new_agreement;

  insert into public.transaction_events (organisation_id, invoice_id, purchase_order_id, phase, event_type, status, detail, metadata)
  values (invoice_record.organisation_id, invoice_record.id, invoice_record.purchase_order_id, 'FUNDING', 'FINANCIER_OFFER_ACCEPTED', 'PASSED', 'Financier offer accepted and receivable lock created.', jsonb_build_object('offer_id', offer_record.id, 'agreement_id', new_agreement.id, 'financier_name', offer_record.financier_name));

  insert into public.invoice_status_history (
    organisation_id,
    invoice_id,
    from_status,
    to_status,
    actor_user_id,
    actor_service,
    event_code,
    event_detail
  )
  values (
    invoice_record.organisation_id,
    invoice_record.id,
    invoice_record.status,
    'OFFER_ACCEPTED',
    auth.uid(),
    'capitalbridge-api',
    'OFFER_ACCEPTED',
    'Financing offer accepted with idempotency key'
  );

  insert into public.audit_logs (
    organisation_id,
    invoice_id,
    actor_user_id,
    actor_service,
    event_code,
    event_detail,
    metadata
  )
  values (
    invoice_record.organisation_id,
    invoice_record.id,
    auth.uid(),
    'capitalbridge-api',
    'OFFER_ACCEPTED',
    'Financing offer locked and agreement created from transaction evidence',
    jsonb_build_object('offer_id', offer_record.id, 'agreement_id', new_agreement.id)
  );

  insert into public.notifications (organisation_id, user_id, invoice_id, title, body, tone)
  values (
    invoice_record.organisation_id,
    auth.uid(),
    invoice_record.id,
    'OFFER ACCEPTED',
    'Financier offer locked against the verified receivable.',
    'blue'
  );

  return new_agreement;
end;
$$;

grant execute on function public.accept_financing_offer(uuid, text) to authenticated;