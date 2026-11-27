-- =========================================================
-- Lab Manager — Supabase schema
-- ວິທີໃຊ້: Supabase Dashboard → SQL Editor → New query
--          ວາງທັງໝົດນີ້ແລ້ວກົດ Run (ແລ່ນຄັ້ງດຽວ)
-- =========================================================

-- ---------- ຕາຕະລາງ ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  username    text not null unique,
  name        text not null,
  role_title  text default '',
  sys_role    text not null default 'member' check (sys_role in ('admin', 'member')),
  must_change boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.equipment (
  id          uuid primary key default gen_random_uuid(),
  code        text not null,
  name        text not null,
  category    text default '',
  qty         integer not null default 1 check (qty >= 0),
  location    text default '',
  status      text not null default 'ພ້ອມໃຊ້'
              check (status in ('ພ້ອມໃຊ້', 'ຖືກຢືມ', 'ເປ່ເພ', 'ກຳລັງສ້ອມແປງ')),
  borrower    uuid references public.profiles(id) on delete set null,
  return_due  date,
  borrowed_at timestamptz,
  note        text default '',
  created_at  timestamptz not null default now()
);

create table if not exists public.tasks (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  detail      text default '',
  assignee    uuid references public.profiles(id) on delete set null,
  due         date,
  priority    text not null default 'ກາງ' check (priority in ('ສູງ', 'ກາງ', 'ຕ່ຳ')),
  status      text not null default 'ຕ້ອງເຮັດ' check (status in ('ຕ້ອງເຮັດ', 'ກຳລັງເຮັດ', 'ສຳເລັດແລ້ວ')),
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table if not exists public.history (
  id     bigint generated always as identity primary key,
  time   timestamptz not null default now(),
  actor  uuid references public.profiles(id) on delete set null,
  text   text not null
);

-- ---------- Helper: ເປັນ admin ບໍ່ ----------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and sys_role = 'admin');
$$;

-- ---------- ສ້າງ profile ອັດຕະໂນມັດເມື່ອມີ user ໃໝ່ ----------
-- ຜູ້ໃຊ້ຄົນທຳອິດທີ່ສ້າງ ຈະເປັນ admin ອັດຕະໂນມັດ
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, name, sys_role)
  values (
    new.id,
    lower(coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1))),
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    case when exists (select 1 from public.profiles) then 'member' else 'admin' end
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- ຢືມ / ສົ່ງຄືນ (ສະມາຊິກໃຊ້ຜ່ານຟັງຊັນນີ້ເທົ່ານັ້ນ) ----------
create or replace function public.borrow_equipment(p_id uuid, p_borrower uuid, p_due date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'ກະລຸນາເຂົ້າສູ່ລະບົບ'; end if;
  if not public.is_admin() and p_borrower <> auth.uid() then
    raise exception 'ທ່ານຢືມໃນນາມຄົນອື່ນບໍ່ໄດ້';
  end if;
  update public.equipment
     set status = 'ຖືກຢືມ', borrower = p_borrower, return_due = p_due, borrowed_at = now()
   where id = p_id and status = 'ພ້ອມໃຊ້';
  if not found then raise exception 'ອຸປະກອນນີ້ບໍ່ພ້ອມໃຫ້ຢືມ'; end if;
end;
$$;

create or replace function public.return_equipment(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.equipment
     set status = 'ພ້ອມໃຊ້', borrower = null, return_due = null, borrowed_at = null
   where id = p_id and status = 'ຖືກຢືມ'
     and (public.is_admin() or borrower = auth.uid());
  if not found then raise exception 'ທ່ານບໍ່ມີສິດສົ່ງຄືນອຸປະກອນນີ້'; end if;
end;
$$;

-- ຜູ້ໃຊ້ປ່ຽນລະຫັດແລ້ວ → ເຊົາແຈ້ງເຕືອນ
create or replace function public.clear_must_change()
returns void language sql security definer set search_path = public as $$
  update public.profiles set must_change = false where id = auth.uid();
$$;

revoke execute on function public.borrow_equipment(uuid, uuid, date) from public, anon;
revoke execute on function public.return_equipment(uuid) from public, anon;
revoke execute on function public.clear_must_change() from public, anon;
grant  execute on function public.borrow_equipment(uuid, uuid, date) to authenticated;
grant  execute on function public.return_equipment(uuid) to authenticated;
grant  execute on function public.clear_must_change() to authenticated;

-- =========================================================
-- Row Level Security (ສິດການເຂົ້າເຖິງ)
-- =========================================================
alter table public.profiles  enable row level security;
alter table public.equipment enable row level security;
alter table public.tasks     enable row level security;
alter table public.history   enable row level security;

-- profiles: ທຸກຄົນທີ່ login ເບິ່ງໄດ້, ແກ້ໄຂຜ່ານ Edge Function (admin) ເທົ່ານັ້ນ
drop policy if exists "profiles read" on public.profiles;
create policy "profiles read" on public.profiles
  for select to authenticated using (true);

-- equipment: ທຸກຄົນເບິ່ງໄດ້, admin ເພີ່ມ/ແກ້/ລຶບ (ການຢືມ-ຄືນ ໃຊ້ຟັງຊັນຂ້າງເທິງ)
drop policy if exists "equipment read"  on public.equipment;
drop policy if exists "equipment admin" on public.equipment;
create policy "equipment read"  on public.equipment
  for select to authenticated using (true);
create policy "equipment admin" on public.equipment
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- tasks: ທຸກຄົນເບິ່ງໄດ້, admin ຈັດການທັງໝົດ, ສະມາຊິກຈັດການສະເພາະວຽກຂອງຕົນເອງ
drop policy if exists "tasks read"   on public.tasks;
drop policy if exists "tasks insert" on public.tasks;
drop policy if exists "tasks update" on public.tasks;
drop policy if exists "tasks delete" on public.tasks;
create policy "tasks read" on public.tasks
  for select to authenticated using (true);
create policy "tasks insert" on public.tasks
  for insert to authenticated
  with check (public.is_admin() or assignee = auth.uid());
create policy "tasks update" on public.tasks
  for update to authenticated
  using (public.is_admin() or assignee = auth.uid())
  with check (public.is_admin() or assignee = auth.uid());
create policy "tasks delete" on public.tasks
  for delete to authenticated
  using (public.is_admin() or assignee = auth.uid());

-- history: ທຸກຄົນເບິ່ງໄດ້, ບັນທຶກໄດ້ສະເພາະໃນນາມຕົນເອງ, ແກ້/ລຶບ ບໍ່ໄດ້
drop policy if exists "history read"   on public.history;
drop policy if exists "history insert" on public.history;
create policy "history read" on public.history
  for select to authenticated using (true);
create policy "history insert" on public.history
  for insert to authenticated with check (actor = auth.uid());

-- =========================================================
-- Realtime: ໃຫ້ໜ້າເວັບອັບເດດເອງເມື່ອຄົນອື່ນແກ້ໄຂຂໍ້ມູນ
-- =========================================================
do $$
declare t text;
begin
  foreach t in array array['profiles', 'equipment', 'tasks', 'history'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- =========================================================
-- ຂໍ້ມູນຕົວຢ່າງ (ລຶບສ່ວນນີ້ອອກໄດ້ ຖ້າບໍ່ຕ້ອງການ)
-- =========================================================
insert into public.equipment (code, name, category, qty, location, status, note)
select * from (values
  ('EQ-001', 'ກ້ອງຈຸລະທັດ', 'ເຄື່ອງມືວັດແທກ', 2, 'ຕູ້ A1', 'ພ້ອມໃຊ້', ''),
  ('EQ-002', 'Pipette 100–1000 µL', 'ອຸປະກອນທົ່ວໄປ', 5, 'ລີ້ນຊັກ B2', 'ພ້ອມໃຊ້', ''),
  ('EQ-003', 'ເຄື່ອງປັ່ນແຍກ (Centrifuge)', 'ເຄື່ອງມືຫຼັກ', 1, 'ໂຕະ C', 'ກຳລັງສ້ອມແປງ', 'ລໍຖ້າຊ່າງມາກວດ')
) as v(code, name, category, qty, location, status, note)
where not exists (select 1 from public.equipment);
