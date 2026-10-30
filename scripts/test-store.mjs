// Tests the Android and Windows sync (windows/src/renderer/src/lib/store.ts) against the stand-in server, the same one
// the Mac's sync test uses: one timestamp per upload, pages of 40. Run: node scripts/test-store.mjs [folder with store.ts and cloud.ts]
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const lib = process.argv[2] ? resolve(process.argv[2]) : join(root, "windows/src/renderer/src/lib");
const tmp = mkdtempSync(join(tmpdir(), "joshu-store-"));
const url = "http://127.0.0.1:8799", USER = "11111111-2222-3333-4444-555555555555";

// The store and cloud code as they ship, with a stand-in for React.
writeFileSync(join(tmp, "react.js"), "export const useSyncExternalStore = () => {}; export const useMemo = (f) => f();");
writeFileSync(join(tmp, "entry.ts"), `export { store } from ${JSON.stringify(join(lib, "store.ts"))};
export { configure, signOut } from ${JSON.stringify(join(lib, "cloud.ts"))};`);
const built = spawnSync(join(root, "android/node_modules/.bin/esbuild"), [join(tmp, "entry.ts"), "--bundle", "--format=esm", "--platform=node",
  `--alias:react=${join(tmp, "react.js")}`, `--outfile=${join(tmp, "out.mjs")}`, "--log-level=error"], { encoding: "utf8" });
if (built.status) { console.error(built.stderr); process.exit(1); }

const memory = new Map();
globalThis.localStorage = {
  getItem: (k) => memory.get(k) ?? null, setItem: (k, v) => memory.set(k, String(v)), removeItem: (k) => memory.delete(k),
  key: (i) => [...memory.keys()][i] ?? null, get length() { return memory.size; },
};
globalThis.window = { addEventListener() {}, removeEventListener() {}, orbit: {} };
const realFetch = fetch, requests = [];
globalThis.fetch = (u, init) => { requests.push(String(u)); return realFetch(u, init); };

const server = spawn("python3", [join(root, "scripts/mock-sync-server.py")], { stdio: "ignore" });
let failed = 0;
const check = (name, ok) => { console.log(`${ok ? "PASS" : "FAIL"}  ${name}`); if (!ok) failed++; };
const seed = async (rows) => {
  const r = await realFetch(`${url}/rest/v1/orbit_records?on_conflict=user_id,id`, {
    method: "POST", headers: { Authorization: "Bearer tok", Prefer: "resolution=merge-duplicates" }, body: JSON.stringify(rows),
  });
  if (!r.ok) throw new Error(`seed ${r.status}`);
};
const task = (i, deleted = false) => ({ id: `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`, user_id: USER, kind: "task", data: { title: `Task ${i}` }, deleted });

try {
  for (let i = 0; i < 40 && !(await realFetch(`${url}/x`).then(() => true, () => false)); i++) await new Promise((r) => setTimeout(r, 100));
  const { store, configure, signOut } = await import(join(tmp, "out.mjs"));
  configure({ url, key: "k" });
  localStorage.setItem("orbit.session", JSON.stringify({ accessToken: "tok", refreshToken: "ref", expiresAt: Date.now() + 3_600_000, userID: USER, email: "test@example.com" }));

  // More than a page, all with one timestamp: exactly what skipped rows on the Mac.
  await seed(Array.from({ length: 130 }, (_, i) => task(i)));
  await store.start();
  check(`Gets everything uploaded together (${store.list("task").length}/130)`, store.list("task").length === 130);
  await store.sync();
  check("A second sync finds nothing new", store.list("task").length === 130);

  await seed(Array.from({ length: 85 }, (_, i) => task(i + 200)));
  await seed([task(3, true)]);
  await store.sync();
  check(`New rows after that arrive too (${store.list("task").length}/214)`, store.list("task").length === 214);
  check("A deletion arrives", !store.get(task(3).id));

  // A device that was already behind: its saved place is past rows it never got, and it catches up once.
  await new Promise((r) => setTimeout(r, 400));   // let the cache save
  const key = `orbit.cache.${USER}`, cache = JSON.parse(localStorage.getItem(key));
  store.stop();
  delete cache.caughtUp; delete cache.cursorID;
  cache.records = Object.fromEntries(Object.entries(cache.records).filter(([id]) => !id.endsWith("0007")));
  cache.records[task(9).id] = { ...cache.records[task(9).id], data: { title: "Stale" } };
  localStorage.setItem(key, JSON.stringify(cache));
  await seed([task(9, true)]);
  await store.start();
  check("A device behind gets what it missed", !!store.get(task(7).id));
  check("…including deletions it missed", !store.get(task(9).id));
  await new Promise((r) => setTimeout(r, 400));
  check("It catches up only once", JSON.parse(localStorage.getItem(key)).caughtUp === true);

  signOut();
  check("Signing out ends this device's session only", requests.some((u) => u.endsWith("/auth/v1/logout?scope=local")));
} catch (e) {
  console.log(`FAIL  ${e.stack}`);
  failed++;
}
server.kill();
rmSync(tmp, { recursive: true, force: true });
console.log(failed ? `${failed} failed` : "All passed");
process.exit(failed ? 1 : 0);
