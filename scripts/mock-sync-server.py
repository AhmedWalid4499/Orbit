# Stand-in sync server for the sync test: ORBIT_SYNC_TEST=1 ORBIT_SUPABASE_URL=http://127.0.0.1:8799 build/Orbit.app/Contents/MacOS/Orbit
# (quit Joshu first). It pages like the real one: one timestamp per upload, small pages.
# Minimal stand-in for Supabase Auth + PostgREST, enough to exercise Orbit's sync engine.
import http.server, json, datetime, urllib.parse, threading
USER = "11111111-2222-3333-4444-555555555555"
USER2 = "99999999-8888-7777-6666-555555555555"
TOKENS = {"tok": USER, "tok2": USER2}
rows = {}
lock = threading.Lock()
calls = []
refresh_answer = [0]   # set by /test/refresh: how the next token refreshes are answered (0: normally)
def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
class H(http.server.BaseHTTPRequestHandler):
    def _send(self, code, obj=None):
        body = b"" if obj is None else json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        u = urllib.parse.urlparse(self.path); n = int(self.headers.get("Content-Length", 0)); data = json.loads(self.rfile.read(n) or b"null")
        calls.append(("POST", u.path, u.query, self.headers.get("Prefer")))
        if u.path == "/test/refresh":
            refresh_answer[0] = data["status"]; return self._send(200)
        if u.path.startswith("/rest/v1/rpc/delete_my_account"):
            who = TOKENS.get((self.headers.get("Authorization") or "")[7:]); assert who, "missing user token"
            with lock:
                for k in [k for k in rows if k[0] == who]: del rows[k]
            return self._send(204)
        if u.path.startswith("/auth/v1/token"):
            if "refresh_token" in u.query and refresh_answer[0]:
                return self._send(refresh_answer[0], {} if refresh_answer[0] == 200 else {"msg": "refused"})
            other = isinstance(data, dict) and data.get("email") == "other@example.com"
            return self._send(200, {"access_token": "tok2" if other else "tok", "refresh_token": "ref", "expires_in": 3600,
                                    "user": {"id": USER2 if other else USER, "email": "other@example.com" if other else "test@example.com"}})
        if u.path.startswith("/auth/v1/logout"): return self._send(204)
        if u.path == "/rest/v1/orbit_records":
            who = TOKENS.get((self.headers.get("Authorization") or "")[7:]); assert who, "missing user token"
            assert "on_conflict=user_id,id" in u.query and "merge-duplicates" in (self.headers.get("Prefer") or "")
            batch = data if isinstance(data, list) else [data]
            ids = [r["id"].lower() for r in batch]   # ids are uuids on the real server: upper and lower case are one id
            if len(ids) != len(set(ids)): return self._send(500, {"message": "ON CONFLICT DO UPDATE command cannot affect row a second time"})
            with lock:
                batch_ts = now()
                for r in batch:
                    assert r["user_id"] == who, "row for another account"
                    r = dict(r); r["updated_at"] = batch_ts; r["id"] = r["id"].lower()
                    rows[(r["user_id"], r["id"])] = r
            return self._send(201)
        self._send(404, {"message": "not found"})
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); q = urllib.parse.parse_qs(u.query)
        calls.append(("GET", u.path, u.query, None))
        if u.path == "/rest/v1/orbit_records":
            who = TOKENS.get((self.headers.get("Authorization") or "")[7:])
            out = sorted([r for r in rows.values() if r["user_id"] == who], key=lambda r: (r["updated_at"], r["id"]))
            if "id" in q:
                want = q["id"][0][3:]
                out = [r for r in out if r["id"] == want]
            if "updated_at" in q:
                cur = q["updated_at"][0]
                if cur.startswith("gt."): out = [r for r in out if r["updated_at"] > cur[3:]]
                elif cur.startswith("gte."): out = [r for r in out if r["updated_at"] >= cur[4:]]
                else: raise AssertionError(cur)
            if "or" in q:
                import re as _re
                m = _re.match(r'\(updated_at\.gt\."([^"]+)",and\(updated_at\.eq\."([^"]+)",id\.gt\."([^"]+)"\)\)', q["or"][0])
                assert m, q["or"][0]
                ts, _, last = m.groups()
                out = [r for r in out if r["updated_at"] > ts or (r["updated_at"] == ts and r["id"] > last)]
            if "limit" in q: out = out[: min(int(q["limit"][0]), 40)]   # pages of 40, so uploads span page boundaries
            return self._send(200, [{k: r[k] for k in ("id", "kind", "data", "deleted", "updated_at")} for r in out])
        self._send(404, {"message": "not found"})
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 8799), H)
try: srv.serve_forever()
finally: pass
