// Joshu's AI server: Pro subscribers' requests go to Claude with Joshu's key, after checking the plan and a
// daily fair-use limit. The app sends the same Messages API body it would send to Anthropic.
import { createClient } from "jsr:@supabase/supabase-js@2";

const MODEL = "claude-opus-5-5";
const DAILY_LIMIT = Number(Deno.env.get("AI_DAILY_LIMIT") ?? "300");

function fail(status: number, message: string) {
  return new Response(JSON.stringify({ type: "error", error: { type: "joshu", message } }),
    { status, headers: { "content-type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return fail(405, "Method not allowed");
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user) return fail(401, "Sign in to your Joshu account first.");

  const { data: ent } = await admin.from("entitlements").select("pro_until").eq("user_id", user.id).maybeSingle();
  if (!ent?.pro_until || new Date(ent.pro_until) < new Date()) return fail(402, "This needs Joshu Pro.");

  const { data: used } = await admin.rpc("bump_ai_usage", { uid: user.id });
  if ((used ?? 0) > DAILY_LIMIT) return fail(429, "You've reached today's fair-use limit for Yuki. It resets tomorrow.");

  // Only Joshu's model, with a sane ceiling on output.
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return fail(400, "Bad request"); }
  body.model = MODEL;
  body.max_tokens = Math.min(Number(body.max_tokens ?? 16000), 32000);

  const headers: Record<string, string> = {
    "content-type": "application/json",
    "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
    "anthropic-version": req.headers.get("anthropic-version") ?? "2023-06-01",
  };
  const beta = req.headers.get("anthropic-beta");
  if (beta) headers["anthropic-beta"] = beta;
  const upstream = await fetch("https://api.anthropic.com/v1/messages", { method: "POST", headers, body: JSON.stringify(body) });
  // Streamed straight through, so replies appear as they're written.
  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "content-type": upstream.headers.get("content-type") ?? "application/json" },
  });
});
