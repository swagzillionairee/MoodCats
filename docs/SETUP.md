# Setup, from nothing

Everything between a fresh Mac and a MoodCats build running on your phone, in order.
Nothing here has been done yet.

Roughly 20 minutes of clicking, then however long the first compile takes to go green.

**Expect the first build to fail.** This code has never been through a compiler — it was
written in a Linux container with no Xcode, no Swift toolchain and no iOS SDK. Step 5 is
where that gets sorted out, and it is a normal part of this, not a sign something is
wrong.

---

## 1. Enable anonymous sign-ins — Supabase, 30 seconds

This is the one hard blocker. Without it the app cannot get past its first screen.

1. Go to <https://supabase.com/dashboard/project/zewojsliyfgmraoxgndc>
2. **Authentication** in the left sidebar
3. **Sign In / Providers**
4. Find **Anonymous Sign-Ins**, turn it on, **Save**

To confirm it took, from any terminal:

```bash
curl -s -X POST 'https://zewojsliyfgmraoxgndc.supabase.co/auth/v1/signup' \
  -H "apikey: $(grep -o 'eyJ[A-Za-z0-9_.-]*' Shared/Config.swift | head -1)" \
  -H 'Content-Type: application/json' -d '{}' | head -c 200
```

- Before: `{"code":422,"error_code":"anonymous_provider_disabled",...}`
- After: a JSON blob containing `access_token`

**This does not add a sign-in screen.** It is a server capability. The app calls it
invisibly on first launch; the user just types a name.

---

## 2. Create the APNs key — Apple, 3 minutes

Only needed for *other people's* phones to update. Skip it for now if you just want to
see the app run — everything except cross-device push works without it.

1. <https://developer.apple.com/account/resources/authkeys/list>
2. **+** to create a key
3. Name it something like `MoodCats APNs`
4. Tick **Apple Push Notifications service (APNs)**
5. **Continue → Register → Download**

> **The `.p8` file downloads exactly once.** There is no second chance. If you lose it you
> must revoke the key and create a new one. Save it somewhere outside this repo —
> `.gitignore` blocks `*.p8`, but do not lean on that.

Write down three things:

| Value | Where to find it |
|---|---|
| **Key ID** | 10 characters, shown on the key page and in the filename: `AuthKey_ABC1234567.p8` |
| **Team ID** | 10 characters, top right of the developer portal, or Membership |
| **Bundle ID** | `com.huydao.moodcats` unless you changed the prefix |

You do **not** need to create App IDs or the App Group by hand — Xcode registers those
for you in step 4 when automatic signing is on.

---

## 3. Get the code and set your Team ID

```bash
git clone <your repo url> MoodCats
cd MoodCats
open Config/Signing.xcconfig
```

Set one line:

```
DEVELOPMENT_TEAM = ABC1234567
```

That single file drives signing for all three targets. Leave it blank and Xcode will just
ask you to pick a team instead — either is fine, but setting it here is one edit rather
than three.

If you want a different bundle prefix, change `BUNDLE_ID_PREFIX` here **and** the matching
literals in `Shared/Config.swift`. The App Group id has to match exactly in both places,
or the widget renders empty and Xcode will not warn you about it.

---

## 4. Open the project

```bash
open MoodCats.xcodeproj
```

Xcode 16 or later, since the deployment target is iOS 18.

1. Wait for **supabase-swift** to resolve (status bar, first open only).
2. Select the **MoodCats** scheme and your device as the destination.
3. Check **Signing & Capabilities** on each of the three targets — `MoodCats`,
   `MoodCatsWidget`, `MoodCatsNotificationService`:
   - **Automatically manage signing** ticked, your team selected
   - **App Groups** shows `group.com.huydao.moodcats`, ticked, on **all three**
   - `MoodCats` alone also has **Push Notifications** and
     **Background Modes → Remote notifications**

   The App Group being missing from one target is the single most common way this app
   breaks, and it fails silently — the widget just renders empty forever. Worth thirty
   seconds of eyeballing.

If Xcode shows a red "team not found" or "no profiles" error, click **Try Again** — it
registers the App IDs and the App Group with Apple on your behalf.

---

## 5. Build, and send me the errors

⌘B.

This is the step that has never been exercised. Copy whatever the compiler says — the
whole error list, not just the first one — and paste it back to me. I will fix them.

Once it builds, ⌘R onto a real device (the simulator cannot receive push, so it is not
much use here beyond checking layout).

**What works at this point, with no APNs key at all:**

- onboarding, create group, join group
- the mood grid
- the group screen, settings, delete my data
- **your own** widget updating the moment you tap a mood — `set-mood` hands the roster
  straight back in its response and the app writes it to the App Group

**What does not work yet:** other people's phones updating. That is push, and it needs
step 6.

The Edge Function reports this honestly rather than failing — check the response header
`x-moodcats-push-note: apns_not_configured`.

---

## 6. Add the APNs secrets — Supabase

1. <https://supabase.com/dashboard/project/zewojsliyfgmraoxgndc/settings/functions>
2. **Edge Function Secrets**, add four:

```
APNS_KEY_ID       ABC1234567
APNS_TEAM_ID      DEF7654321
APNS_BUNDLE_ID    com.huydao.moodcats
APNS_PRIVATE_KEY  <the ENTIRE .p8 file, including the BEGIN and END lines>
```

For the private key, `cat AuthKey_ABC1234567.p8` and paste the whole thing, newlines and
all. The function tolerates the literal `\n` that dashboard fields sometimes introduce,
but real newlines are better.

No redeploy needed — secrets are read at invocation.

The service role key belongs *only* here, never in the Xcode project.
`Tools/verify_project.rb` fails if it ever shows up there.

---

## 7. Phase 0 — the push spike

**Do not skip this, and do not build features on top of a broken update path.** The whole
product rests on one question: with the app force quit and the phone locked, does a push
repaint the right cat on the right widget within 5 seconds?

```bash
cp Scripts/.env.example Scripts/.env
$EDITOR Scripts/.env          # the same four values as step 6, plus the .p8 path
```

Get your device token: run the app from Xcode and look for this in the console (it is
`#if DEBUG` only, so it never appears in a Release build):

```
APNs device token: a1b2c3d4...
```

Then:

```bash
./Scripts/push_spike.sh <that-token> 2 Kim     # 2 = sleepy
```

Full procedure, acceptance criteria and a troubleshooting table are in
**[PHASE0.md](PHASE0.md)**. The three things that must pass:

1. App force quit, phone locked → correct cat within 5 seconds
2. Fifty pushes across a day, no degradation
3. **Provisional authorization actually fires the Notification Service Extension**

Number 3 is a genuine open question that no amount of reading resolves. If it fails,
switch `AppModel.prepareForGroupLife()` from `requestProvisionalAuthorization()` to
`requestFullAuthorization()` and keep `interruption-level: passive` so delivery stays
quiet. Both paths already exist in `NotificationManager`.

---

## 8. Two devices, real accounts

The actual acceptance test for the product:

1. Device A: create a group, note the code
2. Device B: join with that code
3. Device B: add the small widget, long press → **Edit Widget** → pick A
4. Force quit MoodCats on device B, lock it
5. Device A: tap a mood

B's widget should repaint within 5 seconds without B ever being unlocked or opened.

Then work through **[TESTING.md](TESTING.md)** — 13 rows, ordered by how likely each is
to break.

---

## Reference

| Thing | Value |
|---|---|
| Supabase project | `moodcats`, ref `zewojsliyfgmraoxgndc`, us-east-1 |
| Dashboard | <https://supabase.com/dashboard/project/zewojsliyfgmraoxgndc> |
| App bundle id | `com.huydao.moodcats` |
| Widget bundle id | `com.huydao.moodcats.widget` |
| NSE bundle id | `com.huydao.moodcats.notificationservice` |
| App Group | `group.com.huydao.moodcats` |
| Widget kind | `MoodWidget` |
| Deep link | `moodcats://friend/<profile uuid>` |

```bash
ruby Tools/verify_project.rb      # 66 structural checks, run after touching the project
ruby Tools/generate_xcodeproj.rb  # regenerate the project after adding a source file
python3 Tools/make_catalogs.py    # regenerate the asset catalogs and app icon
```
