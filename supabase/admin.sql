-- Joshu admin page (https://ahmedwalid4499.github.io/Orbit/admin/): who may use it, and what it reads.
-- Run once in Supabase › SQL Editor, after pro.sql. Everything here is reached only through the `admin` server
-- function, which checks you're an admin first; nothing is readable from the app or the web page directly.

-- Admins: add yourself (the email you sign in to Joshu with) at the bottom.
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  added_at timestamptz not null default now()
);
alter table public.admins enable row level security;   -- no policies: only the server function reads it

-- A note on a Pro grant ("Beta tester", "Friend"), shown on the admin page.
alter table public.entitlements add column if not exists note text;

-- How much each account has synced, for the admin page.
create or replace function public.admin_record_counts() returns table (user_id uuid, records bigint)
language sql security definer set search_path = public as $$
  select user_id, count(*) from public.orbit_records where not deleted group by user_id;
$$;
revoke execute on function public.admin_record_counts() from public, anon, authenticated;

-- AI requests per account: today and the last 30 days.
create or replace function public.admin_ai_usage() returns table (user_id uuid, today int, month bigint)
language sql security definer set search_path = public as $$
  select user_id,
         coalesce(sum(requests) filter (where day = current_date), 0)::int,
         coalesce(sum(requests), 0)
  from public.ai_usage where day > current_date - 30 group by user_id;
$$;
revoke execute on function public.admin_ai_usage() from public, anon, authenticated;

-- Make yourself an admin (change the email):
-- insert into public.admins (user_id) select id from auth.users where email = 'you@example.com' on conflict do nothing;
