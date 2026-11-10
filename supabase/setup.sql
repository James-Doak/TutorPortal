-- TutorPortal database setup. Paste into Supabase > SQL Editor > Run (safe to re-run).

create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text,
  created_at timestamptz default now()
);

create table if not exists public.questions (
  id text primary key,
  data jsonb not null
);

create table if not exists public.diagrams (
  question_id text primary key,
  figures jsonb not null
);

create table if not exists public.saved_papers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  title text,
  settings jsonb,
  question_ids text[],
  created_at timestamptz default now()
);

alter table public.profiles enable row level security;
alter table public.questions enable row level security;
alter table public.diagrams enable row level security;
alter table public.saved_papers enable row level security;

-- Questions and diagrams: readable ONLY by logged-in users. Writes happen with the service key (bypasses RLS).
drop policy if exists "questions: logged in read" on public.questions;
create policy "questions: logged in read" on public.questions for select to authenticated using (true);
drop policy if exists "diagrams: logged in read" on public.diagrams;
create policy "diagrams: logged in read" on public.diagrams for select to authenticated using (true);

-- Profiles and saved papers: each user sees and edits only their own.
drop policy if exists "profiles: own" on public.profiles;
create policy "profiles: own" on public.profiles for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists "papers: own" on public.saved_papers;
create policy "papers: own" on public.saved_papers for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Create a profile row automatically when someone signs up.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)))
  on conflict do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Paper history: recently built vs completed.
alter table public.saved_papers add column if not exists completed boolean not null default false;
alter table public.saved_papers add column if not exists completed_at timestamptz;
alter table public.saved_papers add column if not exists updated_at timestamptz default now();
