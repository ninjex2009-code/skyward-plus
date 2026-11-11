# Setting up account sync (Firebase)

Skyward Plus syncs your planner, done marks, goals and look between devices
through a free Firebase project that you own. This takes about 10 minutes and
costs nothing (the free "Spark" plan is far more than enough).

Do the steps in this order: Google sign-in and the database have to exist
**before** you add the app in step 4, or the file you download won't contain
their details.

## 1. Create the project

1. Open <https://console.firebase.google.com> and sign in with your Google account.
2. Click **Create a project** (or **Add project**).
3. Name it `Skyward Plus`. Click **Continue**.
4. Turn **off** Google Analytics (not needed). Click **Create project**, then **Continue**.

## 2. Turn on "Sign in with Google"

1. In the left sidebar choose **Build › Authentication**, then **Get started**.
2. Open the **Sign-in method** tab and click **Google**.
3. Switch **Enable** on, pick your email as the **Project support email**, and click **Save**.

## 3. Create the database

1. In the sidebar choose **Build › Realtime Database**, then **Create Database**.
2. Pick **United States** as the location, click **Next**.
3. Choose **Start in locked mode**, click **Enable**.
4. Open the **Rules** tab, replace everything there with the rules below, and click **Publish**.
   They let each signed-in person read and write only their own data.

```json
{
  "rules": {
    "users": {
      "$uid": {
        ".read": "auth != null && auth.uid === $uid",
        ".write": "auth != null && auth.uid === $uid"
      }
    }
  }
}
```

## 4. Register the app and download its settings file

1. Go back to **Project Overview** (top of the sidebar) and click the **iOS+** (Apple) icon to add an app.
2. **Apple bundle ID:** `com.skywardplus.app`. Leave the other fields empty. Click **Register app**.
3. Click **Download GoogleService-Info.plist**. Then click **Next**, **Next**, **Next** and **Continue to console** (you can skip the remaining steps; the app talks to Firebase without its SDK).

## 5. Hand it over

Tell Claude where the file is (it usually lands in **Downloads**), or move it to
`app/SkywardPlus/Resources/GoogleService-Info.plist` yourself.

The file is not a password: it names your project, and the database rules in
step 3 are what keep each person's data private.
