// Keeps Joshu Pro in step with the App Store.
// 1. The app posts { signedTransaction } after a purchase or when it checks (signed in, so we know the account).
// 2. Apple posts App Store Server Notifications V2 { signedPayload } on renewals, expiries and refunds.
// Everything Apple sends is a JWS signed with a certificate chain that must end at Apple Root CA - G3.
import { createClient } from "jsr:@supabase/supabase-js@2";
import * as jose from "npm:jose@5.9.6";
import { X509Certificate } from "npm:@peculiar/x509@1.12.3";

const APPLE_ROOT_G3_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";
const BUNDLES = ["com.ahmedwalid.orbit", "com.personal.orbit"];
const PRODUCTS = ["joshu.pro.monthly", "joshu.pro.yearly"];

async function sha256(bytes: ArrayBuffer) {
  const d = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/// Verifies an Apple JWS (chain up to Apple's root, then the signature) and returns its payload.
async function verifyApple(jws: string): Promise<Record<string, any>> {
  const header = jose.decodeProtectedHeader(jws);
  const chain = (header.x5c ?? []).map((c) => new X509Certificate(c));
  if (chain.length < 3) throw new Error("bad chain");
  if (await sha256(chain[chain.length - 1].rawData) !== APPLE_ROOT_G3_SHA256) throw new Error("not Apple's root");
  for (let i = 0; i < chain.length - 1; i++) {
    const ok = await chain[i].verify({ publicKey: await chain[i + 1].publicKey.export(), date: new Date() });
    if (!ok) throw new Error("chain broken");
  }
  const key = await jose.importX509(chain[0].toString("pem"), header.alg ?? "ES256");
  const { payload } = await jose.compactVerify(jws, key);
  return JSON.parse(new TextDecoder().decode(payload));
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  let input: Record<string, string>;
  try { input = await req.json(); } catch { return json(400, { error: "Bad request" }); }

  try {
    if (input.signedTransaction) {
      // From the app: tie the purchase to the signed-in account.
      const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
      const { data: { user } } = await admin.auth.getUser(jwt);
      if (!user) return json(401, { error: "Sign in first" });
      const t = await verifyApple(input.signedTransaction);
      if (!BUNDLES.includes(t.bundleId) || !PRODUCTS.includes(t.productId)) return json(400, { error: "Not a Joshu Pro purchase" });
      const until = t.revocationDate ? new Date() : new Date(t.expiresDate ?? 0);
      await admin.from("entitlements").upsert({
        user_id: user.id, pro_until: until.toISOString(), source: "app_store", product_id: t.productId,
        original_transaction_id: String(t.originalTransactionId), updated_at: new Date().toISOString(),
      });
      return json(200, { pro_until: until.toISOString() });
    }

    if (input.signedPayload) {
      // From Apple: a renewal, an expiry or a refund for a subscription we already know.
      const note = await verifyApple(input.signedPayload);
      const signed = note.data?.signedTransactionInfo;
      if (!signed) return json(200, { ok: true });
      const t = await verifyApple(signed);
      if (!BUNDLES.includes(t.bundleId)) return json(200, { ok: true });
      const ended = ["EXPIRED", "REFUND", "REVOKE", "GRACE_PERIOD_EXPIRED"].includes(note.notificationType);
      const until = ended || t.revocationDate ? new Date() : new Date(t.expiresDate ?? 0);
      const row: Record<string, unknown> = { pro_until: until.toISOString(), product_id: t.productId, updated_at: new Date().toISOString() };
      // appAccountToken is the Joshu account the purchase was made from (set by the app).
      if (t.appAccountToken) {
        await admin.from("entitlements").upsert({ user_id: t.appAccountToken, source: "app_store",
          original_transaction_id: String(t.originalTransactionId), ...row });
      } else {
        await admin.from("entitlements").update(row).eq("original_transaction_id", String(t.originalTransactionId));
      }
      return json(200, { ok: true });
    }
  } catch (e) {
    return json(400, { error: String(e) });
  }
  return json(400, { error: "Nothing to do" });
});
