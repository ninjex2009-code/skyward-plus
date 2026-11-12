#!/usr/bin/env python3
"""A stand-in for a district sign-in portal plus a signed-in Skyward page, for
testing "Stay signed in" without touching a real district.

  python3 server.py [port]

  /__reset?mode=twostep|wrongpass|baduser|single   start a sign-in scenario
  /__reset?mode=gradebook                           start signed in, at the gradebook
  /__log                                            what the app submitted

The only account is teststudent / test-pass-123. Nothing here is real.
"""
import json, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

USER, PASS = "teststudent", "test-pass-123"
BASE, STS = "/MockISDStu/", "/MockISDStuSTS/Session/Signin"
state = {"mode": "twostep", "signedIn": False, "log": [], "mobile": False, "screenWidth": 1280}

# A signed-in Qmlativ gradebook, built from the selectors the app's page script
# reads. Like a responsive site, the class panel becomes a full-screen
# position:fixed overlay when the page is narrow.
CLASSES = [("1001", "AP CALCULUS BC", "1", ["93", "94", "94", "95"]),
           ("1002", "AP ENGLISH LITERATURE", "2", ["90", "91", "92", "93"]),
           ("1003", "SYMPHONIC BAND", "8", ["99", "99", "100", ""])]
LITS = ["PR1", "Q1", "PR2", "Q2"]

def gradebook():
    head = "".join('<td class="%s">%s</td>' % ("progressReportDetailsOpenHeader" if lit == "Q2" else "", lit) for lit in LITS)
    rows = []
    for section, name, period, grades in CLASSES:
        cells = "".join(
            '<td class="linkPanelCell" data-student-grade-bucket-id="b%s%s"><a href="#">%s</a></td>' % (section, lit, g) if g else "<td></td>"
            for lit, g in zip(LITS, grades))
        rows.append('<tr><td><a data-studentsectionid="%s" data-studentid="77" data-coursedescription="%s">'
                    '<span class="visualLabel">%s</span><span class="visualLabel">Period %s</span></a></td><td>Teacher</td>%s</tr>'
                    % (section, name, name, period, cells))
    return (GRADEBOOK.replace("{HEAD}", head).replace("{ROWS}", "".join(rows))
            .replace("{MOBILE}", "true" if state["mobile"] else "false"))

GRADEBOOK = """<!doctype html><title>Gradebook</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { font: 14px -apple-system, sans-serif; margin: 0; }
  #detailsPanel { display: none; background: #fff; }
  #detailsPanel.open { display: block; position: absolute; top: 0; right: 0; width: 460px; }
  @media (max-width: 800px) { #detailsPanel.open { position: fixed; inset: 0; width: auto; } }
</style>
<script>window.skyward = { global: { mobileAccess: {MOBILE}, mobileAccessEmulation: false } };</script>
<button id="myAccountButton">Test Student</button> <a id="signOutButton" href="/MockISDStu/signout">Sign Out</a>
<p>Current Missing Assignments: 1</p>
<div class="browse">
  <table><tr class="unlockedHeaderTableRow"><td>Class</td><td>Teacher</td>{HEAD}</tr></table>
  <table class="unlockedBrowseTable">{ROWS}</table>
</div>
<div id="detailsPanel"></div>
<script>
document.querySelectorAll('td.linkPanelCell a').forEach(a => a.addEventListener('click', e => {
  e.preventDefault();
  // Like Skyward: a session signed in at phone width never opens the side panel.
  if (window.skyward.global.mobileAccess) return;
  const cell = a.closest('td');
  const xhr = new XMLHttpRequest();
  xhr.open('GET', '/MockISDStu/api/bucket?id=' + cell.dataset.studentGradeBucketId);
  xhr.onload = () => {
    document.querySelectorAll('.linkPanelCell--active').forEach(c => c.classList.remove('linkPanelCell--active'));
    cell.classList.add('linkPanelCell--active');
    const panel = document.getElementById('detailsPanel');
    panel.innerHTML = xhr.responseText;
    panel.classList.add('open');
  };
  setTimeout(() => xhr.send(), 150);
}));
</script>"""

PANEL = """<a href="#"><span class="anchorText">Dana Whitfield</span></a>
<span class="visualLabel">Period 1</span><span class="visualLabel">{LIT}</span>
<span class="visualLabel">10/13/2026 - 12/18/2026</span><span class="visualLabel">95.1%</span>
<span class="gradeMarkLabel">A</span>
<div id="GradeBucketAssignmentsSegmentedOuterContainer"></div>
<div class="browse"><table class="unlockedBrowseTable">
  <tr class="sf_ParentRow"><td class="column0">Major</td><td class="column1"></td><td class="column2">A</td><td class="column3">95</td><td class="column4">190/200</td><td class="column5"></td></tr>
  <tr><td class="column0">Unit 3 Exam</td><td class="column1">10/23/2026</td><td class="column2">A</td><td class="column3">94</td><td class="column4">94/100</td><td class="column5">1</td></tr>
  <tr><td class="column0">Related Rates Test</td><td class="column1">11/04/2026</td><td class="column2">A</td><td class="column3">96</td><td class="column4">96/100</td><td class="column5">1</td></tr>
  <tr class="sf_ParentRow"><td class="column0">Minor</td><td class="column1"></td><td class="column2">A</td><td class="column3">95.3</td><td class="column4">81/85</td><td class="column5"></td></tr>
  <tr><td class="column0">FRQ Set</td><td class="column1">10/20/2026</td><td class="column2">A</td><td class="column3">95</td><td class="column4">19/20</td><td class="column5">1</td></tr>
</table></div>"""

# Like Skyward's: the window size goes along with the sign-in (set at page ready).
SKYWARD_SIGN_IN = """<!doctype html><title>Sign In</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<h1>Mock ISD</h1><p>Sign in to Skyward</p>
<form id="f" method="post" action="/MockISDStuSTS/sso">
  <input type="hidden" id="ScreenWidth" name="ScreenWidth" value="0">
  <input type="hidden" id="ScreenHeight" name="ScreenHeight" value="0">
</form>
<button type="button" onclick="document.getElementById('f').submit()">Sign In with Mock SSO</button>
<script>
document.addEventListener('DOMContentLoaded', () => setTimeout(() => {
  document.getElementById('ScreenWidth').value = window.innerWidth;
  document.getElementById('ScreenHeight').value = window.innerHeight;
}, 0));
</script>"""

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
            mode = query.get("mode", ["twostep"])[0]
            # "gradebook" starts signed in, for testing what happens after sign-in.
            # "mobile" starts signed in to a session made at phone width.
            state.update(mode=mode, signedIn=mode in ("gradebook", "mobile"), log=[],
                         mobile=mode == "mobile", screenWidth=1280)
            return self.send("ok", kind="text/plain")
        if url.path == "/__log":
            return self.send(json.dumps(state["log"]), kind="application/json")
        if url.path == BASE + "api/bucket":
            lit = query.get("id", ["b0000Q2"])[0][5:]
            return self.send(PANEL.replace("{LIT}", lit))
        if url.path == BASE + "signout":
            state["signedIn"] = False
            state["log"].append({"step": "signout"})
            return self.redirect(STS)
        if url.path.startswith(BASE):
            return self.send(gradebook()) if state["signedIn"] else self.redirect(STS)
        if url.path == STS:
            return self.send(SKYWARD_SIGN_IN)
        if url.path == "/portal/":
            if state["mode"] == "single":
                return self.send(SINGLE % ("Invalid username or password" if "error" in query else ""))
            return self.send(TWO_STEP)
        self.send("not found", 404, "text/plain")

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        if self.path == "/MockISDStuSTS/sso":
            form = urllib.parse.parse_qs(raw)
            width = int(float(form.get("ScreenWidth", ["0"])[0] or 0))
            state["screenWidth"] = width
            state["log"].append({"step": "sso", "screenWidth": width})
            return self.redirect("/portal/")
        if self.path == "/portal/api/user":
            user = json.loads(raw).get("user", "")
            ok = user == USER and state["mode"] != "baduser"
            state["log"].append({"step": "user", "matches": user == USER, "accepted": ok})
            return self.send(json.dumps({"ok": ok}), kind="application/json")
        if self.path == "/portal/api/pass":
            ok = json.loads(raw).get("pass", "") == PASS and state["mode"] != "wrongpass"
            state["log"].append({"step": "pass", "accepted": ok})
            state["signedIn"] = ok
            if ok: state["mobile"] = state["screenWidth"] < 768
            return self.send(json.dumps({"ok": ok}), kind="application/json")
        if self.path == "/portal/login":
            form = urllib.parse.parse_qs(raw)
            ok = form.get("username", [""])[0] == USER and form.get("password", [""])[0] == PASS
            state["log"].append({"step": "login", "hasUser": bool(form.get("username")), "accepted": ok})
            state["signedIn"] = ok
            if ok: state["mobile"] = state["screenWidth"] < 768
            return self.redirect(BASE + "Grading/StudentSection/StudentAccess" if ok else "/portal/?error=1")
        self.send("not found", 404, "text/plain")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8791
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
