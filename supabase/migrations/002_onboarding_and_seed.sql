-- Onboarding and demo workspace seed data.
-- Each signed-in user gets their own organisation-owned records.

alter table public.financing_offers
  add column if not exists financier_name text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create or replace function public.seed_demo_workspace(target_organisation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  org_record public.organisations%rowtype;
  supplier_record_id uuid;
  buyer_record_id uuid;
  po_record_id uuid;
  invoice_record_id uuid;
  demo_file_hash text := '7f2d64c9a6b8e31f4a7d2a9b0d4e5c91c8a2f6d13b0e9c41f38a5b7c24d0a6ef';
  demo_fingerprint text := '4d9b1f7b12c8e67fbb57a31f84f1a2f1be7c49ed8c82a9d1e7c0bc6a2e9f5041';
begin
  select * into org_record
  from public.organisations
  where id = target_organisation_id;

  if not found then
    raise exception 'organisation not found';
  end if;

  if auth.uid() is not null and not public.is_org_member(target_organisation_id) then
    raise exception 'not allowed';
  end if;

  if not exists (select 1 from public.business_profiles where organisation_id = target_organisation_id) then
    insert into public.business_profiles (
      organisation_id,
      industry,
      annual_revenue,
      average_invoice_value,
      bank_account_fingerprint,
      metadata
    )
    values (
      target_organisation_id,
      'Transport and logistics',
      2400000.00,
      100000.00,
      'bank-fp-demo-workspace',
      jsonb_build_object('source', 'onboarding_seed')
    );
  end if;

  select id into supplier_record_id
  from public.suppliers
  where organisation_id = target_organisation_id
    and legal_name = org_record.legal_name
  limit 1;

  if supplier_record_id is null then
    insert into public.suppliers (
      organisation_id,
      legal_name,
      registration_number,
      tax_number,
      verified_bank_fingerprint,
      verified_domain
    )
    values (
      target_organisation_id,
      org_record.legal_name,
      coalesce(org_record.registration_number, 'REG-DEMO-SUPPLIER'),
      coalesce(org_record.tax_number, 'TAX-DEMO-SUPPLIER'),
      'bank-fp-demo-workspace',
      'capitalbridge-demo.local'
    )
    returning id into supplier_record_id;
  end if;

  select id into buyer_record_id
  from public.buyers
  where organisation_id = target_organisation_id
    and legal_name = 'Demo Mining Corporation'
  limit 1;

  if buyer_record_id is null then
    insert into public.buyers (
      organisation_id,
      legal_name,
      registration_number,
      tax_number,
      erp_reference,
      payment_history
    )
    values (
      target_organisation_id,
      'Demo Mining Corporation',
      'REG-DEMO-BUYER',
      'TAX-DEMO-BUYER',
      'MOCK-ERP-DEMO-MINING',
      jsonb_build_object('average_days_late', 4, 'paid_invoices', 24, 'disputes', 0)
    )
    returning id into buyer_record_id;
  end if;

  select id into po_record_id
  from public.purchase_orders
  where organisation_id = target_organisation_id
    and po_number = 'PO-DMC-8821'
  limit 1;

  if po_record_id is null then
    insert into public.purchase_orders (
      organisation_id,
      buyer_id,
      supplier_id,
      po_number,
      currency,
      amount,
      status,
      erp_source,
      erp_payload
    )
    values (
      target_organisation_id,
      buyer_record_id,
      supplier_record_id,
      'PO-DMC-8821',
      'ZAR',
      100000.00,
      'OPEN',
      'MockERPConnector',
      jsonb_build_object('line_match', true, 'goods_received', true, 'schema_version', 'demo-v1')
    )
    returning id into po_record_id;
  end if;

  insert into public.invoices (
    organisation_id,
    buyer_id,
    supplier_id,
    purchase_order_id,
    invoice_number,
    purchase_order_number,
    currency,
    amount,
    requested_advance,
    max_advance,
    outstanding_amount,
    issue_date,
    due_date,
    status,
    verification_status,
    financing_status,
    file_hash,
    invoice_fingerprint,
    created_by
  )
  values (
    target_organisation_id,
    buyer_record_id,
    supplier_record_id,
    po_record_id,
    'INV-2026-1045',
    'PO-DMC-8821',
    'ZAR',
    100000.00,
    30000.00,
    85000.00,
    100000.00,
    current_date,
    current_date + 60,
    'UPLOADED',
    'UNVERIFIED',
    'NOT_FINANCED',
    demo_file_hash,
    demo_fingerprint,
    auth.uid()
  )
  on conflict (organisation_id, invoice_number) do update
  set buyer_id = excluded.buyer_id,
      supplier_id = excluded.supplier_id,
      purchase_order_id = excluded.purchase_order_id,
      updated_at = now()
  returning id into invoice_record_id;

  insert into public.invoice_files (
    organisation_id,
    invoice_id,
    storage_bucket,
    storage_path,
    original_filename,
    sha256,
    mime_type,
    byte_size,
    page_count,
    malware_status,
    validation_status
  )
  values (
    target_organisation_id,
    invoice_record_id,
    'invoice-documents',
    target_organisation_id::text || '/' || invoice_record_id::text || '/original.pdf',
    'INV-2026-1045.pdf',
    demo_file_hash,
    'application/pdf',
    385024,
    1,
    'QUEUED',
    'QUEUED'
  )
  on conflict (organisation_id, sha256) do nothing;

  insert into public.invoice_fingerprints (
    organisation_id,
    invoice_id,
    file_sha256,
    perceptual_hash,
    normalized_invoice_number,
    supplier_tax_number,
    buyer_registration_number,
    amount,
    due_date,
    fingerprint_hash
  )
  values (
    target_organisation_id,
    invoice_record_id,
    demo_file_hash,
    'phash-demo-invoice-1045',
    'INV20261045',
    coalesce(org_record.tax_number, 'TAX-DEMO-SUPPLIER'),
    'REG-DEMO-BUYER',
    100000.00,
    current_date + 60,
    demo_fingerprint
  )
  on conflict (invoice_id) do nothing;

  if not exists (
    select 1 from public.audit_logs
    where organisation_id = target_organisation_id
      and invoice_id = invoice_record_id
      and event_code = 'PDF_UPLOADED'
  ) then
    insert into public.audit_logs (
      organisation_id,
      invoice_id,
      actor_user_id,
      actor_service,
      event_code,
      event_detail,
      metadata
    )
    values
      (target_organisation_id, invoice_record_id, auth.uid(), 'capitalbridge-api', 'PDF_UPLOADED', 'Invoice file record created in private storage bucket', jsonb_build_object('seeded', true)),
      (target_organisation_id, invoice_record_id, auth.uid(), 'document-pipeline', 'PDF_HASH_CREATED', 'SHA-256 and invoice fingerprint stored before extraction', jsonb_build_object('seeded', true));
  end if;

  if not exists (
    select 1 from public.notifications
    where organisation_id = target_organisation_id
      and invoice_id = invoice_record_id
      and title = 'Invoice uploaded'
  ) then
    insert into public.notifications (organisation_id, user_id, invoice_id, title, body, tone)
    values (
      target_organisation_id,
      auth.uid(),
      invoice_record_id,
      'Invoice uploaded',
      'The invoice is ready for secure scanning.',
      'blue'
    );
  end if;

  if not exists (
    select 1 from public.integrations
    where organisation_id = target_organisation_id
      and provider = 'Enterprise AP Environment'
  ) then
    insert into public.integrations (
      organisation_id,
      provider,
      integration_type,
      status,
      metadata
    )
    values (
      target_organisation_id,
      'Enterprise AP Environment',
      'ERP',
      'CONNECTED',
      jsonb_build_object(
        'source', 'Enterprise-AP-Environment',
        'local_url', 'http://localhost:7860',
        'live_url', 'https://huggingface.co/spaces/decent-cow26/invoice-env',
        'tasks', jsonb_build_array(
          jsonb_build_object('name', 'easy', 'difficulty', 'Clean invoice', 'maps_to', 'baseline extraction and PO approval', 'tone', 'green'),
          jsonb_build_object('name', 'medium', 'difficulty', 'Price mismatch', 'maps_to', 'line-item variance flagging', 'tone', 'amber'),
          jsonb_build_object('name', 'hard', 'difficulty', 'Schema drift', 'maps_to', 'ERP adapter recovery and duplicate detection', 'tone', 'blue'),
          jsonb_build_object('name', 'expert_negotiation', 'difficulty', 'Vendor negotiation', 'maps_to', 'corrected invoice request workflow', 'tone', 'amber'),
          jsonb_build_object('name', 'expert_fraud', 'difficulty', 'Lookalike fraud', 'maps_to', 'sender domain and bank-account anomaly checks', 'tone', 'red')
        )
      )
    );
  end if;
end;
$$;

create or replace function public.complete_user_onboarding(
  input_full_name text,
  input_organisation_name text,
  input_account_type public.organisation_type default 'SME'
)
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
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  if nullif(trim(input_full_name), '') is null then
    raise exception 'full name is required';
  end if;

  if nullif(trim(input_organisation_name), '') is null then
    raise exception 'organisation name is required';
  end if;

  select member.organisation_id, org.legal_name
  into workspace_id, workspace_name
  from public.organisation_members member
  join public.organisations org on org.id = member.organisation_id
  where member.user_id = current_user_id
    and member.status = 'ACTIVE'
  order by member.created_at
  limit 1;

  if workspace_id is null then
    insert into public.organisations (
      legal_name,
      trading_name,
      organisation_type,
      country_code,
      kyc_status,
      risk_tier,
      created_by
    )
    values (
      trim(input_organisation_name),
      trim(input_organisation_name),
      input_account_type,
      'ZA',
      'PENDING',
      'UNRATED',
      current_user_id
    )
    returning id, legal_name into workspace_id, workspace_name;

    insert into public.organisation_members (organisation_id, user_id, role, status)
    values (workspace_id, current_user_id, 'OWNER', 'ACTIVE')
    on conflict (organisation_id, user_id) do update
    set role = 'OWNER',
        status = 'ACTIVE',
        updated_at = now();
  end if;

  insert into public.profiles (id, default_organisation_id, email, full_name)
  values (current_user_id, workspace_id, user_email, trim(input_full_name))
  on conflict (id) do update
  set default_organisation_id = excluded.default_organisation_id,
      email = excluded.email,
      full_name = excluded.full_name,
      updated_at = now();

  perform public.seed_demo_workspace(workspace_id);

  return jsonb_build_object(
    'organisation_id', workspace_id,
    'organisation_name', workspace_name,
    'email', user_email
  );
end;
$$;

create or replace function public.update_requested_advance(
  target_invoice_id uuid,
  requested_amount numeric
)
returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  invoice_record public.invoices%rowtype;
  updated_invoice public.invoices%rowtype;
  max_allowed numeric(18,2);
begin
  if requested_amount <= 0 then
    raise exception 'requested amount must be positive';
  end if;

  select * into invoice_record
  from public.invoices
  where id = target_invoice_id
  for update;

  if not found then
    raise exception 'invoice not found';
  end if;

  if not public.has_org_role(invoice_record.organisation_id, array['OWNER', 'ADMIN', 'FINANCE']::public.member_role[]) then
    raise exception 'not allowed';
  end if;

  if invoice_record.status <> 'FINANCE_ELIGIBLE' then
    raise exception 'advance amount can only change while invoice is finance eligible';
  end if;

  if exists (select 1 from public.financing_agreements where invoice_id = invoice_record.id) then
    raise exception 'advance amount is locked by financing agreement';
  end if;

  max_allowed := case
    when invoice_record.max_advance > 0 then invoice_record.max_advance
    else round(invoice_record.amount * 0.85, 2)
  end;

  if requested_amount > max_allowed then
    raise exception 'requested amount exceeds maximum advance';
  end if;

  update public.invoices
  set requested_advance = requested_amount,
      updated_at = now()
  where id = invoice_record.id
  returning * into updated_invoice;

  update public.financing_requests
  set requested_advance = requested_amount,
      updated_at = now()
  where invoice_id = invoice_record.id
    and status in ('REQUESTED', 'OFFERED');

  update public.financing_offers offer
  set advance_amount = requested_amount,
      updated_at = now()
  from public.financing_requests request
  where offer.financing_request_id = request.id
    and request.invoice_id = invoice_record.id
    and offer.status = 'OPEN';

  insert into public.audit_logs (
    organisation_id,
    invoice_id,
    actor_user_id,
    actor_service,
    event_code,
    event_detail
  )
  values (
    invoice_record.organisation_id,
    invoice_record.id,
    auth.uid(),
    'capitalbridge-api',
    'REQUESTED_ADVANCE_UPDATED',
    'Requested advance updated before offer acceptance'
  );

  return updated_invoice;
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
  select * into current_invoice
  from public.invoices
  where id = target_invoice_id
  for update;

  if not found then
    raise exception 'invoice not found';
  end if;

  if not public.has_org_role(
    current_invoice.organisation_id,
    array['OWNER', 'ADMIN', 'FINANCE', 'OPERATIONS', 'BUYER_APPROVER', 'FINANCIER_ANALYST']::public.member_role[]
  ) then
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
        when next_status = 'VERIFYING' then 'PENDING'::public.verification_status
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
      max_advance = case
        when next_status = 'FINANCE_ELIGIBLE' and max_advance = 0 then round(amount * 0.85, 2)
        else max_advance
      end,
      requested_advance = case
        when next_status = 'FINANCE_ELIGIBLE' and requested_advance = 0 then round(amount * 0.30, 2)
        else requested_advance
      end,
      outstanding_amount = case
        when next_status = 'SETTLED' then 0
        else outstanding_amount
      end,
      updated_at = now()
  where id = target_invoice_id
  returning * into updated_invoice;

  if next_status = 'SCANNING' then
    update public.invoice_files
    set malware_status = 'PASSED',
        validation_status = 'PASSED'
    where invoice_id = current_invoice.id;
  end if;

  if next_status = 'EXTRACTED' then
    insert into public.invoice_extracted_fields (
      organisation_id,
      invoice_id,
      extraction_engine,
      model_version,
      schema_version,
      confidence,
      extracted_json,
      source_page_count,
      trace_id
    )
    values (
      current_invoice.organisation_id,
      current_invoice.id,
      'Enterprise AP Environment',
      'demo-v1',
      'invoice-v1',
      94.50,
      jsonb_build_object(
        'invoice_number', current_invoice.invoice_number,
        'amount', current_invoice.amount,
        'currency', current_invoice.currency,
        'purchase_order_number', current_invoice.purchase_order_number,
        'buyer_id', current_invoice.buyer_id,
        'supplier_id', current_invoice.supplier_id
      ),
      1,
      'trace-' || current_invoice.id::text
    );
  end if;

  if next_status = 'VERIFYING' then
    insert into public.verification_requests (
      organisation_id,
      invoice_id,
      request_type,
      external_reference,
      idempotency_key,
      status,
      requested_by
    )
    values (
      current_invoice.organisation_id,
      current_invoice.id,
      'ERP_PO_MATCH',
      current_invoice.purchase_order_number,
      'verify-' || current_invoice.id::text,
      'RUNNING',
      auth.uid()
    )
    on conflict (organisation_id, idempotency_key) do update
    set status = 'RUNNING',
        updated_at = now();
  end if;

  if next_status = 'VERIFIED' then
    select id into verification_request_id
    from public.verification_requests
    where invoice_id = current_invoice.id
    order by created_at desc
    limit 1;

    if verification_request_id is not null then
      update public.verification_requests
      set status = 'PASSED',
          updated_at = now()
      where id = verification_request_id;

      insert into public.verification_results (
        organisation_id,
        verification_request_id,
        invoice_id,
        result_status,
        confidence,
        mismatch_flags,
        evidence,
        signed_by
      )
      values (
        current_invoice.organisation_id,
        verification_request_id,
        current_invoice.id,
        'VERIFIED',
        96.00,
        '[]'::jsonb,
        jsonb_build_object('po_match', true, 'supplier_match', true, 'amount_match', true, 'unpaid', true),
        auth.uid()
      );
    end if;
  end if;

  if next_status = 'RISK_ASSESSED' then
    insert into public.fraud_checks (organisation_id, invoice_id, check_type, status, score_delta, evidence)
    values
      (current_invoice.organisation_id, current_invoice.id, 'EXACT_FILE_DUPLICATE', 'PASSED', 15, jsonb_build_object('duplicate_found', false)),
      (current_invoice.organisation_id, current_invoice.id, 'NORMALIZED_INVOICE_DUPLICATE', 'PASSED', 15, jsonb_build_object('duplicate_found', false)),
      (current_invoice.organisation_id, current_invoice.id, 'LOOKALIKE_SUPPLIER_DOMAIN', 'PASSED', 8, jsonb_build_object('domain_change', false)),
      (current_invoice.organisation_id, current_invoice.id, 'BANK_ACCOUNT_CHANGE', 'PASSED', 8, jsonb_build_object('bank_change', false));

    insert into public.risk_assessments (
      organisation_id,
      invoice_id,
      model_version,
      score,
      band,
      decision,
      explanation,
      created_by_service
    )
    values (
      current_invoice.organisation_id,
      current_invoice.id,
      'capitalbridge-risk-demo-v1',
      87.00,
      'LOW',
      'ELIGIBLE',
      jsonb_build_object('summary', 'ERP, PO, duplicate, and fraud evidence supports financing eligibility'),
      'risk-engine'
    )
    returning id into assessment_id;

    insert into public.risk_factors (
      organisation_id,
      risk_assessment_id,
      invoice_id,
      code,
      label,
      earned_score,
      max_score,
      weight,
      evidence
    )
    values
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'ERP_VERIFICATION', 'Direct buyer/ERP verification', 18, 20, 20, jsonb_build_object('source', 'verification_results')),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'DUPLICATE_CONTROLS', 'Duplicate file and invoice checks', 15, 15, 15, jsonb_build_object('source', 'fraud_checks')),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'PARTY_MATCH', 'Supplier and buyer match', 14, 15, 15, jsonb_build_object('source', 'erp')),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'PO_MATCH', 'Purchase order match quality', 10, 10, 10, jsonb_build_object('source', 'purchase_orders')),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'PAYMENT_HISTORY', 'Known buyer payment history', 10, 10, 10, jsonb_build_object('average_days_late', 4)),
      (current_invoice.organisation_id, assessment_id, current_invoice.id, 'LATE_PAYMENT_ATTENTION', 'Buyer averages four days late', 20, 30, 30, jsonb_build_object('average_days_late', 4));
  end if;

  if next_status = 'FINANCE_ELIGIBLE' then
    insert into public.financing_requests (
      organisation_id,
      invoice_id,
      requested_advance,
      max_advance,
      fee_cap_bps,
      status,
      created_by
    )
    values (
      current_invoice.organisation_id,
      current_invoice.id,
      updated_invoice.requested_advance,
      updated_invoice.max_advance,
      350,
      'OFFERED',
      auth.uid()
    )
    on conflict (invoice_id) do update
    set requested_advance = excluded.requested_advance,
        max_advance = excluded.max_advance,
        status = 'OFFERED',
        updated_at = now()
    returning id into request_id;

    if not exists (select 1 from public.financing_offers where financing_request_id = request_id) then
      insert into public.financing_offers (
        organisation_id,
        financing_request_id,
        financier_name,
        offer_name,
        advance_amount,
        fee_bps,
        term_days,
        status,
        metadata
      )
      values
        (current_invoice.organisation_id, request_id, 'Ubuntu Bank Sandbox', 'Bridge Advance', updated_invoice.requested_advance, 300, 60, 'OPEN', jsonb_build_object('speed', 'Same day')),
        (current_invoice.organisation_id, request_id, 'Cedar Capital Demo', 'Flex Settlement', updated_invoice.requested_advance, 250, 75, 'OPEN', jsonb_build_object('speed', '24 hours'));
    end if;
  end if;

  if next_status = 'FUNDED' then
    select * into agreement_record
    from public.financing_agreements
    where invoice_id = current_invoice.id
    limit 1;

    if not found then
      raise exception 'accepted financing agreement required before funding';
    end if;

    update public.financing_agreements
    set status = 'ACTIVE',
        updated_at = now()
    where id = agreement_record.id;

    insert into public.funding_transactions (
      organisation_id,
      financing_agreement_id,
      invoice_id,
      transaction_type,
      amount,
      provider,
      provider_reference,
      status,
      posted_at
    )
    values (
      current_invoice.organisation_id,
      agreement_record.id,
      current_invoice.id,
      'DISBURSEMENT',
      agreement_record.principal_amount,
      'MockBankingProvider',
      'bank-demo-' || agreement_record.id::text,
      'POSTED',
      now()
    );
  end if;

  if next_status = 'SETTLED' then
    select * into agreement_record
    from public.financing_agreements
    where invoice_id = current_invoice.id
    limit 1;

    if not found then
      raise exception 'active financing agreement required before settlement';
    end if;

    principal_amount := agreement_record.principal_amount;
    fee_amount := agreement_record.fee_amount;
    remainder_amount := greatest(current_invoice.amount - principal_amount - fee_amount, 0);

    insert into public.settlements (
      organisation_id,
      financing_agreement_id,
      invoice_id,
      buyer_payment_amount,
      principal_repaid,
      fee_collected,
      sme_remainder,
      status,
      settled_at
    )
    values (
      current_invoice.organisation_id,
      agreement_record.id,
      current_invoice.id,
      current_invoice.amount,
      principal_amount,
      fee_amount,
      remainder_amount,
      'RECONCILED',
      now()
    )
    returning id into settlement_id;

    insert into public.settlement_allocations (organisation_id, settlement_id, recipient_organisation_id, allocation_type, amount)
    values
      (current_invoice.organisation_id, settlement_id, agreement_record.financier_organisation_id, 'PRINCIPAL', principal_amount),
      (current_invoice.organisation_id, settlement_id, agreement_record.financier_organisation_id, 'FEE', fee_amount),
      (current_invoice.organisation_id, settlement_id, current_invoice.organisation_id, 'SME_REMAINDER', remainder_amount);

    insert into public.funding_transactions (
      organisation_id,
      financing_agreement_id,
      invoice_id,
      transaction_type,
      amount,
      provider,
      provider_reference,
      status,
      posted_at
    )
    values
      (current_invoice.organisation_id, agreement_record.id, current_invoice.id, 'REPAYMENT', principal_amount, 'Settlement engine', 'settlement-' || settlement_id::text, 'POSTED', now()),
      (current_invoice.organisation_id, agreement_record.id, current_invoice.id, 'FEE', fee_amount, 'Settlement engine', 'settlement-' || settlement_id::text, 'POSTED', now()),
      (current_invoice.organisation_id, agreement_record.id, current_invoice.id, 'SME_REMAINDER', remainder_amount, 'Settlement engine', 'settlement-' || settlement_id::text, 'POSTED', now());

    update public.financing_agreements
    set status = 'SETTLED',
        updated_at = now()
    where id = agreement_record.id;
  end if;

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

  insert into public.notifications (organisation_id, user_id, invoice_id, title, body, tone)
  values (
    current_invoice.organisation_id,
    auth.uid(),
    current_invoice.id,
    replace(next_status::text, '_', ' '),
    event_detail,
    case
      when next_status in ('SETTLED', 'FUNDED', 'FINANCE_ELIGIBLE') then 'green'
      when next_status in ('VERIFYING', 'RISK_ASSESSED', 'OFFER_ACCEPTED') then 'blue'
      when next_status in ('SCANNING', 'EXTRACTED', 'VERIFIED') then 'amber'
      else 'neutral'
    end
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

  insert into public.notifications (organisation_id, user_id, invoice_id, title, body, tone)
  values (
    invoice_record.organisation_id,
    auth.uid(),
    invoice_record.id,
    'OFFER ACCEPTED',
    'Financing offer locked and agreement created',
    'blue'
  );

  return new_agreement;
end;
$$;

grant execute on function public.seed_demo_workspace(uuid) to authenticated;
grant execute on function public.complete_user_onboarding(text, text, public.organisation_type) to authenticated;
grant execute on function public.update_requested_advance(uuid, numeric) to authenticated;
grant execute on function public.advance_invoice_status(uuid, public.invoice_workflow_status, public.invoice_workflow_status, text, text, text) to authenticated;
grant execute on function public.accept_financing_offer(uuid, text) to authenticated;