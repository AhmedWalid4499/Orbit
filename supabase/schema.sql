-- Orbit sync schema. Run once in Supabase › SQL Editor.
--
-- Every synced item (task, event, habit, transaction, note, book, book category, bucket-list item, setting)
-- is one row. `data` holds its fields as JSON, so new Orbit features don't need database changes.
-- Row Level Security makes sure each signed-in person can only read and write their own rows.

create table if not exists public.orbit_records (
    id          uuid        not null,
    user_id     uuid        not null default auth.uid() references auth.users (id) on delete cascade,
    kind        text        not null,
    data        jsonb       not null default '{}'::jsonb,
    deleted     boolean     not null default false,
    updated_at  timestamptz not null default now(),
    primary key (user_id, id)
);

create index if not exists orbit_records_sync_idx on public.orbit_records (user_id, updated_at);
create index if not exists orbit_records_kind_idx on public.orbit_records (user_id, kind);

-- The server clock decides updated_at, so devices with a wrong clock can't break syncing.
create or replace function public.orbit_touch_updated_at() returns trigger
language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end $$;

drop trigger if exists orbit_records_touch on public.orbit_records;
create trigger orbit_records_touch before insert or update on public.orbit_records
    for each row execute function public.orbit_touch_updated_at();

alter table public.orbit_records enable row level security;

drop policy if exists "Own rows: read"   on public.orbit_records;
drop policy if exists "Own rows: insert" on public.orbit_records;
drop policy if exists "Own rows: update" on public.orbit_records;
drop policy if exists "Own rows: delete" on public.orbit_records;

create policy "Own rows: read"   on public.orbit_records for select to authenticated using (user_id = auth.uid());
create policy "Own rows: insert" on public.orbit_records for insert to authenticated with check (user_id = auth.uid());
create policy "Own rows: update" on public.orbit_records for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Own rows: delete" on public.orbit_records for delete to authenticated using (user_id = auth.uid());

-- Friendly read-only views for browsing your data in the Supabase table editor or SQL.
create or replace view public.orbit_tasks with (security_invoker = true) as
    select id, data->>'title' as title, data->>'area' as area, (data->>'due')::timestamptz as due,
           (data->>'isDone')::boolean as done, updated_at
    from public.orbit_records where kind = 'task' and not deleted;

create or replace view public.orbit_transactions with (security_invoker = true) as
    select id, data->>'title' as title, (data->>'amount')::numeric as amount, data->>'category' as category,
           (data->>'date')::timestamptz as date, updated_at
    from public.orbit_records where kind = 'transaction' and not deleted;

create or replace view public.orbit_books with (security_invoker = true) as
    select id, data->>'title' as title, data->>'author' as author, data->>'status' as status,
           (data->>'rating')::int as rating, updated_at
    from public.orbit_records where kind = 'book' and not deleted;
