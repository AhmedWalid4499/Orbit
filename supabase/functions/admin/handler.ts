// The admin page's server side, kept free of imports so it can be tested with a stand-in database
// (scripts/test-admin.mjs). index.ts wires it to the real Supabase client.
//
// Every request must carry the signed-in person's Joshu token, and that person must be in public.admins.
// POST { action: "list" }                                   → every account with its plan, AI use and synced data
// POST { action: "grant", user_id, days | forever, note }   → Pro for a tester or a friend (source "gift")
// POST { action: "revoke", user_id }                        → ends a grant (App Store purchases are refunded by Apple)
// POST { action: "delete", user_id, email }                 → deletes the account and everything synced for it

export const ORIGINS = ["https://ahmedwalid4499.github.io", "http://localhost:8790", "http://127.0.0.1:8790"];

// deno-lint-ignore no-explicit-any
type DB = any;

function respond(req: Request, status: number, body: unknown) {
  const origin = req.headers.get("origin") ?? "";
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "access-control-allow-origin": ORIGINS.includes(origin) ? origin : ORIGINS[0],
      "access-control-allow-headers": "authorization, content-type, apikey, x-client-info",
      "access-control-allow-methods": "POST, OPTIONS",
      "vary": "origin",
    },
  });
}

export async function handle(req: Request, db: DB): Promise<Response> {
  if (req.method === "OPTIONS") return respond(req, 204, null);
  if (req.method !== "POST") return respond(req, 405, { error: "Method not allowed" });

  const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: who } = jwt ? await db.auth.getUser(jwt) : { data: { user: null } };
  const me = who?.user;
  if (!me) return respond(req, 401, { error: "Sign in first." });
  const { data: adminRow } = await db.from("admins").select("user_id").eq("user_id", me.id).maybeSingle();
  if (!adminRow) return respond(req, 403, { error: "This account isn't an admin." });

  let input: Record<string, unknown>;
  try { input = await req.json(); } catch { return respond(req, 400, { error: "Bad request" }); }

  switch (input.action) {
    case "list": return respond(req, 200, await list(db, me.id));
    case "grant": {
      const id = String(input.user_id ?? "");
      if (!id) return respond(req, 400, { error: "Which account?" });
      const forever = input.forever === true;
      const days = Number(input.days ?? 0);
      if (!forever && !(days > 0 && days <= 3650)) return respond(req, 400, { error: "Give Pro for 1 to 3650 days, or for good." });
      // Whole seconds: Joshu 1.42 and earlier can't read dates with fractions of a second.
      const until = forever ? new Date("2100-01-01T00:00:00Z") : new Date(Math.floor((Date.now() + days * 86_400_000) / 1000) * 1000);
      const { data: current } = await db.from("entitlements").select("pro_until, source").eq("user_id", id).maybeSingle();
      // A paid subscription that already runs longer stays as it is.
      if (current?.source === "app_store" && current.pro_until && new Date(current.pro_until) > until) {
        return respond(req, 409, { error: "They already pay for Pro through the App Store for longer than that." });
      }
      const note = String(input.note ?? "").slice(0, 80) || null;
      const { error } = await db.from("entitlements").upsert(
        { user_id: id, pro_until: until.toISOString().replace(".000Z", "Z"), source: "gift", note, updated_at: new Date().toISOString() },
        { onConflict: "user_id" },
      );
      if (error) return respond(req, 500, { error: error.message });
      return respond(req, 200, { ok: true, pro_until: until.toISOString() });
    }
    case "revoke": {
      const id = String(input.user_id ?? "");
      const { data: current } = await db.from("entitlements").select("source").eq("user_id", id).maybeSingle();
      if (!current) return respond(req, 404, { error: "They don't have Pro." });
      if (current.source === "app_store") {
        return respond(req, 409, { error: "They pay through the App Store. Apple handles cancelling and refunds." });
      }
      const { error } = await db.from("entitlements")
        .update({ pro_until: new Date(Math.floor(Date.now() / 1000) * 1000).toISOString().replace(".000Z", "Z"), updated_at: new Date().toISOString() }).eq("user_id", id);
      if (error) return respond(req, 500, { error: error.message });
      return respond(req, 200, { ok: true });
    }
    case "delete": {
      const id = String(input.user_id ?? "");
      if (!id) return respond(req, 400, { error: "Which account?" });
      if (id === me.id) return respond(req, 409, { error: "You can't delete your own account here." });
      const { data: target } = await db.auth.admin.getUserById(id);
      if (!target?.user) return respond(req, 404, { error: "That account doesn't exist any more." });
      // The page asks you to type the email, and the server checks it, so a wrong click can't delete anyone.
      if (String(input.email ?? "").trim().toLowerCase() !== String(target.user.email ?? "").toLowerCase()) {
        return respond(req, 400, { error: "The email doesn't match that account." });
      }
      const { data: isAdmin } = await db.from("admins").select("user_id").eq("user_id", id).maybeSingle();
      if (isAdmin) return respond(req, 409, { error: "That's an admin. Remove them from public.admins first." });
      // Their synced data, Pro record and AI counts go with the account ("on delete cascade").
      const { error } = await db.auth.admin.deleteUser(id);
      if (error) return respond(req, 500, { error: error.message });
      return respond(req, 200, { ok: true });
    }
    default:
      return respond(req, 400, { error: "Unknown action" });
  }
}

async function list(db: DB, myID: string) {
  const users: Record<string, unknown>[] = [];
  for (let page = 1; page <= 50; page++) {
    const { data, error } = await db.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw new Error(error.message);
    users.push(...(data?.users ?? []));
    if ((data?.users ?? []).length < 1000) break;
  }
  const [{ data: ents }, { data: admins }, { data: counts }, { data: usage }] = await Promise.all([
    db.from("entitlements").select("user_id, pro_until, source, product_id, note, updated_at"),
    db.from("admins").select("user_id"),
    db.rpc("admin_record_counts"),
    db.rpc("admin_ai_usage"),
  ]);
  const byID = <T extends { user_id: string }>(rows: T[] | null) => new Map((rows ?? []).map((r) => [r.user_id, r]));
  const ent = byID(ents), adm = byID(admins), rec = byID(counts), ai = byID(usage);
  return {
    me: myID,
    accounts: users.map((u: Record<string, any>) => {
      const e: Record<string, any> | undefined = ent.get(u.id);
      const a: Record<string, any> | undefined = ai.get(u.id);
      return {
        id: u.id,
        email: u.email ?? "",
        name: u.user_metadata?.full_name ?? u.user_metadata?.name ?? "",
        providers: u.app_metadata?.providers ?? (u.app_metadata?.provider ? [u.app_metadata.provider] : []),
        created_at: u.created_at,
        last_sign_in_at: u.last_sign_in_at ?? null,
        confirmed: Boolean(u.email_confirmed_at ?? u.confirmed_at),
        admin: adm.has(u.id),
        pro_until: e?.pro_until ?? null,
        source: e?.source ?? null,
        product_id: e?.product_id ?? null,
        note: e?.note ?? null,
        records: Number(rec.get(u.id)?.records ?? 0),
        ai_today: Number(a?.today ?? 0),
        ai_month: Number(a?.month ?? 0),
      };
    }),
  };
}
