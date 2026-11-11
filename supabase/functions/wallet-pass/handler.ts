// Makes your Joshu card into an Apple Wallet pass (.pkpass). The app posts the card, signed in; this builds pass.json,
// lists every file with its SHA-1 in manifest.json, signs the manifest with the Pass Type ID certificate (kept as a
// server secret, never in the app), zips it all and sends the pass back. Nothing is stored.
export type Card = {
  name: string; headline?: string; company?: string; email?: string; phone?: string; location?: string; bio?: string;
  links?: { title: string; url: string; handle?: string }[];
};
export type Body = { card: Card; qr?: string; color?: string; images?: Record<string, string> };
export type Deps = {
  userFor: (jwt: string) => Promise<{ id: string } | null>;
  /** null until the pass certificate is set up on the server */
  signer: { passTypeID: string; teamID: string; sign: (manifest: Uint8Array) => Promise<Uint8Array> } | null;
  zip: (files: Record<string, Uint8Array>) => Uint8Array;
};

const ALLOWED_IMAGES = new Set(["icon.png", "icon@2x.png", "icon@3x.png", "logo.png", "logo@2x.png", "logo@3x.png",
  "thumbnail.png", "thumbnail@2x.png", "thumbnail@3x.png"]);

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

async function sha1Hex(data: Uint8Array) {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-1", data));
  return Array.from(d, (b) => b.toString(16).padStart(2, "0")).join("");
}

function fromBase64(s: string) {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** "#E6FF1F" → "rgb(230, 255, 31)"; text goes dark on light colours. */
function colors(hex?: string) {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex ?? "");
  const v = m ? parseInt(m[1], 16) : 0x141416;
  const r = (v >> 16) & 255, g = (v >> 8) & 255, b = v & 255;
  const light = 0.299 * r + 0.587 * g + 0.114 * b > 150;
  return {
    backgroundColor: `rgb(${r}, ${g}, ${b})`,
    foregroundColor: light ? "rgb(17, 17, 17)" : "rgb(255, 255, 255)",
    labelColor: light ? "rgb(60, 60, 67)" : "rgb(200, 200, 205)",
  };
}

const clip = (s: unknown, n = 300) => (typeof s === "string" ? s.trim().slice(0, n) : "");
const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export function passJSON(body: Body, userID: string, passTypeID: string, teamID: string) {
  const c = body.card;
  const name = clip(c.name, 80) || "My card";
  const secondary = [
    clip(c.headline, 80) && { key: "headline", label: "ROLE", value: clip(c.headline, 80) },
    clip(c.company, 80) && { key: "company", label: "COMPANY", value: clip(c.company, 80) },
  ].filter(Boolean);
  const auxiliary = [
    clip(c.email, 120) && { key: "email", label: "EMAIL", value: clip(c.email, 120) },
    clip(c.phone, 40) && { key: "phone", label: "PHONE", value: clip(c.phone, 40) },
  ].filter(Boolean);
  const back: Record<string, string>[] = [];
  if (clip(c.bio, 500)) back.push({ key: "bio", label: "About", value: clip(c.bio, 500) });
  if (clip(c.location, 80)) back.push({ key: "location", label: "Based in", value: clip(c.location, 80) });
  (c.links ?? []).slice(0, 12).forEach((l, i) => {
    const url = clip(l.url, 300);
    if (!/^(https?:|mailto:|tel:)/i.test(url)) return;
    const shown = clip(l.handle, 120) || url.replace(/^https?:\/\/(www\.)?/i, "");
    back.push({ key: `link${i}`, label: clip(l.title, 40) || "Link", value: shown, attributedValue: `<a href="${esc(url)}">${esc(shown)}</a>` });
  });
  back.push({ key: "made", label: "", value: "Made with Joshu" });
  const qr = clip(body.qr, 2000);
  const ascii = /^[\x00-\x7F]*$/.test(qr);
  return {
    formatVersion: 1,
    passTypeIdentifier: passTypeID,
    teamIdentifier: teamID,
    serialNumber: `card-${userID}`,
    organizationName: "Joshu",
    description: `${name}'s card`,
    logoText: name,
    ...colors(body.color),
    sharingProhibited: false,
    generic: {
      primaryFields: [{ key: "name", label: clip(c.location, 40).toUpperCase(), value: name }],
      secondaryFields: secondary,
      auxiliaryFields: auxiliary,
      backFields: back,
    },
    ...(qr ? { barcodes: [{ format: "PKBarcodeFormatQR", message: qr, messageEncoding: ascii ? "iso-8859-1" : "utf-8", altText: "Scan to save my contact" }] } : {}),
  };
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  // The app asks first, so it only shows "Add to Apple Wallet" once passes can really be made.
  if (req.method === "GET") return json(200, { ready: !!deps.signer });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const user = jwt ? await deps.userFor(jwt) : null;
  if (!user) return json(401, { error: "Sign in first" });
  if (!deps.signer) return json(503, { error: "Wallet passes aren't set up on the server yet" });
  const raw = await req.text();
  if (raw.length > 3_000_000) return json(413, { error: "Card is too large" });
  let body: Body;
  try { body = JSON.parse(raw); } catch { return json(400, { error: "Bad request" }); }
  if (!body?.card || typeof body.card.name !== "string") return json(400, { error: "Bad request" });

  const files: Record<string, Uint8Array> = {};
  for (const [name, b64] of Object.entries(body.images ?? {})) {
    if (!ALLOWED_IMAGES.has(name) || typeof b64 !== "string") continue;
    try { files[name] = fromBase64(b64); } catch { /* skip a bad image */ }
  }
  if (!files["icon.png"]) return json(400, { error: "The pass needs an icon" });
  files["pass.json"] = new TextEncoder().encode(JSON.stringify(passJSON(body, user.id, deps.signer.passTypeID, deps.signer.teamID)));

  const manifest: Record<string, string> = {};
  for (const [name, data] of Object.entries(files)) manifest[name] = await sha1Hex(data);
  const manifestBytes = new TextEncoder().encode(JSON.stringify(manifest));
  files["manifest.json"] = manifestBytes;
  files["signature"] = await deps.signer.sign(manifestBytes);

  return new Response(deps.zip(files), {
    status: 200,
    headers: { "content-type": "application/vnd.apple.pkpass", "content-disposition": 'attachment; filename="card.pkpass"' },
  });
}
