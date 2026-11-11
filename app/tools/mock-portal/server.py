#!/usr/bin/env python3
"""A stand-in for a district sign-in portal plus a signed-in Skyward page, for
testing "Stay signed in" without touching a real district.

  python3 server.py [port]

  /__reset?mode=twostep|wrongpass|baduser|single   start a scenario
  /__log                                            what the app submitted

The only account is teststudent / test-pass-123. Nothing here is real.
"""
import json, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

USER, PASS = "teststudent", "test-pass-123"
BASE, STS = "/MockISDStu/", "/MockISDStuSTS/Session/Signin"
state = {"mode": "twostep", "signedIn": False, "log": []}

SKYWARD_SIGNED_IN = """<!doctype html><title>Mock Skyward</title>
<button id="myAccountButton">Test Student</button><a id="signOutButton" href="#">Sign Out</a>
<h1>Gradebook</h1>"""

SKYWARD_SIGN_IN = """<!doctype html><title>Sign In</title>
<h1>Mock ISD</h1><p>Sign in to Skyward</p>
<a href="/portal/">Sign In with Mock SSO</a>"""

TWO_STEP = """<!doctype html><title>Mock Portal</title>
<div id="view"></div><p id="error" style="color:#b00"></p>
<script>
const view = document.getElementById('view'), error = document.getElementById('error');
async function post(path, body) {
  const r = await fetch(path, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
  return r.json();
}
function step1() {
  view.innerHTML = `<form onsubmit="return false">
    <button type="button">Sign in with QR code</button>
    <input id="identification" type="text" placeholder="Username">
    <button type="button" aria-label="Help">?</button>
    <button id="authn-go-button" type="button" disabled>Go</button></form>`;
  const input = document.getElementById('identification'), go = document.getElementById('authn-go-button');
  // Like the real thing, Go only wakes up a beat after typing.
  input.addEventListener('input', () => setTimeout(() => { go.disabled = !input.value; }, 60));
  go.addEventListener('click', async () => {
    const r = await post('/portal/api/user', {user: input.value});
    if (r.ok) step2(); else { error.textContent = 'Unknown username'; input.value = ''; go.disabled = true; }
  });
}
function step2() {
  error.textContent = '';
  view.innerHTML = `<form onsubmit="return false">
    <input type="password" id="password" placeholder="Password">
    <button type="button">Show</button>
    <button type="button">Forgot password</button>
    <button id="authn-go-button" type="button" disabled>Go</button></form>`;
  const input = document.getElementById('password'), go = document.getElementById('authn-go-button');
  input.addEventListener('input', () => setTimeout(() => { go.disabled = !input.value; }, 60));
  go.addEventListener('click', async () => {
    const r = await post('/portal/api/pass', {pass: input.value});
    if (r.ok) location.href = '%s' + 'Grading/StudentSection/StudentAccess';
    else { error.textContent = 'Invalid password'; input.value = ''; go.disabled = true; }
  });
}
step1();
</script>""" % BASE

SINGLE = """<!doctype html><title>Mock Portal</title>
<p style="color:#b00">%s</p>
<form method="post" action="/portal/login">
  <button type="button">English</button>
  <input type="text" name="username" placeholder="Username">
  <input type="password" name="password" placeholder="Password">
  <button type="button">Show</button>
  <input type="submit" value="Log In">
</form>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, body, code=200, kind="text/html; charset=utf-8", headers=None):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(data)

    def redirect(self, where):
        self.send("", 302, headers={"Location": where})

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        if url.path == "/__reset":
            state.update(mode=query.get("mode", ["twostep"])[0], signedIn=False, log=[])
            return self.send("ok", kind="text/plain")
        if url.path == "/__log":
            return self.send(json.dumps(state["log"]), kind="application/json")
        if url.path.startswith(BASE):
            return self.send(SKYWARD_SIGNED_IN) if state["signedIn"] else self.redirect(STS)
        if url.path == STS:
            return self.send(SKYWARD_SIGN_IN)
        if url.path == "/portal/":
            if state["mode"] == "single":
                return self.send(SINGLE % ("Invalid username or password" if "error" in query else ""))
            return self.send(TWO_STEP)
        self.send("not found", 404, "text/plain")

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        if self.path == "/portal/api/user":
            user = json.loads(raw).get("user", "")
            ok = user == USER and state["mode"] != "baduser"
            state["log"].append({"step": "user", "matches": user == USER, "accepted": ok})
            return self.send(json.dumps({"ok": ok}), kind="application/json")
        if self.path == "/portal/api/pass":
            ok = json.loads(raw).get("pass", "") == PASS and state["mode"] != "wrongpass"
            state["log"].append({"step": "pass", "accepted": ok})
            state["signedIn"] = ok
            return self.send(json.dumps({"ok": ok}), kind="application/json")
        if self.path == "/portal/login":
            form = urllib.parse.parse_qs(raw)
            ok = form.get("username", [""])[0] == USER and form.get("password", [""])[0] == PASS
            state["log"].append({"step": "login", "hasUser": bool(form.get("username")), "accepted": ok})
            state["signedIn"] = ok
            return self.redirect(BASE + "Grading/StudentSection/StudentAccess" if ok else "/portal/?error=1")
        self.send("not found", 404, "text/plain")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8791
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
