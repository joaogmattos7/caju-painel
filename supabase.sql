-- =====================================================================
-- CAJU · Painel de clientes e entregas
-- Cole este arquivo inteiro em Supabase > SQL Editor e clique em Run.
-- Rode UMA vez só.
-- ANTES DE RODAR: troque os dois e-mails da linha "insert" abaixo pelos
-- e-mails das pessoas que podem usar o painel.
-- =====================================================================

-- 1) Lista de e-mails autorizados (só quem estiver aqui enxerga os dados)
create table if not exists public.allowed_emails (
  email text primary key
);
alter table public.allowed_emails enable row level security;
-- sem policies: ninguém lê essa tabela pela API, só a função abaixo

insert into public.allowed_emails (email) values
  ('pessoa1@exemplo.com'),
  ('pessoa2@exemplo.com')
on conflict do nothing;

create or replace function public.am_i_member()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.allowed_emails
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function public.am_i_member() from public;
grant execute on function public.am_i_member() to authenticated;

-- 2) Tabelas
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact text,
  drive_folder_url text,
  created_at timestamptz not null default now(),
  updated_by text,
  updated_at timestamptz not null default now()
);
-- Também atualiza a tabela em projetos Supabase já existentes.
alter table public.clients add column if not exists drive_folder_url text;

create table if not exists public.deliveries (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  title text not null,
  type text,
  due date,
  publication_date date,
  owner text,
  status text not null default 'pending' check (status in ('pending','ready','done')),
  done_at date,
  created_at timestamptz not null default now(),
  updated_by text,
  updated_at timestamptz not null default now()
);
-- Também atualiza a tabela em projetos Supabase já existentes.
alter table public.deliveries add column if not exists publication_date date;
notify pgrst, 'reload schema';
create index if not exists deliveries_client_idx on public.deliveries(client_id);

-- 3) Histórico: grava no servidor quem mexeu por último e quando
create or replace function public.set_audit()
returns trigger
language plpgsql
as $$
begin
  new.updated_by := auth.jwt() ->> 'email';
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists clients_audit on public.clients;
create trigger clients_audit before insert or update on public.clients
  for each row execute function public.set_audit();

drop trigger if exists deliveries_audit on public.deliveries;
create trigger deliveries_audit before insert or update on public.deliveries
  for each row execute function public.set_audit();

-- 4) Segurança: só e-mails autorizados leem e editam
alter table public.clients enable row level security;
alter table public.deliveries enable row level security;

drop policy if exists "equipe clients" on public.clients;
create policy "equipe clients" on public.clients
  for all to authenticated
  using (public.am_i_member()) with check (public.am_i_member());

drop policy if exists "equipe deliveries" on public.deliveries;
create policy "equipe deliveries" on public.deliveries
  for all to authenticated
  using (public.am_i_member()) with check (public.am_i_member());

-- 5) Atualização em tempo real entre as telas
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'clients') then
    alter publication supabase_realtime add table public.clients;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'deliveries') then
    alter publication supabase_realtime add table public.deliveries;
  end if;
end $$;

-- 6) Financeiro: lançamentos e regras usadas apenas para projeção
create table if not exists public.finance_recurring (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('income','expense')),
  client_id uuid references public.clients(id) on delete set null,
  title text not null,
  category text not null default 'Outros',
  amount numeric(12,2) not null check (amount > 0),
  day_of_month smallint not null check (day_of_month between 1 and 31),
  start_date date not null,
  end_date date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_by text,
  updated_at timestamptz not null default now(),
  check (end_date is null or end_date >= start_date)
);

create table if not exists public.finance_entries (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('income','expense')),
  client_id uuid references public.clients(id) on delete set null,
  title text not null,
  category text not null default 'Outros',
  amount numeric(12,2) not null check (amount > 0),
  due_date date not null,
  paid_at date,
  recurrence_id uuid references public.finance_recurring(id) on delete set null,
  recurrence_month date,
  created_at timestamptz not null default now(),
  updated_by text,
  updated_at timestamptz not null default now(),
  check (recurrence_id is null or recurrence_month is not null),
  check (recurrence_month is null or date_trunc('month', recurrence_month)::date = recurrence_month)
);

create index if not exists finance_entries_due_idx on public.finance_entries(due_date);
create index if not exists finance_entries_paid_idx on public.finance_entries(paid_at) where paid_at is not null;
create index if not exists finance_recurring_active_idx on public.finance_recurring(active, start_date, end_date);
create unique index if not exists finance_entries_recurring_month_idx on public.finance_entries(recurrence_id, recurrence_month) where recurrence_id is not null;

alter table public.finance_entries enable row level security;
alter table public.finance_recurring enable row level security;
grant select, insert, update, delete on public.finance_entries, public.finance_recurring to authenticated;
revoke all on public.finance_entries, public.finance_recurring from anon;

drop policy if exists "equipe finance entries" on public.finance_entries;
create policy "equipe finance entries" on public.finance_entries
  for all to authenticated
  using (public.am_i_member()) with check (public.am_i_member());

drop policy if exists "equipe finance recurring" on public.finance_recurring;
create policy "equipe finance recurring" on public.finance_recurring
  for all to authenticated
  using (public.am_i_member()) with check (public.am_i_member());

drop trigger if exists finance_entries_audit on public.finance_entries;
create trigger finance_entries_audit before insert or update on public.finance_entries
  for each row execute function public.set_audit();

drop trigger if exists finance_recurring_audit on public.finance_recurring;
create trigger finance_recurring_audit before insert or update on public.finance_recurring
  for each row execute function public.set_audit();

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'finance_entries') then
    alter publication supabase_realtime add table public.finance_entries;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'finance_recurring') then
    alter publication supabase_realtime add table public.finance_recurring;
  end if;
end $$;

-- 7) Conteúdo, tarefas, captação e aniversários
create table if not exists public.content_posts (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on delete set null,
  title text not null,
  caption text,
  format text not null default 'Post',
  status text not null default 'idea' check (status in ('idea','production','review','approved','scheduled','published')),
  publish_at timestamptz,
  published_at timestamptz,
  cover_url text,
  created_at timestamptz not null default now(),
  updated_by text,
  updated_at timestamptz not null default now()
);
create index if not exists content_posts_publish_idx on public.content_posts(publish_at);
create index if not exists content_posts_status_idx on public.content_posts(status);

create table if not exists public.team_tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  notes text,
  owner text,
  due_date date,
  done boolean not null default false,
  status text not null default 'todo',
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_by text,
  updated_at timestamptz not null default now()
);
alter table public.team_tasks add column if not exists status text not null default 'todo';
alter table public.team_tasks add column if not exists position integer not null default 0;
update public.team_tasks
set status = case when done then 'done' else 'todo' end
where status is null or status not in ('todo','doing','done','idea') or (status = 'todo' and done);
update public.team_tasks
set done = (status = 'done')
where done is distinct from (status = 'done');
alter table public.team_tasks alter column status set default 'todo';
alter table public.team_tasks alter column status set not null;
alter table public.team_tasks alter column position set default 0;
alter table public.team_tasks alter column position set not null;
alter table public.team_tasks drop constraint if exists team_tasks_status_check;
alter table public.team_tasks add constraint team_tasks_status_check check (status in ('todo','doing','done','idea'));
create index if not exists team_tasks_due_idx on public.team_tasks(due_date);
create index if not exists team_tasks_board_idx on public.team_tasks(status, position, created_at);

create table if not exists public.team_checklist (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  done boolean not null default false,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_by text,
  updated_at timestamptz not null default now()
);

create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact text,
  source text,
  next_step text,
  status text not null default 'new' check (status in ('new','contacted','qualified','won','lost')),
  created_at timestamptz not null default now(),
  updated_by text,
  updated_at timestamptz not null default now()
);

create table if not exists public.birthdays (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  birthday date not null,
  kind text not null default 'Cliente' check (kind in ('Cliente','Equipe','Parceiro')),
  created_at timestamptz not null default now(),
  updated_by text,
  updated_at timestamptz not null default now()
);
create index if not exists birthdays_date_idx on public.birthdays(birthday);

alter table public.content_posts enable row level security;
alter table public.team_tasks enable row level security;
alter table public.team_checklist enable row level security;
alter table public.leads enable row level security;
alter table public.birthdays enable row level security;
grant select, insert, update, delete on public.content_posts, public.team_tasks, public.team_checklist, public.leads, public.birthdays to authenticated;
revoke all on public.content_posts, public.team_tasks, public.team_checklist, public.leads, public.birthdays from anon;

drop policy if exists "equipe content posts" on public.content_posts;
create policy "equipe content posts" on public.content_posts
  for all to authenticated
  using (public.am_i_member()) with check (public.am_i_member());
drop policy if exists "equipe team tasks" on public.team_tasks;
create policy "equipe team tasks" on public.team_tasks
  for all to authenticated
  using (public.am_i_member()) with check (public.am_i_member());
drop policy if exists "equipe team checklist" on public.team_checklist;
create policy "equipe team checklist" on public.team_checklist
  for all to authenticated
  using (public.am_i_member()) with check (public.am_i_member());
drop policy if exists "equipe leads" on public.leads;
create policy "equipe leads" on public.leads
  for all to authenticated
  using (public.am_i_member()) with check (public.am_i_member());
drop policy if exists "equipe birthdays" on public.birthdays;
create policy "equipe birthdays" on public.birthdays
  for all to authenticated
  using (public.am_i_member()) with check (public.am_i_member());

drop trigger if exists content_posts_audit on public.content_posts;
create trigger content_posts_audit before insert or update on public.content_posts
  for each row execute function public.set_audit();
drop trigger if exists team_tasks_audit on public.team_tasks;
create trigger team_tasks_audit before insert or update on public.team_tasks
  for each row execute function public.set_audit();
drop trigger if exists team_checklist_audit on public.team_checklist;
create trigger team_checklist_audit before insert or update on public.team_checklist
  for each row execute function public.set_audit();
drop trigger if exists leads_audit on public.leads;
create trigger leads_audit before insert or update on public.leads
  for each row execute function public.set_audit();
drop trigger if exists birthdays_audit on public.birthdays;
create trigger birthdays_audit before insert or update on public.birthdays
  for each row execute function public.set_audit();

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'content_posts') then
    alter publication supabase_realtime add table public.content_posts;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'team_tasks') then
    alter publication supabase_realtime add table public.team_tasks;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'team_checklist') then
    alter publication supabase_realtime add table public.team_checklist;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'leads') then
    alter publication supabase_realtime add table public.leads;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'birthdays') then
    alter publication supabase_realtime add table public.birthdays;
  end if;
end $$;
notify pgrst, 'reload schema';

-- Para liberar mais alguém depois:
--   insert into public.allowed_emails values ('novo@exemplo.com');
-- Para tirar o acesso de alguém:
--   delete from public.allowed_emails where email = 'saiu@exemplo.com';

-- 8) Clientes: contatos, contratos e receitas mensais vinculadas
-- Requer que as seções 1-6 já tenham sido executadas.
alter table public.clients add column if not exists contact_email text;
alter table public.clients add column if not exists contact_phone text;

create table if not exists public.client_contracts (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  title text not null,
  amount numeric(12,2) not null check (amount > 0),
  due_day smallint not null check (due_day between 1 and 31),
  start_date date not null,
  end_date date,
  contract_url text,
  active boolean not null default true,
  finance_recurring_id uuid references public.finance_recurring(id),
  created_at timestamptz not null default now(),
  updated_by text,
  updated_at timestamptz not null default now(),
  check (end_date is null or end_date >= start_date)
);
create index if not exists client_contracts_client_idx on public.client_contracts(client_id);
create unique index if not exists client_contracts_recurring_idx on public.client_contracts(finance_recurring_id) where finance_recurring_id is not null;

alter table public.client_contracts enable row level security;
grant select, insert, update, delete on public.client_contracts to authenticated;
revoke all on public.client_contracts from anon;
drop policy if exists "equipe client contracts" on public.client_contracts;
create policy "equipe client contracts" on public.client_contracts
  for all to authenticated
  using (public.am_i_member()) with check (public.am_i_member());

drop trigger if exists client_contracts_audit on public.client_contracts;
create trigger client_contracts_audit before insert or update on public.client_contracts
  for each row execute function public.set_audit();

create or replace function public.sync_client_contract_recurring()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recurring_id uuid;
begin
  if tg_op = 'DELETE' then
    update public.finance_recurring set active = false
    where id = old.finance_recurring_id;
    delete from public.finance_entries
    where recurrence_id = old.finance_recurring_id
      and paid_at is null
      and due_date >= current_date;
    return old;
  end if;

  if new.finance_recurring_id is null then
    insert into public.finance_recurring (
      kind, client_id, title, category, amount, day_of_month,
      start_date, end_date, active
    ) values (
      'income', new.client_id, new.title, 'Mensalidade', new.amount,
      new.due_day, new.start_date, new.end_date, new.active
    ) returning id into recurring_id;
    new.finance_recurring_id := recurring_id;
  else
    recurring_id := new.finance_recurring_id;
    update public.finance_recurring set
      kind = 'income',
      client_id = new.client_id,
      title = new.title,
      category = 'Mensalidade',
      amount = new.amount,
      day_of_month = new.due_day,
      start_date = new.start_date,
      end_date = new.end_date,
      active = new.active
    where id = recurring_id;
  end if;

  if tg_op = 'UPDATE' then
    if not new.active then
      delete from public.finance_entries
      where recurrence_id = recurring_id
        and paid_at is null
        and due_date >= current_date;
    else
      delete from public.finance_entries
      where recurrence_id = recurring_id
        and paid_at is null
        and due_date >= current_date
        and (
          date_trunc('month', due_date)::date
            + least(new.due_day, extract(day from (date_trunc('month', due_date) + interval '1 month - 1 day'))::integer) - 1
            < new.start_date
          or (
            new.end_date is not null
            and date_trunc('month', due_date)::date
              + least(new.due_day, extract(day from (date_trunc('month', due_date) + interval '1 month - 1 day'))::integer) - 1
              > new.end_date
          )
        );

      update public.finance_entries e set
        client_id = new.client_id,
        title = new.title,
        category = 'Mensalidade',
        amount = new.amount,
        due_date = date_trunc('month', e.due_date)::date
          + least(
              new.due_day,
              extract(day from (date_trunc('month', e.due_date) + interval '1 month - 1 day'))::integer
            ) - 1
      where e.recurrence_id = recurring_id
        and e.paid_at is null
        and e.due_date >= current_date
        and date_trunc('month', e.due_date)::date
          + least(new.due_day, extract(day from (date_trunc('month', e.due_date) + interval '1 month - 1 day'))::integer) - 1
          >= current_date
        and date_trunc('month', e.due_date)::date >= date_trunc('month', new.start_date)::date
        and date_trunc('month', e.due_date)::date
          + least(new.due_day, extract(day from (date_trunc('month', e.due_date) + interval '1 month - 1 day'))::integer) - 1
          >= new.start_date
        and (
          new.end_date is null
          or date_trunc('month', e.due_date)::date
            + least(new.due_day, extract(day from (date_trunc('month', e.due_date) + interval '1 month - 1 day'))::integer) - 1
            <= new.end_date
        );
    end if;
  end if;

  return new;
end;
$$;
revoke all on function public.sync_client_contract_recurring() from public;

drop trigger if exists client_contracts_sync_recurring on public.client_contracts;
create trigger client_contracts_sync_recurring
  before insert or update or delete on public.client_contracts
  for each row execute function public.sync_client_contract_recurring();

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'client_contracts') then
    alter publication supabase_realtime add table public.client_contracts;
  end if;
end $$;
notify pgrst, 'reload schema';
