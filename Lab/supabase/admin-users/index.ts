// =========================================================
// Edge Function: admin-users
// ໃຫ້ Admin ສ້າງ / ແກ້ໄຂ / ລຶບ ບັນຊີສະມາຊິກ
// (ໃຊ້ service role key ຢູ່ຝັ່ງ server ເທົ່ານັ້ນ — ບໍ່ຢູ່ໃນໜ້າເວັບ)
//
// ວິທີ deploy: Supabase Dashboard → Edge Functions → Deploy a new function
//              → Via Editor → ຕັ້ງຊື່ "admin-users" → ວາງໂຄ້ດນີ້ → Deploy
// =========================================================
import { createClient } from "npm:@supabase/supabase-js@2";

// ຕ້ອງກົງກັບ EMAIL_DOMAIN ໃນ config.js
const EMAIL_DOMAIN = "lab.local";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

class Fail extends Error {}
const USERNAME_RE = /^[a-z0-9_.]{3,}$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    // ---- ກວດວ່າຜູ້ເອີ້ນເປັນ admin ----
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: { user }, error: authErr } = await admin.auth.getUser(jwt);
    if (authErr || !user) return json({ error: "ກະລຸນາເຂົ້າສູ່ລະບົບ" }, 401);

    const { data: caller } = await admin.from("profiles").select("*").eq("id", user.id).single();
    if (caller?.sys_role !== "admin") return json({ error: "ສະເພາະ Admin ເທົ່ານັ້ນ" }, 403);

    const body = await req.json();
    const action: string = body.action;
    const username = String(body.username ?? "").trim().toLowerCase();
    const name = String(body.name ?? "").trim();
    const roleTitle = String(body.role_title ?? "").trim();
    const password = String(body.password ?? "");
    const sysRole = body.sys_role === "admin" ? "admin" : "member";

    const usernameTaken = async (exceptId?: string) => {
      let q = admin.from("profiles").select("id").eq("username", username);
      if (exceptId) q = q.neq("id", exceptId);
      const { data } = await q;
      return (data?.length ?? 0) > 0;
    };
    const adminCount = async () => {
      const { count } = await admin.from("profiles").select("id", { count: "exact", head: true }).eq("sys_role", "admin");
      return count ?? 0;
    };

    // ---- ສ້າງບັນຊີ ----
    if (action === "create") {
      if (!name) throw new Fail("ກະລຸນາໃສ່ຊື່");
      if (!USERNAME_RE.test(username)) throw new Fail("ຊື່ຜູ້ໃຊ້ຕ້ອງເປັນ a-z, 0-9, _ ຫຼື . ຢ່າງໜ້ອຍ 3 ຕົວ");
      if (password.length < 6) throw new Fail("ລະຫັດຜ່ານຕ້ອງມີຢ່າງໜ້ອຍ 6 ຕົວ");
      if (await usernameTaken()) throw new Fail("ຊື່ຜູ້ໃຊ້ນີ້ມີຄົນໃຊ້ແລ້ວ");

      const { data, error } = await admin.auth.admin.createUser({
        email: `${username}@${EMAIL_DOMAIN}`,
        password,
        email_confirm: true,
        user_metadata: { username, name },
      });
      if (error) throw new Fail(error.message);

      const { error: pErr } = await admin.from("profiles")
        .update({ name, role_title: roleTitle, sys_role: sysRole, must_change: true })
        .eq("id", data.user.id);
      if (pErr) throw new Fail(pErr.message);
      return json({ ok: true, id: data.user.id });
    }

    // ---- ແກ້ໄຂບັນຊີ / ຣີເຊັດລະຫັດ ----
    if (action === "update") {
      const id = String(body.id ?? "");
      const { data: target } = await admin.from("profiles").select("*").eq("id", id).single();
      if (!target) throw new Fail("ບໍ່ພົບບັນຊີນີ້");
      if (!name) throw new Fail("ກະລຸນາໃສ່ຊື່");
      if (!USERNAME_RE.test(username)) throw new Fail("ຊື່ຜູ້ໃຊ້ຕ້ອງເປັນ a-z, 0-9, _ ຫຼື . ຢ່າງໜ້ອຍ 3 ຕົວ");
      if (password && password.length < 6) throw new Fail("ລະຫັດຜ່ານຕ້ອງມີຢ່າງໜ້ອຍ 6 ຕົວ");

      const newRole = id === user.id ? target.sys_role : sysRole; // ປ່ຽນສິດຕົນເອງບໍ່ໄດ້
      if (target.sys_role === "admin" && newRole === "member" && (await adminCount()) <= 1) {
        throw new Fail("ຕ້ອງມີ Admin ຢ່າງໜ້ອຍ 1 ຄົນ");
      }

      const authUpdate: Record<string, unknown> = {};
      if (username !== target.username) {
        if (await usernameTaken(id)) throw new Fail("ຊື່ຜູ້ໃຊ້ນີ້ມີຄົນໃຊ້ແລ້ວ");
        authUpdate.email = `${username}@${EMAIL_DOMAIN}`;
        authUpdate.email_confirm = true;
      }
      if (password) authUpdate.password = password;
      if (Object.keys(authUpdate).length) {
        const { error } = await admin.auth.admin.updateUserById(id, authUpdate);
        if (error) throw new Fail(error.message);
      }

      const { error: pErr } = await admin.from("profiles").update({
        username, name, role_title: roleTitle, sys_role: newRole,
        must_change: password && id !== user.id ? true : target.must_change,
      }).eq("id", id);
      if (pErr) throw new Fail(pErr.message);
      return json({ ok: true });
    }

    // ---- ລຶບບັນຊີ ----
    if (action === "delete") {
      const id = String(body.id ?? "");
      if (id === user.id) throw new Fail("ບໍ່ສາມາດລຶບບັນຊີຂອງຕົນເອງໄດ້");
      const { count } = await admin.from("equipment").select("id", { count: "exact", head: true }).eq("borrower", id);
      if ((count ?? 0) > 0) throw new Fail("ຄົນນີ້ຍັງຢືມອຸປະກອນຢູ່ ກະລຸນາສົ່ງຄືນກ່ອນ");
      const { error } = await admin.auth.admin.deleteUser(id); // profile ຖືກລຶບຕາມ (cascade)
      if (error) throw new Fail(error.message);
      return json({ ok: true });
    }

    throw new Fail("action ບໍ່ຖືກຕ້ອງ");
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return json({ error: msg }, e instanceof Fail ? 400 : 500);
  }
});
