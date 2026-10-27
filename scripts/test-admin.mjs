// Tests the admin server function (supabase/functions/admin/handler.ts) against a stand-in database.
// Run: node scripts/test-admin.mjs
import { handle } from "../supabase/functions/admin/handler.ts";

const OWNER = "aaaaaaaa-0000-0000-0000-000000000001", TESTER = "bbbbbbbb-0000-0000-0000-000000000002",
  PAYER = "cccccccc-0000-0000-0000-000000000003";
const tables = {
  admins: [{ user_id: OWNER }],
  entitlements: [{ user_id: PAYER, pro_until: "2099-01-01T00:00:00Z", source: "app_store", product_id: "joshu.pro.yearly", note: null }],
};
const users = [
  { id: OWNER, email: "owner@example.com", created_at: "2026-10-01T00:00:00Z", app_metadata: { providers: ["google"] }, email_confirmed_at: "x" },
  { id: TESTER, email: "tester@example.com", created_at: "2026-10-02T00:00:00Z", app_metadata: { provider: "email" } },
  { id: PAYER, email: "payer@example.com", created_at: "2026-10-03T00:00:00Z", app_metadata: { providers: ["email"] } },
];
const tokens = { "owner-token": OWNER, "tester-token": TESTER };

function query(table) {
  let rows = tables[table] ?? [];
  const b = {
    select() { return b; },
    eq(col, val) { rows = rows.filter((r) => r[col] === val); return b; },
    maybeSingle: async () => ({ data: rows[0] ?? null }),
    then(ok) { return Promise.resolve({ data: rows }).then(ok); },
    upsert: async (row) => {
      const all = tables[table];
      const i = all.findIndex((r) => r.user_id === row.user_id);
      if (i >= 0) all[i] = { ...all[i], ...row }; else all.push(row);
      return { error: null };
    },
    update: (vals) => ({
      eq: async (col, val) => { for (const r of tables[table]) if (r[col] === val) Object.assign(r, vals); return { error: null }; },
    }),
  };
  return b;
}
const db = {
  auth: {
    getUser: async (jwt) => ({ data: { user: tokens[jwt] ? { id: tokens[jwt] } : null } }),
    admin: {
      listUsers: async ({ page }) => ({ data: { users: page === 1 ? users : [] }, error: null }),
      getUserById: async (id) => ({ data: { user: users.find((u) => u.id === id) ?? null } }),
      deleteUser: async (id) => { users.splice(users.findIndex((u) => u.id === id), 1); return { error: null }; },
    },
  },
  from: query,
  rpc: async (name) => ({
    data: name === "admin_record_counts" ? [{ user_id: OWNER, records: 442 }] : [{ user_id: OWNER, today: 12, month: 310 }],
  }),
};

async function call(body, token = "owner-token", method = "POST") {
  const req = new Request("https://x/functions/v1/admin", {
    method, headers: { origin: "https://ahmedwalid4499.github.io", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
  const res = await handle(req, db);
  return { status: res.status, body: res.status === 204 ? null : await res.json(), cors: res.headers.get("access-control-allow-origin") };
}

let failed = 0;
function check(name, ok) { console.log(`${ok ? "PASS" : "FAIL"}  ${name}`); if (!ok) failed++; }

check("Browser preflight is allowed", (await call(null, null, "OPTIONS")).status === 204);
check("No sign-in is refused", (await call({ action: "list" }, null)).status === 401);
check("A non-admin is refused", (await call({ action: "list" }, "tester-token")).status === 403);
const list = await call({ action: "list" });
const owner = list.body.accounts?.find((a) => a.id === OWNER);
check("Lists every account", list.status === 200 && list.body.accounts.length === 3);
check("Shows synced data and AI use", owner?.records === 442 && owner?.ai_today === 12 && owner?.ai_month === 310 && owner?.admin === true);
check("Shows a paying subscriber", list.body.accounts.find((a) => a.id === PAYER)?.source === "app_store");
check("CORS answers the website", list.cors === "https://ahmedwalid4499.github.io");
const grant = await call({ action: "grant", user_id: TESTER, days: 30, note: "Beta tester" });
const t = tables.entitlements.find((e) => e.user_id === TESTER);
check("Gives a tester Pro for 30 days", grant.status === 200 && t?.source === "gift" && t?.note === "Beta tester"
  && Math.abs(new Date(t.pro_until) - Date.now() - 30 * 86_400_000) < 60_000);
check("Bad grant length is refused", (await call({ action: "grant", user_id: TESTER, days: 0 })).status === 400);
check("Won't shorten a paid subscription", (await call({ action: "grant", user_id: PAYER, days: 5 })).status === 409);
check("Won't revoke an App Store purchase", (await call({ action: "revoke", user_id: PAYER })).status === 409);
const revoke = await call({ action: "revoke", user_id: TESTER });
check("Ends a tester's Pro", revoke.status === 200 && new Date(t.pro_until) <= new Date());
const forever = await call({ action: "grant", user_id: TESTER, forever: true, note: "Friend" });
const t2 = tables.entitlements.find((e) => e.user_id === TESTER);
check("Gives Pro for good", forever.status === 200 && t2.pro_until.startsWith("2100") && t2.note === "Friend");
check("Delete needs the right email", (await call({ action: "delete", user_id: TESTER, email: "someone@else.com" })).status === 400 && users.length === 3);
check("Can't delete yourself", (await call({ action: "delete", user_id: OWNER, email: "owner@example.com" })).status === 409);
const del = await call({ action: "delete", user_id: TESTER, email: "Tester@Example.com" });
check("Deletes an account", del.status === 200 && users.length === 2 && !users.some((u) => u.id === TESTER));
check("A deleted account can't be deleted twice", (await call({ action: "delete", user_id: TESTER, email: "tester@example.com" })).status === 404);
check("Unknown action is refused", (await call({ action: "drop_tables" })).status === 400);
process.exit(failed ? 1 : 0);
