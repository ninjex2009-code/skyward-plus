#!/usr/bin/env python3
"""Adds a release to the AltStore / SideStore source (altstore/source.json).

Usage: tools/make-altstore-source.py <version> <build> <ipa-path> <notes-file>

The source lists every version, newest first; AltStore and SideStore offer the
newest one as an update. The IPA itself is downloaded from the GitHub release.
"""
import datetime, json, os, sys

REPO = "ninjex2009-code/skyward-plus"
RAW = f"https://raw.githubusercontent.com/{REPO}/main/altstore"

def main():
    version, build, ipa, notes_file = sys.argv[1:5]
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    path = os.path.join(root, "altstore", "source.json")
    with open(notes_file) as f:
        notes = f.read().strip()
    source = json.load(open(path)) if os.path.exists(path) else None
    if source is None:
        source = {
            "name": "Skyward Plus",
            "identifier": "com.skywardplus.source",
            "subtitle": "Your Skyward grades, beautifully.",
            "iconURL": f"{RAW}/icon.png",
            "website": f"https://github.com/{REPO}",
            "tintColor": "#7C5CFF",
            "apps": [{
                "name": "Skyward Plus",
                "bundleIdentifier": "com.skywardplus.app",
                "developerName": "Skyward Plus",
                "subtitle": "Grades, planner and alerts for Skyward.",
                "localizedDescription": "A friendly, fast app for Skyward grades: every class at a glance, what's missing or due, alerts for new grades, a planner, GPA tools and living background themes.",
                "iconURL": f"{RAW}/icon.png",
                "tintColor": "#7C5CFF",
                "category": "education",
                "versions": [],
                "appPermissions": {
                    "entitlements": [],
                    "privacy": {"NSFaceIDUsageDescription": "Skyward Plus uses Face ID to keep your grades private."},
                },
            }],
            "news": [],
        }
    app = source["apps"][0]
    entry = {
        "version": version,
        "buildVersion": build,
        "date": datetime.date.today().isoformat(),
        "localizedDescription": notes,
        "downloadURL": f"https://github.com/{REPO}/releases/download/v{version}/Skyward-Plus-{version}.ipa",
        "size": os.path.getsize(ipa),
        "minOSVersion": "17.0",
    }
    app["versions"] = [entry] + [v for v in app["versions"] if v["version"] != version]
    with open(path, "w") as f:
        json.dump(source, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"altstore/source.json: {version} ({build}), {len(app['versions'])} version(s)")

if __name__ == "__main__":
    main()
