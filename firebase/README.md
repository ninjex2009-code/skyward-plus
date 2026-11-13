# Firebase rules for Skyward Plus account sync

Everyone who signs in with Google shares one Firebase project, so the
Realtime Database rules must keep each person inside their own folder.
Skyward Plus only ever reads and writes `users/<their uid>/…`.

To apply (once, in the Firebase console):

1. Open your project → **Build → Realtime Database → Rules**.
2. Replace everything with the contents of `database.rules.json`.
3. Click **Publish**.

With these rules a signed-in person can read and write only their own
`users/<uid>` data; nobody can list or read anyone else's, and signed-out
requests get nothing.

Study groups (`groups/…`, `invites/…`) follow their own rules: only members can
read a group; joining needs the group's invite code and fails once 8 people are
in; only the owner can rename it, remove people or delete it; and each member
can share or remove only their own class averages. Re-publish the rules after
updating Skyward Plus to 1.6.

# Google Calendar (one-time setup)

Skyward Plus copies due dates into a "Skyward Plus" calendar using Google's
narrowest calendar permission (`calendar.app.created`: only calendars the app
creates). Google needs two switches turned on in the same Google Cloud project
your Firebase project uses:

1. Open https://console.cloud.google.com and pick the Firebase project.
2. **APIs & Services → Library** → search "Google Calendar API" → **Enable**.
3. **APIs & Services → OAuth consent screen → Data access** → **Add or remove
   scopes** → add `https://www.googleapis.com/auth/calendar.app.created` → Save.
4. Under **Audience**: while the app is in *Testing*, only listed test users can
   connect, so add each friend's Google address there (up to 100). Or choose
   *Publish app*; Google then shows an "unverified app" warning until the app
   is verified.

Then in Skyward Plus: Settings → Syncing → Google Calendar → Connect.
