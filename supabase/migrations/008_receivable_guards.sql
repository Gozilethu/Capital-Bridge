create or replace function public.prevent_duplicate_receivable_by_transaction_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_supplier_name text;
  new_buyer_name text;
begin
  select lower(trim(legal_name)) into new_supplier_name
  from public.suppliers
  where id = new.supplier_id;

  select lower(trim(legal_name)) into new_buyer_name
  from public.buyers
  where id = new.buyer_id;

  if exists (
    select 1
    from public.invoices existing_invoice
    join public.suppliers existing_supplier on existing_supplier.id = existing_invoice.supplier_id
    join public.buyers existing_buyer on existing_buyer.id = existing_invoice.buyer_id
    where existing_invoice.id <> new.id
      and lower(trim(existing_invoice.invoice_number)) = lower(trim(new.invoice_number))
      and existing_invoice.amount = new.amount
      and existing_invoice.due_date = new.due_date
      and coalesce(lower(trim(existing_invoice.purchase_order_number)), '') = coalesce(lower(trim(new.purchase_order_number)), '')
      and lower(trim(existing_supplier.legal_name)) = new_supplier_name
      and lower(trim(existing_buyer.legal_name)) = new_buyer_name
  ) then
    raise exception 'A matching receivable with the same supplier, buyer, invoice number, amount, due date, and purchase order already exists.';
  end if;

  return new;
end;
$$;

drop trigger if exists prevent_duplicate_receivable_by_transaction_fields_trigger on public.invoices;
create trigger prevent_duplicate_receivable_by_transaction_fields_trigger
  before insert on public.invoices
  for each row
  execute function public.prevent_duplicate_receivable_by_transaction_fields();

create or replace function public.require_eligible_risk_before_financier_market()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  latest_decision text;
begin
  if new.status = 'FINANCE_ELIGIBLE' and old.status is distinct from new.status then
    select assessment.decision into latest_decision
    from public.risk_assessments assessment
    where assessment.invoice_id = new.id
      and assessment.organisation_id = new.organisation_id
    order by assessment.created_at desc
    limit 1;

    if coalesce(latest_decision, '') <> 'ELIGIBLE' then
      raise exception 'Transaction risk assessment requires manual review before financing offers can open.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists require_eligible_risk_before_financier_market_trigger on public.invoices;
create trigger require_eligible_risk_before_financier_market_trigger
  before update of status on public.invoices
  for each row
  execute function public.require_eligible_risk_before_financier_market();