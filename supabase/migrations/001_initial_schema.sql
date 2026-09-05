-- CapitalBridge initial Supabase schema.
-- The Expo app displays workflow state; these tables and RPCs are the authority.

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'invoice_workflow_status') then
    create type public.invoice_workflow_status as enum (
      'UPLOADED',
      'SCANNING',
      'EXTRACTED',
      'VERIFYING',
      'VERIFIED',
      'RISK_ASSESSED',
      'FINANCE_ELIGIBLE',
      'OFFER_ACCEPTED',
      'FUNDED',
      'SETTLED'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'verification_status') then
    create type public.verification_status as enum (
      'UNVERIFIED',
      'PENDING',
      'VERIFIED',
      'PARTIALLY_VERIFIED',
      'FAILED',
      'DISPUTED'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'financing_status') then
    create type public.financing_status as enum (
      'NOT_FINANCED',
      'ELIGIBLE',
      'OFFER_ACCEPTED',
      'ACTIVE',
      'SETTLED'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'organisation_type') then
    create type public.organisation_type as enum ('SME', 'BUYER', 'FINANCIER', 'ADMIN');
  end if;

  if not exists (select 1 from pg_type where typname = 'member_role') then
    create type public.member_role as enum (
      'OWNER',
      'ADMIN',
      'FINANCE',
      'OPERATIONS',
      'VIEWER',
      'BUYER_APPROVER',
      'FINANCIER_ANALYST'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'job_status') then
    create type public.job_status as enum ('QUEUED', 'RUNNING', 'PASSED', 'FAILED', 'REVIEW_REQUIRED');
  end if;

  if not exists (select 1 from pg_type where typname = 'offer_status') then
    create type public.offer_status as enum ('DRAFT', 'OPEN', 'ACCEPTED', 'EXPIRED', 'WITHDRAWN', 'DECLINED', 'SUPERSEDED');
  end if;

  if not exists (select 1 from pg_type where typname = 'agreement_status') then
    create type public.agreement_status as enum ('PENDING', 'ACTIVE', 'DEFAULTED', 'SETTLED', 'CANCELLED');
  end if;
end $$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.organisations (
  id uuid primary key default gen_random_uuid(),
  legal_name text not null,
  trading_name text,
  organisation_type public.organisation_type not null default 'SME',
  registration_number text,
  tax_number text,
  country_code char(2) not null default 'ZA',
  kyc_status text not null default 'PENDING' check (kyc_status in ('PENDING', 'VERIFIED', 'REJECTED', 'EXPIRED')),
  risk_tier text not null default 'UNRATED' check (risk_tier in ('UNRATED', 'LOW', 'MEDIUM', 'HIGH')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (country_code, registration_number)
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  default_organisation_id uuid references public.organisations(id),
  email text not null,
  full_name text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organisation_members (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.member_role not null default 'VIEWER',
  status text not null default 'ACTIVE' check (status in ('INVITED', 'ACTIVE', 'SUSPENDED', 'REMOVED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, user_id)
);

create table public.business_profiles (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  industry text,
  annual_revenue numeric(18,2),
  average_invoice_value numeric(18,2),
  bank_account_fingerprint text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.buyers (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  linked_organisation_id uuid references public.organisations(id),
  legal_name text not null,
  registration_number text,
  tax_number text,
  erp_reference text,
  payment_history jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  linked_organisation_id uuid references public.organisations(id),
  legal_name text not null,
  registration_number text,
  tax_number text,
  verified_bank_fingerprint text,
  verified_domain text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  buyer_id uuid references public.buyers(id),
  supplier_id uuid references public.suppliers(id),
  po_number text not null,
  currency char(3) not null default 'ZAR',
  amount numeric(18,2) not null check (amount >= 0),
  status text not null default 'OPEN' check (status in ('OPEN', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CANCELLED', 'CLOSED')),
  erp_source text,
  erp_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, po_number)
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  buyer_id uuid references public.buyers(id),
  supplier_id uuid references public.suppliers(id),
  purchase_order_id uuid references public.purchase_orders(id),
  invoice_number text not null,
  purchase_order_number text,
  currency char(3) not null default 'ZAR',
  amount numeric(18,2) not null check (amount > 0),
  requested_advance numeric(18,2) not null default 0 check (requested_advance >= 0),
  max_advance numeric(18,2) not null default 0 check (max_advance >= 0),
  outstanding_amount numeric(18,2) not null check (outstanding_amount >= 0),
  issue_date date,
  due_date date,
  status public.invoice_workflow_status not null default 'UPLOADED',
  verification_status public.verification_status not null default 'UNVERIFIED',
  financing_status public.financing_status not null default 'NOT_FINANCED',
  file_hash text,
  invoice_fingerprint text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, invoice_number)
);

create table public.invoice_status_history (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  from_status public.invoice_workflow_status,
  to_status public.invoice_workflow_status not null,
  actor_user_id uuid references auth.users(id),
  actor_service text,
  event_code text not null,
  event_detail text not null,
  created_at timestamptz not null default now()
);

create table public.invoice_files (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  storage_bucket text not null default 'invoice-documents',
  storage_path text not null,
  original_filename text,
  sha256 text not null,
  mime_type text not null,
  byte_size bigint not null check (byte_size > 0),
  page_count integer check (page_count is null or page_count > 0),
  malware_status public.job_status not null default 'QUEUED',
  validation_status public.job_status not null default 'QUEUED',
  created_at timestamptz not null default now(),
  unique (organisation_id, sha256)
);

create table public.invoice_extracted_fields (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  invoice_file_id uuid references public.invoice_files(id) on delete set null,
  extraction_engine text not null,
  model_version text,
  schema_version text,
  confidence numeric(5,2) check (confidence between 0 and 100),
  extracted_json jsonb not null default '{}'::jsonb,
  source_page_count integer,
  trace_id text,
  created_at timestamptz not null default now()
);

create table public.invoice_fingerprints (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  file_sha256 text not null,
  perceptual_hash text,
  normalized_invoice_number text not null,
  supplier_tax_number text,
  buyer_registration_number text,
  amount numeric(18,2) not null,
  due_date date,
  fingerprint_hash text not null,
  created_at timestamptz not null default now(),
  unique (organisation_id, fingerprint_hash),
  unique (invoice_id)
);

create table public.verification_requests (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  request_type text not null check (request_type in ('ERP_PO_MATCH', 'BUYER_CONFIRMATION', 'SUPPLIER_CONFIRMATION', 'BANK_ACCOUNT_CHECK')),
  external_reference text,
  idempotency_key text not null,
  status public.job_status not null default 'QUEUED',
  requested_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, idempotency_key)
);

create table public.verification_results (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  verification_request_id uuid not null references public.verification_requests(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  result_status public.verification_status not null,
  confidence numeric(5,2) check (confidence between 0 and 100),
  mismatch_flags jsonb not null default '[]'::jsonb,
  evidence jsonb not null default '{}'::jsonb,
  signed_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.fraud_checks (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  check_type text not null,
  status public.job_status not null default 'QUEUED',
  score_delta numeric(6,2) not null default 0,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.fraud_alerts (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  fraud_check_id uuid references public.fraud_checks(id) on delete set null,
  severity text not null check (severity in ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
  alert_type text not null,
  description text not null,
  resolved_by uuid references auth.users(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.risk_assessments (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  model_version text not null,
  score numeric(5,2) not null check (score between 0 and 100),
  band text not null check (band in ('LOW', 'MEDIUM', 'HIGH', 'BLOCKED')),
  decision text not null check (decision in ('ELIGIBLE', 'MANUAL_REVIEW', 'REJECTED')),
  explanation jsonb not null default '{}'::jsonb,
  created_by_service text not null default 'risk-engine',
  created_at timestamptz not null default now()
);

create table public.risk_factors (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  risk_assessment_id uuid not null references public.risk_assessments(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  code text not null,
  label text not null,
  earned_score numeric(8,2) not null,
  max_score numeric(8,2) not null,
  weight numeric(8,2) not null,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.financing_requests (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  requested_advance numeric(18,2) not null check (requested_advance > 0),
  max_advance numeric(18,2) not null check (max_advance >= requested_advance),
  fee_cap_bps integer check (fee_cap_bps is null or fee_cap_bps >= 0),
  status text not null default 'REQUESTED' check (status in ('REQUESTED', 'OFFERED', 'ACCEPTED', 'CANCELLED', 'DECLINED')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (invoice_id)
);

create table public.financing_offers (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  financing_request_id uuid not null references public.financing_requests(id) on delete cascade,
  financier_organisation_id uuid references public.organisations(id),
  offer_name text not null,
  advance_amount numeric(18,2) not null check (advance_amount > 0),
  fee_bps integer not null check (fee_bps >= 0),
  term_days integer not null check (term_days > 0),
  status public.offer_status not null default 'OPEN',
  expires_at timestamptz,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.financing_agreements (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  financing_offer_id uuid not null references public.financing_offers(id) on delete restrict,
  borrower_organisation_id uuid not null references public.organisations(id),
  financier_organisation_id uuid references public.organisations(id),
  principal_amount numeric(18,2) not null check (principal_amount > 0),
  fee_amount numeric(18,2) not null check (fee_amount >= 0),
  status public.agreement_status not null default 'PENDING',
  contract_hash text,
  idempotency_key text not null,
  accepted_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, idempotency_key),
  unique (invoice_id)
);

create table public.funding_transactions (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  financing_agreement_id uuid not null references public.financing_agreements(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  transaction_type text not null check (transaction_type in ('DISBURSEMENT', 'REPAYMENT', 'FEE', 'SME_REMAINDER', 'REVERSAL')),
  amount numeric(18,2) not null check (amount >= 0),
  provider text,
  provider_reference text,
  status text not null default 'PENDING' check (status in ('PENDING', 'PROCESSING', 'POSTED', 'FAILED', 'REVERSED')),
  posted_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.settlements (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  financing_agreement_id uuid not null references public.financing_agreements(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  buyer_payment_amount numeric(18,2) not null check (buyer_payment_amount >= 0),
  principal_repaid numeric(18,2) not null default 0 check (principal_repaid >= 0),
  fee_collected numeric(18,2) not null default 0 check (fee_collected >= 0),
  sme_remainder numeric(18,2) not null default 0 check (sme_remainder >= 0),
  status text not null default 'PENDING' check (status in ('PENDING', 'ALLOCATED', 'RECONCILED', 'DISPUTED')),
  settled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.settlement_allocations (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  settlement_id uuid not null references public.settlements(id) on delete cascade,
  recipient_organisation_id uuid references public.organisations(id),
  allocation_type text not null check (allocation_type in ('PRINCIPAL', 'FEE', 'SME_REMAINDER')),
  amount numeric(18,2) not null check (amount >= 0),
  created_at timestamptz not null default now()
);

create table public.integrations (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  provider text not null,
  integration_type text not null check (integration_type in ('ERP', 'BANKING', 'EMAIL', 'STORAGE', 'KYC')),
  status text not null default 'DISCONNECTED' check (status in ('DISCONNECTED', 'CONNECTED', 'ERROR', 'SUSPENDED')),
  encrypted_secret_ref text,
  last_synced_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.integration_events (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  integration_id uuid not null references public.integrations(id) on delete cascade,
  event_type text not null,
  status public.job_status not null default 'QUEUED',
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  invoice_id uuid references public.invoices(id) on delete cascade,
  title text not null,
  body text not null,
  tone text not null default 'neutral' check (tone in ('blue', 'green', 'amber', 'red', 'neutral', 'slate')),
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.consents (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  consent_type text not null,
  status text not null default 'GRANTED' check (status in ('GRANTED', 'REVOKED', 'EXPIRED')),
  purpose text not null,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
);

create table public.data_access_logs (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  actor_user_id uuid references auth.users(id),
  target_table text not null,
  target_id uuid,
  action text not null,
  reason text,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  invoice_id uuid references public.invoices(id) on delete cascade,
  actor_user_id uuid references auth.users(id),
  actor_service text,
  event_code text not null,
  event_detail text not null,
  ip_address inet,
  user_agent text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.idempotency_keys (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  key text not null,
  scope text not null,
  request_hash text not null,
  response_json jsonb,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (organisation_id, key, scope)
);

create index organisations_type_idx on public.organisations (organisation_type);
create index organisation_members_user_idx on public.organisation_members (user_id);
create index invoices_org_status_idx on public.invoices (organisation_id, status);
create index invoices_hash_idx on public.invoices (file_hash);
create index invoice_files_invoice_idx on public.invoice_files (invoice_id);
create index invoice_fingerprints_hash_idx on public.invoice_fingerprints (fingerprint_hash);
create index verification_requests_invoice_idx on public.verification_requests (invoice_id);
create index fraud_alerts_invoice_idx on public.fraud_alerts (invoice_id, severity);
create index risk_assessments_invoice_idx on public.risk_assessments (invoice_id, created_at desc);
create index financing_offers_request_idx on public.financing_offers (financing_request_id, status);
create index funding_transactions_agreement_idx on public.funding_transactions (financing_agreement_id);
create index audit_logs_org_created_idx on public.audit_logs (organisation_id, created_at desc);
create index notifications_user_created_idx on public.notifications (user_id, created_at desc);

create or replace function public.is_org_member(target_organisation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organisation_members member
    where member.organisation_id = target_organisation_id
      and member.user_id = auth.uid()
      and member.status = 'ACTIVE'
  );
$$;

create or replace function public.has_org_role(target_organisation_id uuid, allowed_roles public.member_role[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organisation_members member
    where member.organisation_id = target_organisation_id
      and member.user_id = auth.uid()
      and member.status = 'ACTIVE'
      and member.role = any (allowed_roles)
  );
$$;

create or replace function public.invoice_status_rank(status_value public.invoice_workflow_status)
returns integer
language sql
immutable
as $$
  select case status_value
    when 'UPLOADED' then 1
    when 'SCANNING' then 2
    when 'EXTRACTED' then 3
    when 'VERIFYING' then 4
    when 'VERIFIED' then 5
    when 'RISK_ASSESSED' then 6
    when 'FINANCE_ELIGIBLE' then 7
    when 'OFFER_ACCEPTED' then 8
    when 'FUNDED' then 9
    when 'SETTLED' then 10
  end;
$$;

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
begin
  select *
  into current_invoice
  from public.invoices
  where id = target_invoice_id
  for update;

  if not found then
    raise exception 'invoice not found';
  end if;

  if not public.is_org_member(current_invoice.organisation_id) then
    raise exception 'not allowed';
  end if;

  if current_invoice.status <> expected_status then
    raise exception 'invalid invoice state: expected %, found %', expected_status, current_invoice.status;
  end if;

  if public.invoice_status_rank(next_status) <> public.invoice_status_rank(expected_status) + 1 then
    raise exception 'invalid transition from % to %', expected_status, next_status;
  end if;

  update public.invoices
  set status = next_status,
      verification_status = case
        when next_status in ('VERIFYING') then 'PENDING'::public.verification_status
        when next_status in ('VERIFIED', 'RISK_ASSESSED', 'FINANCE_ELIGIBLE', 'OFFER_ACCEPTED', 'FUNDED', 'SETTLED') then 'VERIFIED'::public.verification_status
        else verification_status
      end,
      financing_status = case
        when next_status = 'FINANCE_ELIGIBLE' then 'ELIGIBLE'::public.financing_status
        when next_status = 'OFFER_ACCEPTED' then 'OFFER_ACCEPTED'::public.financing_status
        when next_status = 'FUNDED' then 'ACTIVE'::public.financing_status
        when next_status = 'SETTLED' then 'SETTLED'::public.financing_status
        else financing_status
      end,
      updated_at = now()
  where id = target_invoice_id
  returning * into updated_invoice;

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
    current_invoice.organisation_id,
    current_invoice.id,
    current_invoice.status,
    next_status,
    auth.uid(),
    actor_service,
    event_code,
    event_detail
  );

  insert into public.audit_logs (
    organisation_id,
    invoice_id,
    actor_user_id,
    actor_service,
    event_code,
    event_detail
  )
  values (
    current_invoice.organisation_id,
    current_invoice.id,
    auth.uid(),
    actor_service,
    event_code,
    event_detail
  );

  return updated_invoice;
end;
$$;

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
  select *
  into offer_record
  from public.financing_offers
  where id = target_offer_id
  for update;

  if not found then
    raise exception 'offer not found';
  end if;

  select *
  into request_record
  from public.financing_requests
  where id = offer_record.financing_request_id
  for update;

  select *
  into invoice_record
  from public.invoices
  where id = request_record.invoice_id
  for update;

  if not public.has_org_role(invoice_record.organisation_id, array['OWNER', 'ADMIN', 'FINANCE']::public.member_role[]) then
    raise exception 'not allowed';
  end if;

  select *
  into existing_agreement
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
    'Financing offer locked and agreement created',
    jsonb_build_object('offer_id', offer_record.id, 'agreement_id', new_agreement.id)
  );

  return new_agreement;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'organisations',
    'profiles',
    'organisation_members',
    'business_profiles',
    'buyers',
    'suppliers',
    'purchase_orders',
    'invoices',
    'verification_requests',
    'financing_requests',
    'financing_offers',
    'financing_agreements',
    'settlements',
    'integrations'
  ]
  loop
    execute format('create trigger %I before update on public.%I for each row execute function public.set_updated_at()', 'set_' || table_name || '_updated_at', table_name);
  end loop;
end $$;

alter table public.organisations enable row level security;
alter table public.profiles enable row level security;
alter table public.organisation_members enable row level security;
alter table public.business_profiles enable row level security;
alter table public.buyers enable row level security;
alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_status_history enable row level security;
alter table public.invoice_files enable row level security;
alter table public.invoice_extracted_fields enable row level security;
alter table public.invoice_fingerprints enable row level security;
alter table public.verification_requests enable row level security;
alter table public.verification_results enable row level security;
alter table public.fraud_checks enable row level security;
alter table public.fraud_alerts enable row level security;
alter table public.risk_assessments enable row level security;
alter table public.risk_factors enable row level security;
alter table public.financing_requests enable row level security;
alter table public.financing_offers enable row level security;
alter table public.financing_agreements enable row level security;
alter table public.funding_transactions enable row level security;
alter table public.settlements enable row level security;
alter table public.settlement_allocations enable row level security;
alter table public.integrations enable row level security;
alter table public.integration_events enable row level security;
alter table public.notifications enable row level security;
alter table public.consents enable row level security;
alter table public.data_access_logs enable row level security;
alter table public.audit_logs enable row level security;
alter table public.idempotency_keys enable row level security;

create policy profiles_read_own on public.profiles
  for select using (id = auth.uid());

create policy profiles_insert_own on public.profiles
  for insert with check (id = auth.uid());

create policy profiles_update_own on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

create policy organisations_read_member on public.organisations
  for select using (public.is_org_member(id));

create policy organisations_read_creator on public.organisations
  for select using (created_by = auth.uid());

create policy organisations_insert_creator on public.organisations
  for insert with check (created_by = auth.uid());

create policy organisations_update_admin on public.organisations
  for update using (public.has_org_role(id, array['OWNER', 'ADMIN']::public.member_role[]))
  with check (public.has_org_role(id, array['OWNER', 'ADMIN']::public.member_role[]));

create policy organisation_members_read_member on public.organisation_members
  for select using (public.is_org_member(organisation_id));

create policy organisation_members_manage_admin on public.organisation_members
  for all using (public.has_org_role(organisation_id, array['OWNER', 'ADMIN']::public.member_role[]))
  with check (public.has_org_role(organisation_id, array['OWNER', 'ADMIN']::public.member_role[]));

create policy organisation_members_insert_initial_owner on public.organisation_members
  for insert with check (
    user_id = auth.uid()
    and role = 'OWNER'
    and exists (
      select 1
      from public.organisations org
      where org.id = organisation_id
        and org.created_by = auth.uid()
    )
  );

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'business_profiles',
    'buyers',
    'suppliers',
    'purchase_orders',
    'invoices',
    'verification_requests',
    'financing_requests',
    'financing_offers',
    'financing_agreements',
    'settlements',
    'integrations',
    'notifications',
    'consents',
    'idempotency_keys'
  ]
  loop
    execute format('create policy %I on public.%I for select using (public.is_org_member(organisation_id))', table_name || '_read_member', table_name);
    execute format('create policy %I on public.%I for insert with check (public.is_org_member(organisation_id))', table_name || '_insert_member', table_name);
    execute format('create policy %I on public.%I for update using (public.has_org_role(organisation_id, array[''OWNER'', ''ADMIN'', ''FINANCE'', ''OPERATIONS'']::public.member_role[])) with check (public.has_org_role(organisation_id, array[''OWNER'', ''ADMIN'', ''FINANCE'', ''OPERATIONS'']::public.member_role[]))', table_name || '_update_operator', table_name);
  end loop;
end $$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'invoice_status_history',
    'invoice_files',
    'invoice_extracted_fields',
    'invoice_fingerprints',
    'verification_results',
    'fraud_checks',
    'fraud_alerts',
    'risk_assessments',
    'risk_factors',
    'funding_transactions',
    'settlement_allocations',
    'integration_events',
    'data_access_logs',
    'audit_logs'
  ]
  loop
    execute format('create policy %I on public.%I for select using (public.is_org_member(organisation_id))', table_name || '_read_member', table_name);
    execute format('create policy %I on public.%I for insert with check (public.is_org_member(organisation_id))', table_name || '_insert_member', table_name);
  end loop;
end $$;

create policy financing_offers_read_financier on public.financing_offers
  for select using (
    financier_organisation_id is not null
    and public.is_org_member(financier_organisation_id)
  );

create policy financing_offers_update_financier on public.financing_offers
  for update using (
    financier_organisation_id is not null
    and public.has_org_role(financier_organisation_id, array['OWNER', 'ADMIN', 'FINANCIER_ANALYST']::public.member_role[])
  )
  with check (
    financier_organisation_id is not null
    and public.has_org_role(financier_organisation_id, array['OWNER', 'ADMIN', 'FINANCIER_ANALYST']::public.member_role[])
  );

create policy financing_agreements_read_financier on public.financing_agreements
  for select using (
    financier_organisation_id is not null
    and public.is_org_member(financier_organisation_id)
  );

create policy funding_transactions_read_financier on public.funding_transactions
  for select using (
    exists (
      select 1
      from public.financing_agreements agreement
      where agreement.id = funding_transactions.financing_agreement_id
        and agreement.financier_organisation_id is not null
        and public.is_org_member(agreement.financier_organisation_id)
    )
  );

grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;
grant insert, update on
  public.profiles,
  public.organisations,
  public.organisation_members,
  public.business_profiles,
  public.buyers,
  public.suppliers,
  public.purchase_orders,
  public.invoices,
  public.verification_requests,
  public.financing_requests,
  public.financing_offers,
  public.settlements,
  public.integrations,
  public.notifications,
  public.consents,
  public.idempotency_keys
to authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to authenticated;
grant execute on function public.advance_invoice_status(uuid, public.invoice_workflow_status, public.invoice_workflow_status, text, text, text) to authenticated;
grant execute on function public.accept_financing_offer(uuid, text) to authenticated;

revoke update (status, verification_status, financing_status, amount, requested_advance, max_advance, outstanding_amount, file_hash, invoice_fingerprint)
on public.invoices
from authenticated;

create or replace function public.path_org_id(object_name text)
returns uuid
language plpgsql
immutable
as $$
begin
  return split_part(object_name, '/', 1)::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

insert into storage.buckets (id, name, public)
values ('invoice-documents', 'invoice-documents', false)
on conflict (id) do update set public = false;

create policy invoice_documents_read_member on storage.objects
  for select using (
    bucket_id = 'invoice-documents'
    and public.is_org_member(public.path_org_id(name))
  );

create policy invoice_documents_insert_member on storage.objects
  for insert with check (
    bucket_id = 'invoice-documents'
    and public.is_org_member(public.path_org_id(name))
  );
