-- Grace Shop v2 : paiement dans l'application, suivi des commandes, alertes en direct.
-- À exécuter après schema.sql. Ré-exécutable sans danger.

alter table public.orders add column if not exists pay_method text;
alter table public.orders add column if not exists pay_status text not null default 'en attente';
alter table public.orders add column if not exists pay_phone text;
alter table public.orders add column if not exists pay_ident text;
alter table public.orders add column if not exists tx_reference text;
alter table public.orders add column if not exists pay_ref text;
alter table public.orders add column if not exists paid_at timestamptz;
alter table public.orders add column if not exists client_key text;

do $$ begin
  alter table public.orders add constraint orders_pay_status_chk
    check (pay_status in ('en attente','en cours','payé','échoué','déclaré'));
exception when duplicate_object then null; end $$;

-- Une commande se crée toujours « non payée » : seul le serveur (ou l'équipe) peut la marquer payée.
drop policy if exists ord_insert on public.orders;
create policy ord_insert on public.orders for insert with check (
  (user_id is null or user_id = auth.uid())
  and status = 'nouvelle'
  and pay_status = 'en attente'
  and paid_at is null and tx_reference is null and pay_ref is null and pay_ident is null
  and (client_key is null or char_length(client_key) between 16 and 64)
);

-- Suivi d'une commande sans compte : la cliente garde une clé secrète sur son téléphone.
create or replace function public.order_track(p_ref text, p_key text)
returns table (ref text, status text, pay_status text, pay_method text, total int, created_at timestamptz, paid_at timestamptz)
language sql stable security definer set search_path = public as $$
  select o.ref, o.status, o.pay_status, o.pay_method, o.total, o.created_at, o.paid_at
  from public.orders o
  where o.ref = p_ref and ((p_key is not null and o.client_key = p_key) or (auth.uid() is not null and o.user_id = auth.uid()));
$$;

-- La cliente déclare avoir payé (code reçu par SMS) : l'équipe vérifie ensuite.
create or replace function public.declare_payment(p_ref text, p_key text, p_code text, p_method text)
returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.orders set pay_ref = left(trim(p_code), 40), pay_status = 'déclaré', pay_method = left(coalesce(p_method, pay_method), 20)
  where ref = p_ref
    and ((p_key is not null and client_key = p_key) or (auth.uid() is not null and user_id = auth.uid()))
    and pay_status in ('en attente', 'échoué', 'en cours');
  get diagnostics n = row_count;
  return n > 0;
end $$;

grant execute on function public.order_track(text, text) to anon, authenticated;
grant execute on function public.declare_payment(text, text, text, text) to anon, authenticated;

-- Alertes en direct pour l'équipe (nouvelles commandes, paiements reçus).
alter table public.orders replica identity full;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'orders') then
    alter publication supabase_realtime add table public.orders;
  end if;
end $$;
