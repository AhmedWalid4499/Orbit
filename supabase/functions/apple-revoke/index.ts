// See handler.ts. Secrets, from Apple Developer › Keys (a key with Sign in with Apple enabled):
//   APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (the .p8 file's contents)
import { createClient } from "jsr:@supabase/supabase-js@2";
import * as jose from "npm:jose@5.9.6";
import { handle } from "./handler.ts";

const CLIENT_ID = "com.ahmedwalid.orbit";
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const team = Deno.env.get("APPLE_TEAM_ID"), keyID = Deno.env.get("APPLE_KEY_ID"), pem = Deno.env.get("APPLE_PRIVATE_KEY");

async function clientSecret() {
  return await new jose.SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyID! })
    .setIssuer(team!).setSubject(CLIENT_ID).setAudience("https://appleid.apple.com")
    .setIssuedAt().setExpirationTime("5m")
    .sign(await jose.importPKCS8(pem!, "ES256"));
}

Deno.serve((req) => handle(req, {
  userFor: async (jwt) => (await admin.auth.getUser(jwt)).data.user,
  clientSecret: team && keyID && pem ? clientSecret : null,
  post: (url, form) => fetch(url, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(form) }),
  clientID: CLIENT_ID,
}));
