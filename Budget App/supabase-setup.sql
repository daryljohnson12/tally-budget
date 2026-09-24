-- Tally Budget: database setup for Supabase
-- Run once in Supabase → SQL Editor.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null
);

create table if not exists public.budgets (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.budget_members (
  budget_id uuid not null references public.budgets(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','member')),
  primary key (budget_id, user_id)
);

create table if not exists public.invites (
  budget_id uuid not null references public.budgets(id) on delete cascade,
  email text not null,
  invited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (budget_id, email)
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  budget_id uuid not null references public.budgets(id) on delete cascade,
  name text not null,
  color text not null default '#7D8B85',
  icon text not null default 'tag',
  monthly_budget numeric(12,2) not null default 0,
  sort int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  budget_id uuid not null references public.budgets(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  amount numeric(12,2) not null check (amount > 0),
  note text not null default '',
  spent_on date not null default current_date,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists expenses_budget_date on public.expenses(budget_id, spent_on desc);

-- Helper: is the signed-in user in this budget?
create or replace function public.is_member(b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from budget_members where budget_id = b and user_id = auth.uid());
$$;

-- Profiles are created automatically at sign-up
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles(id, email) values (new.id, lower(new.email)) on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Row level security
alter table public.profiles enable row level security;
alter table public.budgets enable row level security;
alter table public.budget_members enable row level security;
alter table public.invites enable row level security;
alter table public.categories enable row level security;
alter table public.expenses enable row level security;

drop policy if exists "see self and co-members" on public.profiles;
create policy "see self and co-members" on public.profiles for select using (
  id = auth.uid() or exists (
    select 1 from budget_members m1 join budget_members m2 on m1.budget_id = m2.budget_id
    where m1.user_id = auth.uid() and m2.user_id = profiles.id));

drop policy if exists "members read budget" on public.budgets;
create policy "members read budget" on public.budgets for select using (is_member(id));
drop policy if exists "owner renames budget" on public.budgets;
create policy "owner renames budget" on public.budgets for update using (owner_id = auth.uid());
drop policy if exists "owner deletes budget" on public.budgets;
create policy "owner deletes budget" on public.budgets for delete using (owner_id = auth.uid());

drop policy if exists "members read members" on public.budget_members;
create policy "members read members" on public.budget_members for select using (is_member(budget_id));
drop policy if exists "leave or owner removes" on public.budget_members;
create policy "leave or owner removes" on public.budget_members for delete using (
  (user_id = auth.uid() and role <> 'owner')
  or exists (select 1 from budgets b where b.id = budget_id and b.owner_id = auth.uid() and user_id <> auth.uid()));

drop policy if exists "members manage invites" on public.invites;
create policy "members manage invites" on public.invites for all using (is_member(budget_id)) with check (is_member(budget_id));

drop policy if exists "members manage categories" on public.categories;
create policy "members manage categories" on public.categories for all using (is_member(budget_id)) with check (is_member(budget_id));

drop policy if exists "members manage expenses" on public.expenses;
create policy "members manage expenses" on public.expenses for all using (is_member(budget_id)) with check (is_member(budget_id));

-- Create a budget (you become owner) with starter categories
create or replace function public.create_budget(budget_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare b uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  insert into budgets(name, owner_id) values (budget_name, auth.uid()) returning id into b;
  insert into budget_members(budget_id, user_id, role) values (b, auth.uid(), 'owner');
  insert into categories(budget_id, name, color, icon, monthly_budget, sort) values
    (b, 'Gas', '#E07A2E', 'gas', 200, 1),
    (b, 'Fast Food', '#D6455B', 'food', 150, 2),
    (b, 'Groceries', '#3E9B5F', 'cart', 450, 3),
    (b, 'Bills & Utilities', '#4F6FD1', 'bolt', 600, 4),
    (b, 'Shopping', '#A45BC9', 'bag', 150, 5),
    (b, 'Entertainment', '#C9A227', 'ticket', 100, 6);
  return b;
end $$;

-- Turn any invites for my email into memberships
create or replace function public.accept_invites() returns int
language plpgsql security definer set search_path = public as $$
declare my_email text; n int;
begin
  select lower(email) into my_email from auth.users where id = auth.uid();
  insert into budget_members(budget_id, user_id, role)
    select budget_id, auth.uid(), 'member' from invites where lower(email) = my_email
    on conflict do nothing;
  get diagnostics n = row_count;
  delete from invites where lower(email) = my_email;
  return n;
end $$;

grant execute on function public.create_budget(text) to authenticated;
grant execute on function public.accept_invites() to authenticated;

-- Live updates between devices
do $$ begin
  begin alter publication supabase_realtime add table public.expenses; exception when others then null; end;
  begin alter publication supabase_realtime add table public.categories; exception when others then null; end;
end $$;
