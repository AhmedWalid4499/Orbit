-- Public "My Card" pages. Run once in Supabase › SQL Editor (after schema.sql).
--
-- Each person can publish one card under a short name (slug). Anyone can read published cards,
-- so the web page at https://ahmedwalid4499.github.io/Orbit/card/?u=<slug> can show it without signing in.
-- Only the owner can create, change or remove their card.
--
-- data = { name, headline, company, location, bio, colorIndex,
--          links: [{ kind, url, display }],
--          email, phone   (empty unless the owner chose to show them),
--          photo          (small JPEG as a data: URL, or "") }

create table if not exists public.public_cards (
    slug        text        primary key check (slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'),
    user_id     uuid        not null unique default auth.uid() references auth.users (id) on delete cascade,
    data        jsonb       not null default '{}'::jsonb,
    updated_at  timestamptz not null default now()
);

drop trigger if exists public_cards_touch on public.public_cards;
create trigger public_cards_touch before insert or update on public.public_cards
    for each row execute function public.orbit_touch_updated_at();

alter table public.public_cards enable row level security;

drop policy if exists "Anyone can read cards" on public.public_cards;
drop policy if exists "Own card: insert" on public.public_cards;
drop policy if exists "Own card: update" on public.public_cards;
drop policy if exists "Own card: delete" on public.public_cards;

create policy "Anyone can read cards" on public.public_cards for select to anon, authenticated using (true);
create policy "Own card: insert" on public.public_cards for insert to authenticated with check (user_id = auth.uid());
create policy "Own card: update" on public.public_cards for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Own card: delete" on public.public_cards for delete to authenticated using (user_id = auth.uid());
