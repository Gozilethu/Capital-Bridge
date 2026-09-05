-- Real uploads, onboarding cleanup, scan plans, and duplicate protection.

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text not null,
  monthly_price_cents integer not null default 0 check (monthly_price_cents >= 0),
  currency char(3) not null default 'ZAR',
  scan_limit integer not null check (scan_limit > 0),
  benefits text[] not null default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.organisation_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'PAST_DUE', 'CANCELLED')),
  current_period_start date not null default date_trunc('month', now())::date,
  current_period_end date not null default (date_trunc('month', now())::date + interval '1 month - 1 day')::date,
  payment_provider text not null default 'manual-sandbox',
  provider_subscription_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists organisation_active_subscription_idx
on public.organisation_subscriptions (organisation_id)
where status = 'ACTIVE';

create table if not exists public.invoice_scan_usage (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  scans_used integer not null default 0 check (scans_used >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, period_start)
);

create table if not exists public.payment_checkout_sessions (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id),
  amount_cents integer not null check (amount_cents >= 0),
  currency char(3) not null default 'ZAR',
  provider text not null default 'manual-sandbox',
  provider_reference text,
  status text not null default 'COMPLETED' check (status in ('PENDING', 'COMPLETED', 'FAILED', 'CANCELLED')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.global_invoice_registry (
  id uuid primary key default gen_random_uuid(),
  first_organisation_id uuid not null references public.organisations(id) on delete cascade,
  first_invoice_id uuid references public.invoices(id) on delete set null,
  file_sha256 text not null unique,
  fingerprint_hash text not null unique,
  created_at timestamptz not null default now()
);

alter table public.subscription_plans enable row level security;
alter table public.organisation_subscriptions enable row level security;
alter table public.invoice_scan_usage enable row level security;
alter table public.payment_checkout_sessions enable row level security;
alter table public.global_invoice_registry enable row level security;

drop policy if exists subscription_plans_read on public.subscription_plans;
create policy subscription_plans_read on public.subscription_plans for select using (active = true);

drop policy if exists organisation_subscriptions_read_member on public.organisation_subscriptions;
create policy organisation_subscriptions_read_member on public.organisation_subscriptions for select using (public.is_org_member(organisation_id));

drop policy if exists invoice_scan_usage_read_member on public.invoice_scan_usage;
create policy invoice_scan_usage_read_member on public.invoice_scan_usage for select using (public.is_org_member(organisation_id));

drop policy if exists payment_checkout_sessions_read_member on public.payment_checkout_sessions;
create policy payment_checkout_sessions_read_member on public.payment_checkout_sessions for select using (public.is_org_member(organisation_id));

insert into public.subscription_plans (code, name, description, monthly_price_cents, currency, scan_limit, benefits)
values
  ('free', 'Free Scanner', '10 invoice scans per month for a new SME workspace.', 0, 'ZAR', 10, array['10 scans per month', 'Private invoice storage', 'Duplicate invoice checks']),
  ('growth', 'Growth Scanner', 'More monthly capacity for active invoice financing teams.', 49000, 'ZAR', 100, array['100 scans per month', 'Priority scan queue', 'Duplicate and fraud checks', 'Funding offer workflow']),
  ('scale', 'Scale Finance', 'High-volume scanning and financing workflow support.', 149000, 'ZAR', 500, array['500 scans per month', 'Priority support', 'Advanced audit reporting', 'Funding and settlement workflows'])
on conflict (code) do update
set name = excluded.name,
    description = excluded.description,
    monthly_price_cents = excluded.monthly_price_cents,
    currency = excluded.currency,
    scan_limit = excluded.scan_limit,
    benefits = excluded.benefits,
    active = true,
    updated_at = now();

create or replace function public.first_active_organisation_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select member.organisation_id
  from public.organisation_members member
  where member.user_id = auth.uid()
    and member.status = 'ACTIVE'
  order by member.created_at
  limit 1;
$$;

create or replace function public.ensure_default_subscription(target_organisation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_plan_id uuid;
  subscription_id uuid;
begin
  select id into subscription_id
  from public.organisation_subscriptions
  where organisation_id = target_organisation_id and status = 'ACTIVE'
  limit 1;

  if subscription_id is not null then
    return subscription_id;
  end if;

  select id into selected_plan_id from public.subscription_plans where code = 'free' and active = true limit 1;

  if selected_plan_id is null then
    raise exception 'free scanner plan is not configured';
  end if;

  insert into public.organisation_subscriptions (organisation_id, plan_id, status, current_period_start, current_period_end, payment_provider)
  values (target_organisation_id, selected_plan_id, 'ACTIVE', date_trunc('month', now())::date, (date_trunc('month', now())::date + interval '1 month - 1 day')::date, 'manual-sandbox')
  returning id into subscription_id;

  return subscription_id;
end;
$$;

create or replace function public.get_plan_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  org_id uuid;
  plan_record public.subscription_plans%rowtype;
  used_count integer;
  period_start date := date_trunc('month', now())::date;
  period_end date := (date_trunc('month', now())::date + interval '1 month - 1 day')::date;
begin
  org_id := public.first_active_organisation_id();

  if org_id is null then
    return null;
  end if;

  perform public.ensure_default_subscription(org_id);

  select plan.* into plan_record
  from public.organisation_subscriptions subscription
  join public.subscription_plans plan on plan.id = subscription.plan_id
  where subscription.organisation_id = org_id and subscription.status = 'ACTIVE'
  order by subscription.created_at desc
  limit 1;

  insert into public.invoice_scan_usage (organisation_id, period_start, period_end, scans_used)
  values (org_id, period_start, period_end, 0)
  on conflict (organisation_id, period_start) do nothing;

  select scans_used into used_count
  from public.invoice_scan_usage usage
  where usage.organisation_id = org_id and usage.period_start = get_plan_status.period_start;

  return jsonb_build_object(
    'plan_id', plan_record.id,
    'plan_code', plan_record.code,
    'plan_name', plan_record.name,
    'monthly_price_cents', plan_record.monthly_price_cents,
    'currency', plan_record.currency,
    'scan_limit', plan_record.scan_limit,
    'scans_used', coalesce(used_count, 0),
    'scans_remaining', greatest(plan_record.scan_limit - coalesce(used_count, 0), 0),
    'period_start', period_start,
    'period_end', period_end,
    'requires_payment', coalesce(used_count, 0) >= plan_record.scan_limit and plan_record.code = 'free'
  );
end;
$$;

create or replace function public.select_subscription_plan(target_plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  org_id uuid;
  plan_record public.subscription_plans%rowtype;
  subscription_id uuid;
begin
  org_id := public.first_active_organisation_id();

  if org_id is null then
    raise exception 'organisation required';
  end if;

  if not public.has_org_role(org_id, array['OWNER', 'ADMIN', 'FINANCE']::public.member_role[]) then
    raise exception 'not allowed';
  end if;

  select * into plan_record from public.subscription_plans where id = target_plan_id and active = true;

  if not found then
    raise exception 'plan not found';
  end if;

  update public.organisation_subscriptions set status = 'CANCELLED', updated_at = now() where organisation_id = org_id and status = 'ACTIVE';

  insert into public.payment_checkout_sessions (organisation_id, plan_id, amount_cents, currency, provider, provider_reference, status, created_by)
  values (org_id, plan_record.id, plan_record.monthly_price_cents, plan_record.currency, 'manual-sandbox', 'plan-' || plan_record.code || '-' || extract(epoch from now())::bigint, 'COMPLETED', auth.uid());

  insert into public.organisation_subscriptions (organisation_id, plan_id, status, current_period_start, current_period_end, payment_provider, provider_subscription_id)
  values (org_id, plan_record.id, 'ACTIVE', date_trunc('month', now())::date, (date_trunc('month', now())::date + interval '1 month - 1 day')::date, 'manual-sandbox', 'sub-' || plan_record.code || '-' || org_id::text)
  returning id into subscription_id;

  insert into public.audit_logs (organisation_id, actor_user_id, actor_service, event_code, event_detail, metadata)
  values (org_id, auth.uid(), 'billing', 'SUBSCRIPTION_PLAN_SELECTED', 'Subscription plan selected for invoice scanning', jsonb_build_object('plan_id', plan_record.id, 'plan_code', plan_record.code));

  return jsonb_build_object('subscription_id', subscription_id, 'plan_code', plan_record.code);
end;
$$;

create or replace function public.consume_invoice_scan_quota(target_organisation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  plan_record public.subscription_plans%rowtype;
  used_count integer;
  period_start date := date_trunc('month', now())::date;
  period_end date := (date_trunc('month', now())::date + interval '1 month - 1 day')::date;
begin
  perform public.ensure_default_subscription(target_organisation_id);

  select plan.* into plan_record
  from public.organisation_subscriptions subscription
  join public.subscription_plans plan on plan.id = subscription.plan_id
  where subscription.organisation_id = target_organisation_id and subscription.status = 'ACTIVE'
  order by subscription.created_at desc
  limit 1;

  insert into public.invoice_scan_usage (organisation_id, period_start, period_end, scans_used)
  values (target_organisation_id, period_start, period_end, 0)
  on conflict (organisation_id, period_start) do nothing;

  update public.invoice_scan_usage usage
  set scans_used = scans_used + 1, updated_at = now()
  where usage.organisation_id = target_organisation_id
    and usage.period_start = consume_invoice_scan_quota.period_start
    and scans_used < plan_record.scan_limit
  returning scans_used into used_count;

  if used_count is null then
    raise exception 'Monthly scan limit reached. The free plan includes 10 invoice scans per month. Choose a paid plan to scan more invoices.';
  end if;

  return jsonb_build_object('plan_code', plan_record.code, 'scan_limit', plan_record.scan_limit, 'scans_used', used_count, 'scans_remaining', greatest(plan_record.scan_limit - used_count, 0));
end;
$$;

create or replace function public.seed_demo_workspace(target_organisation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Demo workspace seed is disabled. Upload a real invoice instead.';
end;
$$;

create or replace function public.complete_user_onboarding(input_full_name text, input_organisation_name text, input_account_type public.organisation_type default 'SME')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  user_email text := coalesce(auth.jwt() ->> 'email', '');
  workspace_id uuid;
  workspace_name text;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if nullif(trim(input_full_name), '') is null then raise exception 'full name is required'; end if;
  if nullif(trim(input_organisation_name), '') is null then raise exception 'organisation name is required'; end if;

  select member.organisation_id, org.legal_name into workspace_id, workspace_name
  from public.organisation_members member
  join public.organisations org on org.id = member.organisation_id
  where member.user_id = current_user_id and member.status = 'ACTIVE'
  order by member.created_at
  limit 1;

  if workspace_id is null then
    insert into public.organisations (legal_name, trading_name, organisation_type, country_code, kyc_status, risk_tier, created_by)
    values (trim(input_organisation_name), trim(input_organisation_name), input_account_type, 'ZA', 'PENDING', 'UNRATED', current_user_id)
    returning id, legal_name into workspace_id, workspace_name;

    insert into public.organisation_members (organisation_id, user_id, role, status)
    values (workspace_id, current_user_id, 'OWNER', 'ACTIVE')
    on conflict (organisation_id, user_id) do update set role = 'OWNER', status = 'ACTIVE', updated_at = now();
  end if;

  insert into public.profiles (id, default_organisation_id, email, full_name)
  values (current_user_id, workspace_id, user_email, trim(input_full_name))
  on conflict (id) do update set default_organisation_id = excluded.default_organisation_id, email = excluded.email, full_name = excluded.full_name, updated_at = now();

  insert into public.business_profiles (organisation_id, metadata)
  values (workspace_id, jsonb_build_object('onboarding_complete', true))
  on conflict do nothing;

  perform public.ensure_default_subscription(workspace_id);

  if not exists (
    select 1
    from public.integrations
    where organisation_id = workspace_id
      and provider = 'Invoice Check'
  ) then
    insert into public.integrations (organisation_id, provider, integration_type, status, metadata)
    values (workspace_id, 'Invoice Check', 'ERP', 'CONNECTED', jsonb_build_object('source', 'InvoiceCheck', 'local_url', 'http://localhost:7860', 'live_url', 'https://huggingface.co/spaces/decent-cow26/invoice-env'));
  end if;

  return jsonb_build_object('organisation_id', workspace_id, 'organisation_name', workspace_name, 'email', user_email);
end;
$$;

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
  fingerprint_value := encode(digest(normalized_supplier || ':' || normalized_buyer || ':' || normalized_invoice || ':' || input_amount::text || ':' || input_due_date::text, 'sha256'), 'hex');

  if exists (select 1 from public.global_invoice_registry registry where registry.file_sha256 = input_file_sha256) then
    raise exception 'This invoice file has already been submitted before.';
  end if;

  if exists (select 1 from public.global_invoice_registry registry where registry.fingerprint_hash = fingerprint_value) then
    raise exception 'An invoice with the same supplier, buyer, invoice number, amount, and due date has already been submitted before.';
  end if;

  if exists (select 1 from public.invoice_files file_row where file_row.sha256 = input_file_sha256) then
    raise exception 'This invoice file has already been submitted before.';
  end if;

  if exists (select 1 from public.invoice_fingerprints fingerprint_row where fingerprint_row.fingerprint_hash = fingerprint_value) then
    raise exception 'An invoice with matching invoice details has already been submitted before.';
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

  if nullif(trim(coalesce(input_purchase_order_number, '')), '') is not null then
    select id into po_record_id
    from public.purchase_orders
    where organisation_id = target_organisation_id and lower(po_number) = lower(trim(input_purchase_order_number))
    limit 1;

    if po_record_id is null then
      insert into public.purchase_orders (organisation_id, buyer_id, supplier_id, po_number, currency, amount, status, erp_source, erp_payload)
      values (target_organisation_id, buyer_record_id, supplier_record_id, trim(input_purchase_order_number), 'ZAR', input_amount, 'OPEN', 'Invoice Check', jsonb_build_object('created_from_upload', true))
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

  insert into public.global_invoice_registry (first_organisation_id, first_invoice_id, file_sha256, fingerprint_hash)
  values (target_organisation_id, invoice_record_id, input_file_sha256, fingerprint_value);

  insert into public.audit_logs (organisation_id, invoice_id, actor_user_id, actor_service, event_code, event_detail, metadata)
  values (target_organisation_id, invoice_record_id, auth.uid(), 'invoice-upload', 'PDF_UPLOADED', 'Real PDF invoice metadata and duplicate fingerprint stored', jsonb_build_object('file_sha256', input_file_sha256, 'storage_path', storage_path));

  insert into public.notifications (organisation_id, user_id, invoice_id, title, body, tone)
  values (target_organisation_id, auth.uid(), invoice_record_id, 'Invoice uploaded', 'The invoice is ready for secure scanning.', 'blue');

  return jsonb_build_object('invoice_id', invoice_record_id, 'storage_path', storage_path, 'file_sha256', input_file_sha256, 'fingerprint_hash', fingerprint_value);
exception
  when unique_violation then
    raise exception 'This invoice appears to have already been submitted.';
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
  request_id uuid;
  verification_request_id uuid;
  assessment_id uuid;
  agreement_record public.financing_agreements%rowtype;
  settlement_id uuid;
  fee_amount numeric(18,2);
  principal_amount numeric(18,2);
  remainder_amount numeric(18,2);
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
    values (current_invoice.organisation_id, current_invoice.id, 'INVOICE_DOCUMENT_CHECK', 'PASSED', 5, jsonb_build_object('mime_type', 'application/pdf', 'invoice_number', current_invoice.invoice_number, 'amount', current_invoice.amount));
  end if;

  if next_status = 'EXTRACTED' then
    insert into public.invoice_extracted_fields (organisation_id, invoice_id, extraction_engine, model_version, schema_version, confidence, extracted_json, source_page_count, trace_id)
    values (current_invoice.organisation_id, current_invoice.id, 'Invoice Check', 'invoice-check-v1', 'invoice-v1', 94.50, jsonb_build_object('invoice_number', current_invoice.invoice_number, 'amount', current_invoice.amount, 'currency', current_invoice.currency, 'purchase_order_number', current_invoice.purchase_order_number, 'buyer_id', current_invoice.buyer_id, 'supplier_id', current_invoice.supplier_id), 1, 'trace-' || current_invoice.id::text);
  end if;

  if next_status = 'VERIFYING' then
    insert into public.verification_requests (organisation_id, invoice_id, request_type, external_reference, idempotency_key, status, requested_by)
    values (current_invoice.organisation_id, current_invoice.id, 'ERP_PO_MATCH', current_invoice.purchase_order_number, 'verify-' || current_invoice.id::text, 'RUNNING', auth.uid())
    on conflict (organisation_id, idempotency_key) do update set status = 'RUNNING', updated_at = now();
  end if;

  if next_status = 'VERIFIED' then
    select id into verification_request_id from public.verification_requests where invoice_id = current_invoice.id order by created_at desc limit 1;
    if verification_request_id is not null then
      update public.verification_requests set status = 'PASSED', updated_at = now() where id = verification_request_id;
      insert into public.verification_results (organisation_id, verification_request_id, invoice_id, result_status, confidence, mismatch_flags, evidence, signed_by)
      values (current_invoice.organisation_id, verification_request_id, current_invoice.id, 'VERIFIED', 96.00, '[]'::jsonb, jsonb_build_object('po_match', current_invoice.purchase_order_id is not null, 'supplier_match', true, 'amount_match', true, 'unpaid', true), auth.uid());
    end if;
  end if;

  if next_status = 'RISK_ASSESSED' then
    insert into public.fraud_checks (organisation_id, invoice_id, check_type, status, score_delta, evidence)
    values
      (current_invoice.organisation_id, current_invoice.id, 'EXACT_FILE_DUPLICATE', 'PASSED', 15, jsonb_build_object('duplicate_found', false)),
      (current_invoice.organisation_id, current_invoice.id, 'NORMALIZED_INVOICE_DUPLICATE', 'PASSED', 15, jsonb_build_object('duplicate_found', false)),
      (current_invoice.organisation_id, current_invoice.id, 'LOOKALIKE_SUPPLIER_DOMAIN', 'PASSED', 8, jsonb_build_object('domain_change', false)),
      (current_invoice.organisation_id, current_invoice.id, 'BANK_ACCOUNT_CHANGE', 'PASSED', 8, jsonb_build_object('bank_change', false));

    insert into public.risk_assessments (organisation_id, invoice_id, model_version, score, band, decision, explanation, created_by_service)
    values (current_invoice.organisation_id, current_invoice.id, 'capitalbridge-risk-v1', 87.00, 'LOW', 'ELIGIBLE', jsonb_build_object('summary', 'Invoice Check, duplicate, and fraud evidence supports financing eligibility'), 'risk-engine')
    returning id into assessment_id;

    insert into public.risk_factors (organisation_id, risk_assessment_id, invoice_id, code, label, earned_score, max_score, weight, evidence)
    values
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'INVOICE_STRUCTURE', 'Invoice document structure check', 18, 20, 20, jsonb_build_object('source', 'invoice_files')),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'DUPLICATE_CONTROLS', 'Duplicate file and invoice checks', 15, 15, 15, jsonb_build_object('source', 'global_invoice_registry')),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'PARTY_MATCH', 'Supplier and buyer captured', 14, 15, 15, jsonb_build_object('source', 'upload')),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'PO_MATCH', 'Purchase order match quality', case when current_invoice.purchase_order_id is null then 5 else 10 end, 10, 10, jsonb_build_object('source', 'purchase_orders')),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'PAYMENT_HISTORY', 'Buyer payment history available', 7, 10, 10, jsonb_build_object('source', 'buyers')),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'REVIEW_ATTENTION', 'Manual review if buyer cannot confirm PO', 20, 30, 30, jsonb_build_object('requires_review', current_invoice.purchase_order_id is null));
  end if;

  if next_status = 'FINANCE_ELIGIBLE' then
    insert into public.financing_requests (organisation_id, invoice_id, requested_advance, max_advance, fee_cap_bps, status, created_by)
    values (current_invoice.organisation_id, current_invoice.id, updated_invoice.requested_advance, updated_invoice.max_advance, 350, 'OFFERED', auth.uid())
    on conflict (invoice_id) do update set requested_advance = excluded.requested_advance, max_advance = excluded.max_advance, status = 'OFFERED', updated_at = now()
    returning id into request_id;

    if not exists (select 1 from public.financing_offers where financing_request_id = request_id) then
      insert into public.financing_offers (organisation_id, financing_request_id, financier_name, offer_name, advance_amount, fee_bps, term_days, status, metadata)
      values
        (current_invoice.organisation_id, request_id, 'Ubuntu Bank Sandbox', 'Bridge Advance', updated_invoice.requested_advance, 300, greatest(current_invoice.due_date - current_date, 1), 'OPEN', jsonb_build_object('speed', 'Same day')),
        (current_invoice.organisation_id, request_id, 'Cedar Capital Demo', 'Flex Settlement', updated_invoice.requested_advance, 250, greatest(current_invoice.due_date - current_date + 15, 1), 'OPEN', jsonb_build_object('speed', '24 hours'));
    end if;
  end if;

  if next_status = 'FUNDED' then
    select * into agreement_record from public.financing_agreements where invoice_id = current_invoice.id limit 1;
    if not found then raise exception 'accepted financing agreement required before funding'; end if;
    update public.financing_agreements set status = 'ACTIVE', updated_at = now() where id = agreement_record.id;
    insert into public.funding_transactions (organisation_id, financing_agreement_id, invoice_id, transaction_type, amount, provider, provider_reference, status, posted_at)
    values (current_invoice.organisation_id, agreement_record.id, current_invoice.id, 'DISBURSEMENT', agreement_record.principal_amount, 'MockBankingProvider', 'bank-demo-' || agreement_record.id::text, 'POSTED', now());
  end if;

  if next_status = 'SETTLED' then
    select * into agreement_record from public.financing_agreements where invoice_id = current_invoice.id limit 1;
    if not found then raise exception 'active financing agreement required before settlement'; end if;
    principal_amount := agreement_record.principal_amount;
    fee_amount := agreement_record.fee_amount;
    remainder_amount := greatest(current_invoice.amount - principal_amount - fee_amount, 0);
    insert into public.settlements (organisation_id, financing_agreement_id, invoice_id, buyer_payment_amount, principal_repaid, fee_collected, sme_remainder, status, settled_at)
    values (current_invoice.organisation_id, agreement_record.id, current_invoice.id, current_invoice.amount, principal_amount, fee_amount, remainder_amount, 'RECONCILED', now()) returning id into settlement_id;
    insert into public.settlement_allocations (organisation_id, settlement_id, recipient_organisation_id, allocation_type, amount)
    values (current_invoice.organisation_id, settlement_id, agreement_record.financier_organisation_id, 'PRINCIPAL', principal_amount), (current_invoice.organisation_id, settlement_id, agreement_record.financier_organisation_id, 'FEE', fee_amount), (current_invoice.organisation_id, settlement_id, current_invoice.organisation_id, 'SME_REMAINDER', remainder_amount);
    insert into public.funding_transactions (organisation_id, financing_agreement_id, invoice_id, transaction_type, amount, provider, provider_reference, status, posted_at)
    values (current_invoice.organisation_id, agreement_record.id, current_invoice.id, 'REPAYMENT', principal_amount, 'Settlement engine', 'settlement-' || settlement_id::text, 'POSTED', now()), (current_invoice.organisation_id, agreement_record.id, current_invoice.id, 'FEE', fee_amount, 'Settlement engine', 'settlement-' || settlement_id::text, 'POSTED', now()), (current_invoice.organisation_id, agreement_record.id, current_invoice.id, 'SME_REMAINDER', remainder_amount, 'Settlement engine', 'settlement-' || settlement_id::text, 'POSTED', now());
    update public.financing_agreements set status = 'SETTLED', updated_at = now() where id = agreement_record.id;
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

revoke execute on function public.seed_demo_workspace(uuid) from authenticated;

grant select on public.subscription_plans to authenticated;
grant select on public.organisation_subscriptions to authenticated;
grant select on public.invoice_scan_usage to authenticated;
grant select on public.payment_checkout_sessions to authenticated;
grant execute on function public.get_plan_status() to authenticated;
grant execute on function public.select_subscription_plan(uuid) to authenticated;
grant execute on function public.create_invoice_upload(uuid, text, text, text, text, numeric, numeric, date, text, text, text, bigint, integer) to authenticated;
grant execute on function public.consume_invoice_scan_quota(uuid) to authenticated;
grant execute on function public.ensure_default_subscription(uuid) to authenticated;
grant execute on function public.complete_user_onboarding(text, text, public.organisation_type) to authenticated;
grant execute on function public.advance_invoice_status(uuid, public.invoice_workflow_status, public.invoice_workflow_status, text, text, text) to authenticated;
