# Phase 0 — the push spike

**Do this before anything else, and do not build on top of a broken update path.**

The entire product rests on one question:

> With the app force quit and the phone locked, does a push repaint the right cat on the
> right pinned widget within 5 seconds?

Everything else — auth, groups, the mood grid, the whole backend — is replaceable. This
is not. If it fails, stop and report rather than working around it.

---

## What you need

- **Two physical devices** on iOS 18 or later. The simulator does not receive real pushes,
  and it is exactly the force-quit-and-locked case that a simulator cannot tell you
  anything about.
- The App ID, App Group and APNs `.p8` from the README's "Do these first".
- A Mac with Xcode 16+.

Supabase is *not* involved in Phase 0. No auth, no network from the app, no real UI.

---

## Setup

### 1. Configure the spike script

```bash
cp Scripts/.env.example Scripts/.env
$EDITOR Scripts/.env
```

```bash
APNS_P8_PATH=/secure/path/outside/this/repo/AuthKey_ABC1234567.p8
APNS_KEY_ID=ABC1234567
APNS_TEAM_ID=DEF7654321
APNS_BUNDLE_ID=com.huydao.moodcats     # the MAIN app id, not the widget's
APNS_ENV=sandbox                        # Xcode builds are Debug, so: sandbox
```

`Scripts/.env` and `*.p8` are both gitignored. Keep the `.p8` outside the repo anyway.

### 2. Build to both devices

Run the `MoodCats` scheme on each. The app requests provisional notification
authorization after you join a group — for Phase 0, trigger it from Settings, or just let
onboarding run.

### 3. Grab each device token

`AppDelegate` logs it on every launch, and DEBUG builds log the hex itself:

```
APNs token registered (sandbox).
APNs device token: 8f3a...
```

No temporary `print` is needed -- the second line is already there, marked
`privacy: .public` so it is not redacted to `<private>`, and compiled out of Release so a
real user's token never lands in a log. Read it from the Xcode console or from Console.app
filtered by `com.huydao.moodcats`. It is 64 hex characters. **Copy the hex, not the
debugger's `<32 bytes>` form.**

### 4. Add a widget on device B

Long press the Home Screen → **+** → search MoodCats → add the **small** widget.

The friend picker reads the App Group roster blob, which is empty until the first push
lands. So: fire one push first (step 5), *then* long press the widget → **Edit Widget** →
pick Kim.

---

## Fire it

```bash
./Scripts/push_spike.sh <device-b-token> 2 Kim     # 2 = sleepy
```

The script signs an ES256 provider token (caching it 50 minutes, the same window the Edge
Function uses), builds the exact payload `set-mood` produces, checks it against the 4 KB
APNs limit, and POSTs over HTTP/2.

Change the mood id to watch the widget move:

```bash
./Scripts/push_spike.sh <token> 0 Kim    # happy
./Scripts/push_spike.sh <token> 6 Kim    # excited
```

---

## Acceptance

All three must pass.

### 1. Force quit, locked, under 5 seconds

Swipe the app away from the app switcher on device B. Lock the phone. Fire the curl.

**Pass:** the pinned widget shows the sleepy cat within 5 seconds, without unlocking.

This is the whole point of the Notification Service Extension: it runs even when the app
is dead.

### 2. Fifty pushes across a day, no degradation

Not fifty in a row — spread them out, with the phone idle and locked between. iOS
throttles extensions that misbehave, and a rate that looks fine in a burst can decay over
hours.

**Pass:** the fiftieth is as prompt as the first.

### 3. Provisional authorization fires the NSE

This is the open question Phase 0 exists to close.

The app requests `.provisional`, which grants without ever showing a prompt and delivers
quietly. Combined with `interruption-level: passive`, that is what stops notification
fatigue from killing the update path. But it is only worth anything if the NSE still runs.

On a device where notifications were **never** explicitly allowed — fresh install, no
prompt answered — fire a push and watch the widget.

**Pass:** the widget updates.

**Fail:** switch to full authorization. In `NotificationManager`, call
`requestFullAuthorization()` instead of `requestProvisionalAuthorization()` from
`AppModel.afterJoiningGroup()`. Keep `interruption-level: passive` in the payload so
delivery stays quiet. **Record the result here either way** — this is the kind of thing
that gets re-litigated in six months.

> Result: _not yet run_

---

## Also worth checking now

Cheap here, expensive to discover in Phase 3:

| Check | How |
|---|---|
| Out of order pushes are ignored | `MOODCATS_T=1600000000000 ./Scripts/push_spike.sh <token> 3 Kim` — an old `t`. The widget must **not** change. |
| Lock Screen vibrant mode | Add the circular and rectangular widgets to the Lock Screen. Vibrant desaturates everything; the art is already monochrome vector so this should be free — verify rather than assume. |
| Low Power Mode | Enable it, fire a push. Updates may be delayed but must arrive. |
| Airplane mode | Enable, fire a push, wait, disable. The queued push must land and apply. |

---

## When it does not work

The push was accepted by APNs (HTTP 200) but nothing happened:

1. **Is the App Group entitlement on the widget?** This is the single most common cause
   and Xcode will not warn you. `RosterStore` logs a `fault` when the suite is
   unavailable. `ruby Tools/verify_project.rb` checks it statically.
2. **Console.app**, filtered by `com.huydao.moodcats.notificationservice`. Widget and
   extension logs do not reliably reach the Xcode console. For NSE breakpoints, use
   Xcode → Debug → **Attach to Process by PID**.
3. **Is `mutable-content: 1` present?** Without it the NSE never runs. The script always
   sends it.

APNs rejected the push:

| Reason | Fix |
|---|---|
| `BadDeviceToken` | Token is from the other environment. Flip `APNS_ENV`. Debug builds get sandbox tokens. |
| `TopicDisallowed` | `apns-topic` must be the **main app** bundle id, not the widget's. |
| `ExpiredProviderToken` | `rm $TMPDIR/moodcats_apns_jwt_*` and rerun. |
| `Unregistered` | The app was deleted from that device. Reinstall and grab a fresh token. |
| `InvalidProviderToken` | Key ID, Team ID or `.p8` mismatch. Check all three. |
