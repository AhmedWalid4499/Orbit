// See handler.ts. Secrets (scripts/setup-wallet-pass.sh sets them):
//   PASS_TYPE_ID   the Pass Type ID, e.g. pass.com.ahmedwalid.joshu.card
//   PASS_TEAM_ID   your Apple team ID
//   PASS_CERT      the Pass Type ID certificate, PEM
//   PASS_KEY       its private key, PEM (PASS_KEY_PASSWORD if it's encrypted)
import { createClient } from "jsr:@supabase/supabase-js@2";
import { zipSync } from "npm:fflate@0.8.2";
import { handle } from "./handler.ts";
import { makeSigner } from "./sign.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const typeID = Deno.env.get("PASS_TYPE_ID"), teamID = Deno.env.get("PASS_TEAM_ID");
const cert = Deno.env.get("PASS_CERT"), key = Deno.env.get("PASS_KEY");

let signer: Awaited<ReturnType<typeof setUp>> = null;
async function setUp() {
  if (!typeID || !teamID || !cert || !key) return null;
  // Apple's Worldwide Developer Relations G4 intermediate, which every pass signature must include.
  const wwdr = new Uint8Array(await (await fetch("https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer")).arrayBuffer());
  return { passTypeID: typeID, teamID, sign: makeSigner(cert, key, wwdr, Deno.env.get("PASS_KEY_PASSWORD") ?? undefined) };
}
const ready = setUp().then((s) => { signer = s; }).catch(() => { signer = null; });

Deno.serve(async (req) => {
  await ready;
  return handle(req, {
    userFor: async (jwt) => (await admin.auth.getUser(jwt)).data.user,
    signer,
    zip: (files) => zipSync(files, { level: 6 }),
  });
});
