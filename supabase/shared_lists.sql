-- Shared lists (groceries, trip plans) between Orbit users. Run once in Supabase › SQL Editor (after schema.sql).
--
-- Everyone in `members` can read and edit a list; the owner shares its six-letter `code`, and anyone signed in who
-- enters the code joins (join_shared_list). Items are edited one at a time on the server (shared_list_put_item,
-- shared_list_remove_item), so two people ticking things off at once don't overwrite each other.
--
-- items = [{ id, text, done, by, at }]

create table if not exists public.shared_lists (
    id          uuid        primary key default gen_random_uuid(),
    code        text        not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 6)),
    title       text        not null default '',
    owner       uuid        not null default auth.uid() references auth.users (id) on delete cascade,
    members     uuid[]      not null default array[auth.uid()],
    items       jsonb       not null default '[]'::jsonb,
    updated_at  timestamptz not null default now()
);

drop trigger if exists shared_lists_touch on public.shared_lists;
create trigger shared_lists_touch before insert or update on public.shared_lists
    for each row execute function public.orbit_touch_updated_at();

alter table public.shared_lists enable row level security;

drop policy if exists "Members: read" on public.shared_lists;
drop policy if exists "Own list: insert" on public.shared_lists;
drop policy if exists "Members: update" on public.shared_lists;
drop policy if exists "Owner: delete" on public.shared_lists;

create policy "Members: read" on public.shared_lists for select to authenticated using (auth.uid() = any (members));
create policy "Own list: insert" on public.shared_lists for insert to authenticated
    with check (owner = auth.uid() and members = array[auth.uid()]);
create policy "Members: update" on public.shared_lists for update to authenticated
    using (auth.uid() = any (members)) with check (auth.uid() = any (members));
create policy "Owner: delete" on public.shared_lists for delete to authenticated using (owner = auth.uid());

-- Join a list by its code. Runs as the table owner so you can find a list you're not on yet; returns its id.
create or replace function public.join_shared_list(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
    list_id uuid;
begin
    if auth.uid() is null then raise exception 'not signed in'; end if;
    update shared_lists set members = array_append(members, auth.uid())
        where code = upper(trim(p_code)) and not (auth.uid() = any (members))
        returning id into list_id;
    if list_id is null then
        select id into list_id from shared_lists where code = upper(trim(p_code)) and auth.uid() = any (members);
    end if;
    if list_id is null then raise exception 'list not found'; end if;
    return list_id;
end $$;

-- Add an item, or replace the one with the same id, keeping its place in the list.
create or replace function public.shared_list_put_item(p_list uuid, p_item jsonb) returns void
language sql security invoker set search_path = public as $$
    update shared_lists set items = case
        when exists (select 1 from jsonb_array_elements(items) e where e->>'id' = p_item->>'id')
            then (select jsonb_agg(case when e->>'id' = p_item->>'id' then p_item else e end order by n)
                  from jsonb_array_elements(items) with ordinality as t(e, n))
        else items || jsonb_build_array(p_item)
    end
    where id = p_list;
$$;

create or replace function public.shared_list_remove_item(p_list uuid, p_id text) returns void
language sql security invoker set search_path = public as $$
    update shared_lists set items = coalesce((select jsonb_agg(e order by n)
                                              from jsonb_array_elements(items) with ordinality as t(e, n)
                                              where e->>'id' <> p_id), '[]'::jsonb)
    where id = p_list;
$$;

-- Leave a list. When the owner leaves, the list is deleted for everyone.
create or replace function public.leave_shared_list(p_list uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
    delete from shared_lists where id = p_list and owner = auth.uid();
    update shared_lists set members = array_remove(members, auth.uid()) where id = p_list and auth.uid() = any (members);
end $$;

grant execute on function public.join_shared_list(text) to authenticated;
grant execute on function public.shared_list_put_item(uuid, jsonb) to authenticated;
grant execute on function public.shared_list_remove_item(uuid, text) to authenticated;
grant execute on function public.leave_shared_list(uuid) to authenticated;
