-- =========================================================
-- Lab Manager — ອັບເດດ #2: ຮູບອຸປະກອນ + ໝວດໝູ່
-- ວິທີໃຊ້: SQL Editor → New query → ວາງທັງໝົດ → Run (ແລ່ນຊ້ຳໄດ້)
-- =========================================================

-- ---------- ຕາຕະລາງໝວດໝູ່ ----------
create table if not exists public.categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  color       text not null default '#6366f1',
  description text default '',
  created_at  timestamptz not null default now()
);

alter table public.categories enable row level security;
drop policy if exists "categories read"  on public.categories;
drop policy if exists "categories admin" on public.categories;
create policy "categories read"  on public.categories
  for select to authenticated using (true);
create policy "categories admin" on public.categories
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ຍ້າຍໝວດໝູ່ທີ່ມີຢູ່ແລ້ວໃນອຸປະກອນ ເຂົ້າຕາຕະລາງໃໝ່
insert into public.categories (name)
select distinct trim(category) from public.equipment where coalesce(trim(category), '') <> ''
on conflict (name) do nothing;

update public.equipment set category = null where coalesce(trim(category), '') = '';
update public.equipment set category = trim(category) where category is not null;
alter table public.equipment alter column category drop default;

-- ເຊື່ອມອຸປະກອນ → ໝວດໝູ່ (ປ່ຽນຊື່ໝວດ = ອຸປະກອນປ່ຽນຕາມ, ລຶບໝວດ = ອຸປະກອນເປັນ "ບໍ່ມີໝວດ")
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'equipment_category_fkey') then
    alter table public.equipment
      add constraint equipment_category_fkey foreign key (category)
      references public.categories(name) on update cascade on delete set null;
  end if;
end $$;

-- ---------- ຮູບອຸປະກອນ ----------
alter table public.equipment add column if not exists image_path text;

-- Bucket ເກັບຮູບ (public = ເປີດເບິ່ງຮູບໄດ້ຜ່ານລິ້ງ, ອັບໂຫຼດໄດ້ສະເພາະ admin)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('equipment-images', 'equipment-images', true, 5242880,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "equipment images read"         on storage.objects;
drop policy if exists "equipment images admin insert" on storage.objects;
drop policy if exists "equipment images admin update" on storage.objects;
drop policy if exists "equipment images admin delete" on storage.objects;

create policy "equipment images read" on storage.objects
  for select to authenticated using (bucket_id = 'equipment-images');
create policy "equipment images admin insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'equipment-images' and public.is_admin());
create policy "equipment images admin update" on storage.objects
  for update to authenticated using (bucket_id = 'equipment-images' and public.is_admin());
create policy "equipment images admin delete" on storage.objects
  for delete to authenticated using (bucket_id = 'equipment-images' and public.is_admin());

-- ---------- Realtime ----------
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'categories') then
    alter publication supabase_realtime add table public.categories;
  end if;
end $$;
