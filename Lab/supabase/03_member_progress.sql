-- =========================================================
-- Lab Manager — ອັບເດດ #3: ຄວາມຄືບໜ້າວຽກ + ຈຳກັດສິດສະມາຊິກ
--   - ສະມາຊິກເຫັນສະເພາະວຽກ ແລະ ປະຫວັດຂອງຕົນເອງ
--   - ສະມາຊິກອັບເດດໄດ້ສະເພາະ ສະຖານະ / % ຄວາມຄືບໜ້າ / ບັນທຶກ ຂອງວຽກຕົນເອງ
--   - ສ້າງ / ແກ້ໄຂ / ລຶບ ວຽກ ໄດ້ສະເພາະ Admin
-- ວິທີໃຊ້: SQL Editor → New query → ວາງທັງໝົດ → Run (ແລ່ນຊ້ຳໄດ້)
-- =========================================================

-- ---------- ຊ່ອງຂໍ້ມູນໃໝ່ຂອງວຽກ ----------
alter table public.tasks add column if not exists progress      integer not null default 0;
alter table public.tasks add column if not exists progress_note text not null default '';
alter table public.tasks add column if not exists updated_at    timestamptz not null default now();
alter table public.tasks add column if not exists updated_by    uuid references public.profiles(id) on delete set null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'tasks_progress_range') then
    alter table public.tasks add constraint tasks_progress_range check (progress between 0 and 100);
  end if;
end $$;

update public.tasks set progress = 100 where status = 'ສຳເລັດແລ້ວ' and progress < 100;

-- ບັນທຶກເວລາ ແລະ ຜູ້ອັບເດດລ່າສຸດອັດຕະໂນມັດ
create or replace function public.touch_task()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  return new;
end;
$$;
drop trigger if exists tasks_touch on public.tasks;
create trigger tasks_touch before update on public.tasks
  for each row execute function public.touch_task();

-- ---------- ສິດຂອງວຽກ ----------
drop policy if exists "tasks read"        on public.tasks;
drop policy if exists "tasks insert"      on public.tasks;
drop policy if exists "tasks update"      on public.tasks;
drop policy if exists "tasks delete"      on public.tasks;
drop policy if exists "tasks admin write" on public.tasks;

-- ເບິ່ງ: admin ເຫັນທັງໝົດ, ສະມາຊິກເຫັນສະເພາະວຽກທີ່ມອບໃຫ້ຕົນເອງ
create policy "tasks read" on public.tasks
  for select to authenticated using (public.is_admin() or assignee = auth.uid());
-- ສ້າງ / ແກ້ໄຂ / ລຶບ: admin ເທົ່ານັ້ນ (ສະມາຊິກອັບເດດຄວາມຄືບໜ້າຜ່ານຟັງຊັນຂ້າງລຸ່ມ)
create policy "tasks admin write" on public.tasks
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ສະມາຊິກອັບເດດຄວາມຄືບໜ້າວຽກຂອງຕົນເອງ
create or replace function public.update_task_progress(p_id uuid, p_status text, p_progress integer, p_note text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'ກະລຸນາເຂົ້າສູ່ລະບົບ'; end if;
  if p_status not in ('ຕ້ອງເຮັດ', 'ກຳລັງເຮັດ', 'ສຳເລັດແລ້ວ') then raise exception 'ສະຖານະບໍ່ຖືກຕ້ອງ'; end if;
  update public.tasks
     set status = p_status,
         progress = case when p_status = 'ສຳເລັດແລ້ວ' then 100
                         else greatest(0, least(100, coalesce(p_progress, progress))) end,
         progress_note = coalesce(p_note, progress_note)
   where id = p_id and (public.is_admin() or assignee = auth.uid());
  if not found then raise exception 'ທ່ານບໍ່ມີສິດອັບເດດວຽກນີ້'; end if;
end;
$$;
revoke execute on function public.update_task_progress(uuid, text, integer, text) from public, anon;
grant  execute on function public.update_task_progress(uuid, text, integer, text) to authenticated;

-- ---------- ປະຫວັດ: ສະມາຊິກເຫັນສະເພາະຂອງຕົນເອງ ----------
drop policy if exists "history read" on public.history;
create policy "history read" on public.history
  for select to authenticated using (public.is_admin() or actor = auth.uid());
