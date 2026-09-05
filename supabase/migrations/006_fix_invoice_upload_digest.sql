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
  fingerprint_value := encode(extensions.digest(normalized_supplier || ':' || normalized_buyer || ':' || normalized_invoice || ':' || input_amount::text || ':' || input_due_date::text, 'sha256'::text), 'hex');

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

grant execute on function public.create_invoice_upload(uuid, text, text, text, text, numeric, numeric, date, text, text, text, bigint, integer) to authenticated;
