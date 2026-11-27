-- =========================================================
-- Lab Manager — ອັບເດດ #5: ບັນທຶກຄວາມຄືບໜ້າເປັນແຕ່ລະຮອບ
--   ທຸກຄັ້ງທີ່ ສະຖານະ / % / ບັນທຶກ ຂອງວຽກປ່ຽນ → ເກັບເປັນ 1 ລາຍການ
--   ສະມາຊິກເຫັນສະເພາະວຽກຂອງຕົນເອງ, Admin ເຫັນທັງໝົດ
-- ວິທີໃຊ້: SQL Editor → New query → ວາງທັງໝົດ → Run (ແລ່ນຊ້ຳໄດ້)
-- =========================================================

create table if not exists public.task_updates (
  id            bigint generated always as identity primary key,
  task_id       uuid not null references public.tasks(id) on delete cascade,
  author        uuid references public.profiles(id) on delete set null,
  kind          text not null default 'update' check (kind in ('create', 'update')),
  status        text not null,
  progress      integer not null,
  prev_progress integer,
  note          text not null default '' check (char_length(note) <= 2000),
  created_at    timestamptz not null default now()
);
create index if not exists task_updates_task_idx on public.task_updates (task_id, created_at desc);

alter table public.task_updates enable row level security;
drop policy if exists "task updates read" on public.task_updates;
create policy "task updates read" on public.task_updates
  for select to authenticated
  using (public.is_admin()
         or exists (select 1 from public.tasks t where t.id = task_id and t.assignee = auth.uid()));
-- ບໍ່ມີ policy insert/update/delete → ເຂົ້າໄດ້ສະເພາະຜ່ານ trigger ຂ້າງລຸ່ມ (ແກ້/ລຶບປະຫວັດບໍ່ໄດ້)

-- ---------- Trigger: ບັນທຶກອັດຕະໂນມັດ ----------
create or replace function public.log_task_update()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  round_note text := nullif(current_setting('lab.round_note', true), '');   -- ຂໍ້ຄວາມ "ຮອບນີ້" ຈາກ update_task_progress
begin
  if tg_op = 'INSERT' then
    insert into task_updates (task_id, author, kind, status, progress, prev_progress, note)
    values (new.id, coalesce(auth.uid(), new.created_by), 'create', new.status, new.progress, null, '');
    return new;
  end if;

  if round_note is not null
     or new.status is distinct from old.status
     or new.progress is distinct from old.progress
     or new.progress_note is distinct from old.progress_note then
    insert into task_updates (task_id, author, kind, status, progress, prev_progress, note)
    values (new.id, auth.uid(), 'update', new.status, new.progress, old.progress,
            coalesce(round_note,
                     case when new.progress_note is distinct from old.progress_note then new.progress_note else '' end));
  end if;
  return new;
end;
$$;
revoke execute on function public.log_task_update() from public, anon, authenticated;

drop trigger if exists tasks_log_insert on public.tasks;
drop trigger if exists tasks_log_update on public.tasks;
create trigger tasks_log_insert after insert on public.tasks
  for each row execute function public.log_task_update();
create trigger tasks_log_update after update on public.tasks
  for each row execute function public.log_task_update();

-- ---------- ອັບເດດຟັງຊັນຂອງສະມາຊິກ: ບັນທຶກ "ສິ່ງທີ່ເຮັດຮອບນີ້" ----------
create or replace function public.update_task_progress(p_id uuid, p_status text, p_progress integer, p_note text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'ກະລຸນາເຂົ້າສູ່ລະບົບ'; end if;
  if p_status not in ('ຕ້ອງເຮັດ', 'ກຳລັງເຮັດ', 'ສຳເລັດແລ້ວ') then raise exception 'ສະຖານະບໍ່ຖືກຕ້ອງ'; end if;
  if char_length(coalesce(p_note, '')) > 2000 then raise exception 'ບັນທຶກຍາວເກີນໄປ'; end if;

  perform set_config('lab.round_note', coalesce(p_note, ''), true);   -- ໃຊ້ໃນ trigger (ສະເພາະ transaction ນີ້)
  update public.tasks
     set status = p_status,
         progress = case when p_status = 'ສຳເລັດແລ້ວ' then 100
                         else greatest(0, least(100, coalesce(p_progress, progress))) end,
         progress_note = case when coalesce(p_note, '') <> '' then p_note else progress_note end
   where id = p_id and (public.is_admin() or assignee = auth.uid());
  if not found then raise exception 'ທ່ານບໍ່ມີສິດອັບເດດວຽກນີ້'; end if;
end;
$$;
revoke execute on function public.update_task_progress(uuid, text, integer, text) from public, anon;
grant  execute on function public.update_task_progress(uuid, text, integer, text) to authenticated;

-- ---------- ເພີ່ມປະຫວັດເລີ່ມຕົ້ນໃຫ້ວຽກທີ່ມີຢູ່ແລ້ວ (ຄັ້ງດຽວ) ----------
insert into public.task_updates (task_id, author, kind, status, progress, prev_progress, note, created_at)
select t.id, t.created_by, 'create', 'ຕ້ອງເຮັດ', 0, null, '', t.created_at
from public.tasks t
where not exists (select 1 from public.task_updates u where u.task_id = t.id);

insert into public.task_updates (task_id, author, kind, status, progress, prev_progress, note, created_at)
select t.id, coalesce(t.updated_by, t.assignee), 'update', t.status, t.progress, 0, t.progress_note, t.updated_at
from public.tasks t
where (t.progress > 0 or t.status <> 'ຕ້ອງເຮັດ' or t.progress_note <> '')
  and not exists (select 1 from public.task_updates u where u.task_id = t.id and u.kind = 'update');
