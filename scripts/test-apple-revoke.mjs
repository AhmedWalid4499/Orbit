// Tests the Sign in with Apple revoke function (supabase/functions/apple-revoke/handler.ts) against a stand-in Apple.
// Run: node scripts/test-apple-revoke.mjs
import { handle } from "../supabase/functions/apple-revoke/handler.ts";

let failed = 0;
const check = (name, ok) => { console.log(`${ok ? "PASS" : "FAIL"}  ${name}`); if (!ok) failed++; };
const request = (body, token = "good", method = "POST") => new Request("http://x/", {
  method, headers: token ? { Authorization: `Bearer ${token}` } : {}, body: method === "POST" ? JSON.stringify(body) : undefined,
});
function deps({ tokenOK = true, revokeOK = true, secret = true } = {}) {
  const calls = [];
  return {
    calls, clientID: "app.id",
    userFor: async (jwt) => (jwt === "good" ? { id: "u1" } : null),
    clientSecret: secret ? async () => "signed" : null,
    post: async (url, form) => {
      calls.push({ url, form });
      const ok = url.endsWith("/token") ? tokenOK : revokeOK;
      return { ok, json: async () => ({ refresh_token: "ref" }) };
    },
  };
}

let d = deps();
let r = await handle(request({ code: "c" }), d);
check("Revokes with a good code", r.status === 200 && (await r.json()).revoked === true);
check("Swaps the code first", d.calls[0]?.url.endsWith("/auth/token") && d.calls[0].form.code === "c" && d.calls[0].form.grant_type === "authorization_code");
check("Then revokes the refresh token", d.calls[1]?.url.endsWith("/auth/revoke") && d.calls[1].form.token === "ref" && d.calls[1].form.token_type_hint === "refresh_token");
check("Signs both with the client secret", d.calls.every((c) => c.form.client_secret === "signed" && c.form.client_id === "app.id"));
d = deps();
check("Needs a sign-in", (await handle(request({ code: "c" }, "bad"), d)).status === 401 && d.calls.length === 0);
check("Needs no token at all to refuse", (await handle(request({ code: "c" }, null), deps())).status === 401);
check("Needs a code", (await handle(request({}), deps())).status === 400);
check("Only POST", (await handle(request(null, "good", "GET"), deps())).status === 405);
check("Says so when Apple isn't set up", (await handle(request({ code: "c" }), deps({ secret: false }))).status === 503);
check("Reports a refused code", (await handle(request({ code: "c" }), deps({ tokenOK: false }))).status === 502);
check("Reports a failed revoke", (await handle(request({ code: "c" }), deps({ revokeOK: false }))).status === 502);
console.log(failed ? `${failed} failed` : "All passed");
process.exit(failed ? 1 : 0);
