# Skyward Plus

A Mac app for Skyward grades. It signs in to your school district's own
Skyward page and shows your grades, assignments, GPA, schedule and attendance
in one place, with a menu bar view, alerts for new grades and a what-if
calculator.

This is a beta. It is not affiliated with or endorsed by Skyward.

## Install

1. Download the latest `Skyward-Plus-x.y.dmg` from [Releases](../../releases).
2. Open it and drag **Skyward Plus** onto **Applications**.
3. The app is not signed with a paid Apple developer account, so macOS blocks
   it the first time. Allow it once, either way:
   - Double-click **Allow Skyward Plus.command** in the disk image, or run
     this in Terminal:

     ```bash
     xattr -dr com.apple.quarantine "/Applications/Skyward Plus.app"
     ```
   - Or open the app, click Done on the warning, then go to System Settings >
     Privacy & Security and click **Open Anyway**.

Needs macOS 14 Sonoma or newer. Works on Apple silicon and Intel Macs.

## What it does

- Grades for every class and marking period, with category weights and each
  assignment's score
- What-if grades, class goals and "what do I need on the next test"
- GPA (weighted and unweighted), report cards, schedule, attendance
- Planner that mixes Skyward due dates with your own tasks
- Menu bar view, background sync, and notifications for new grades, work due
  tomorrow and classes that drop below their goal
- Search everything with Command-K
- Due dates copied to Reminders or Calendar, and a PDF grade report
- Checks this repository's releases for updates

## Privacy

Everything stays on your Mac. Your password is typed into your district's own
sign-in page; if you choose "Stay signed in" it is stored in the macOS
Keychain. Nothing is sent anywhere except your school district's Skyward.

## Build from source

Requires Xcode 16 or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd app
xcodegen generate
open SkywardPlus.xcodeproj
```

`app/tools/make-dmg.sh` builds the universal release and the disk image into
`app/dist/`. Tests: the `CoreTests` scheme.

## Chrome extension

The repository root also holds the original **Skyward+** Chrome extension
(`manifest.json`, `src/`, `popup/`, `dashboard/`), which reads the gradebook
from the Skyward page in your browser. Load it from `chrome://extensions` with
Developer mode on and **Load unpacked**.
