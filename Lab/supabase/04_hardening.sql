-- =========================================================
-- Lab Manager — ອັບເດດ #4: ເພີ່ມຄວາມປອດໄພກ່ອນ deploy
-- ວິທີໃຊ້: SQL Editor → New query → ວາງທັງໝົດ → Run (ແລ່ນຊ້ຳໄດ້)
-- =========================================================

-- ສີໝວດໝູ່ຕ້ອງເປັນ #rrggbb ເທົ່ານັ້ນ (ກັນການແຊກໂຄ້ດຜ່ານຊ່ອງສີ)
update public.categories set color = '#6366f1' where color !~ '^#[0-9a-fA-F]{6}$';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'categories_color_hex') then
    alter table public.categories add constraint categories_color_hex check (color ~ '^#[0-9a-fA-F]{6}$');
  end if;

  -- ຊື່ໄຟລ໌ຮູບຕ້ອງເປັນແບບທີ່ລະບົບສ້າງ (uuid.jpg)
  if not exists (select 1 from pg_constraint where conname = 'equipment_image_path_safe') then
    alter table public.equipment add constraint equipment_image_path_safe
      check (image_path is null or image_path ~ '^[0-9a-fA-F-]{36}\.jpg$') not valid;
  end if;

  -- ຈຳກັດຄວາມຍາວຂໍ້ຄວາມ (ກັນການ spam ຂໍ້ມູນຂະໜາດໃຫຍ່)
  if not exists (select 1 from pg_constraint where conname = 'history_text_len') then
    alter table public.history add constraint history_text_len check (char_length(text) <= 500) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'tasks_text_len') then
    alter table public.tasks add constraint tasks_text_len
      check (char_length(title) <= 200 and char_length(detail) <= 5000 and char_length(progress_note) <= 2000) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'equipment_text_len') then
    alter table public.equipment add constraint equipment_text_len
      check (char_length(name) <= 200 and char_length(code) <= 50 and char_length(coalesce(note, '')) <= 2000) not valid;
  end if;
end $$;

-- ປິດການເອີ້ນຟັງຊັນພາຍໃນຈາກພາຍນອກ (ໃຊ້ໄດ້ສະເພາະພາຍໃນຖານຂໍ້ມູນ)
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.touch_task()      from public, anon, authenticated;
