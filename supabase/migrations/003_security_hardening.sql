-- Security hardening: prevent client-side creation of authoritative finance states.
-- Normal users can create uploaded invoices, but finance workflow records move through RPCs.

drop policy if exists invoices_insert_member on public.invoices;
create policy invoices_insert_uploaded on public.invoices
  for insert with check (
    public.is_org_member(organisation_id)
    and status = 'UPLOADED'
    and verification_status = 'UNVERIFIED'
    and financing_status = 'NOT_FINANCED'
    and amount > 0
    and requested_advance >= 0
    and requested_advance <= amount
    and max_advance >= 0
    and max_advance <= amount
    and outstanding_amount = amount
  );

drop policy if exists verification_requests_insert_member on public.verification_requests;
drop policy if exists verification_requests_update_operator on public.verification_requests;

drop policy if exists financing_requests_insert_member on public.financing_requests;
drop policy if exists financing_requests_update_operator on public.financing_requests;

drop policy if exists financing_offers_insert_member on public.financing_offers;
drop policy if exists financing_offers_update_operator on public.financing_offers;

drop policy if exists settlements_insert_member on public.settlements;
drop policy if exists settlements_update_operator on public.settlements;

revoke insert, update on
  public.verification_requests,
  public.financing_requests,
  public.financing_offers,
  public.settlements,
  public.idempotency_keys
from authenticated;

revoke insert on
  public.invoice_status_history,
  public.invoice_extracted_fields,
  public.invoice_fingerprints,
  public.verification_results,
  public.fraud_checks,
  public.fraud_alerts,
  public.risk_assessments,
  public.risk_factors,
  public.funding_transactions,
  public.settlement_allocations,
  public.integration_events,
  public.data_access_logs,
  public.audit_logs
from authenticated;

grant execute on function public.advance_invoice_status(uuid, public.invoice_workflow_status, public.invoice_workflow_status, text, text, text) to authenticated;
grant execute on function public.accept_financing_offer(uuid, text) to authenticated;
grant execute on function public.update_requested_advance(uuid, numeric) to authenticated;
grant execute on function public.complete_user_onboarding(text, text, public.organisation_type) to authenticated;
grant execute on function public.seed_demo_workspace(uuid) to authenticated;