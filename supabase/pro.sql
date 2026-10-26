-- Joshu Pro: who has Pro (and until when), and a daily fair-use counter for the AI.
-- Run once in Supabase › SQL Editor. Writes happen only from the server functions (service role).

create table if not exists public.entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pro_until timestamptz,
  source text not null default 'app_store',          -- app_store, owner, gift
  product_id text,
  original_transaction_id text unique,
  updated_at timestamptz not null default now()
);
alter table public.entitlements enable row level security;
drop policy if exists "read own entitlement" on public.entitlements;
create policy "read own entitlement" on public.entitlements for select using (auth.uid() = user_id);

create table if not exists public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null default current_date,
  requests int not null default 0,
  primary key (user_id, day)
);
alter table public.ai_usage enable row level security;
drop policy if exists "read own usage" on public.ai_usage;
create policy "read own usage" on public.ai_usage for select using (auth.uid() = user_id);

-- Counts one AI request for today and returns today's total (called by the claude function).
create or replace function public.bump_ai_usage(uid uuid) returns int
language sql security definer set search_path = public as $$
  insert into public.ai_usage (user_id, day, requests) values (uid, current_date, 1)
  on conflict (user_id, day) do update set requests = public.ai_usage.requests + 1
  returning requests;
$$;
revoke execute on function public.bump_ai_usage(uuid) from public, anon, authenticated;

-- Give yourself Pro for good (change the email to the one you sign in to Joshu with):
-- insert into public.entitlements (user_id, pro_until, source)
--   select id, '2100-01-01', 'owner' from auth.users where email = 'you@example.com'
--   on conflict (user_id) do update set pro_until = excluded.pro_until, source = 'owner';

-- Delete my account (Settings › Account › Delete Account): removes the sign-in and, through "on delete cascade",
-- everything synced for it.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
