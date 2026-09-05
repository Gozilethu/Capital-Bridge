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
  current_month_start date := date_trunc('month', now())::date;
  current_month_end date := (date_trunc('month', now())::date + interval '1 month - 1 day')::date;
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
  values (org_id, current_month_start, current_month_end, 0)
  on conflict (organisation_id, period_start) do nothing;

  select usage.scans_used into used_count
  from public.invoice_scan_usage usage
  where usage.organisation_id = org_id
    and usage.period_start = current_month_start;

  return jsonb_build_object(
    'plan_id', plan_record.id,
    'plan_code', plan_record.code,
    'plan_name', plan_record.name,
    'monthly_price_cents', plan_record.monthly_price_cents,
    'currency', plan_record.currency,
    'scan_limit', plan_record.scan_limit,
    'scans_used', coalesce(used_count, 0),
    'scans_remaining', greatest(plan_record.scan_limit - coalesce(used_count, 0), 0),
    'period_start', current_month_start,
    'period_end', current_month_end,
    'requires_payment', coalesce(used_count, 0) >= plan_record.scan_limit and plan_record.code = 'free'
  );
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
  current_month_start date := date_trunc('month', now())::date;
  current_month_end date := (date_trunc('month', now())::date + interval '1 month - 1 day')::date;
begin
  perform public.ensure_default_subscription(target_organisation_id);

  select plan.* into plan_record
  from public.organisation_subscriptions subscription
  join public.subscription_plans plan on plan.id = subscription.plan_id
  where subscription.organisation_id = target_organisation_id and subscription.status = 'ACTIVE'
  order by subscription.created_at desc
  limit 1;

  if not found then
    raise exception 'No active scan plan is configured for this organisation.';
  end if;

  insert into public.invoice_scan_usage (organisation_id, period_start, period_end, scans_used)
  values (target_organisation_id, current_month_start, current_month_end, 0)
  on conflict (organisation_id, period_start) do nothing;

  update public.invoice_scan_usage as usage
  set scans_used = usage.scans_used + 1,
      updated_at = now()
  where usage.organisation_id = target_organisation_id
    and usage.period_start = current_month_start
    and usage.scans_used < plan_record.scan_limit
  returning usage.scans_used into used_count;

  if used_count is null then
    raise exception 'Monthly scan limit reached. The free plan includes 10 invoice scans per month. Choose a paid plan to scan more invoices.';
  end if;

  return jsonb_build_object(
    'plan_code', plan_record.code,
    'scan_limit', plan_record.scan_limit,
    'scans_used', used_count,
    'scans_remaining', greatest(plan_record.scan_limit - used_count, 0)
  );
end;
$$;

grant execute on function public.get_plan_status() to authenticated;
grant execute on function public.consume_invoice_scan_quota(uuid) to authenticated;