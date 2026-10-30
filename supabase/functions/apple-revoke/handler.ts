// Ends a Sign in with Apple link when someone deletes their Joshu account (Apple requires it for apps that offer it).
// The app gets a fresh authorization code from Apple and posts { code } here, signed in; Apple swaps the code for a
// token, and revoking that token removes Joshu from the person's Apple ID. Nothing is stored.
export type Deps = {
  userFor: (jwt: string) => Promise<{ id: string } | null>;
  clientSecret: (() => Promise<string>) | null;   // null until the Apple secrets are set on the server
  post: (url: string, form: Record<string, string>) => Promise<{ ok: boolean; json: () => Promise<any> }>;
  clientID: string;
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt || !(await deps.userFor(jwt))) return json(401, { error: "Sign in first" });
  let code: unknown;
  try { code = (await req.json()).code; } catch { return json(400, { error: "Bad request" }); }
  if (typeof code !== "string" || !code) return json(400, { error: "Bad request" });
  if (!deps.clientSecret) return json(503, { error: "Sign in with Apple isn't set up on the server" });

  const client_secret = await deps.clientSecret();
  const base = { client_id: deps.clientID, client_secret };
  const token = await deps.post("https://appleid.apple.com/auth/token", { ...base, code, grant_type: "authorization_code" });
  const refresh = token.ok ? (await token.json()).refresh_token : null;
  if (!refresh) return json(502, { error: "Apple didn't accept the code" });
  const revoked = await deps.post("https://appleid.apple.com/auth/revoke", { ...base, token: refresh, token_type_hint: "refresh_token" });
  return revoked.ok ? json(200, { revoked: true }) : json(502, { error: "Apple didn't revoke the token" });
}
