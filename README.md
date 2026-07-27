# MoodCats

A friend group shares moods through cat art on each other's home screens.

Pick a name, create a group or join one with a 6 character code, tap one of 8 cat moods.
Everyone else in the group gets a quiet notification, and any widget they have pinned to
you repaints to the new cat within seconds. Each widget instance is pinned to exactly one
friend — want to watch four friends, add four widgets.

Built to [MoodCats Technical Specification v1.0](#).

---

## Status

| Layer | State |
|---|---|
| Supabase project, schema, RLS, 8 RPCs | **Done and verified** against the live project |
| `set-mood` Edge Function | **Deployed**, verified end to end over HTTP |
| Shared data contract, iOS app, widget, Notification Service Extension | **Written**, not yet compiled — needs Xcode |
| Cat faces (kaomoji) | **Done** — text, no image assets anywhere |
| Phase 0 push spike | **Tooling ready**, needs two physical devices |

**Nothing here has been run on an iPhone.** This was built in a Linux container with no
Xcode, no Swift toolchain and no iOS SDK, so the Swift compiles in theory and not yet in
practice. Everything that *could* be verified without hardware was:
`ruby Tools/verify_project.rb` runs 68 structural checks, and the backend was exercised
against the real project over real HTTP.

---

## Do these first

**Full click-by-click walkthrough: [docs/SETUP.md](docs/SETUP.md).** Summary below.

Five things block a first build. Three are Apple, one is Supabase, one is a paste.

### 1. Enable anonymous sign-ins (Supabase) — **hard blocker**

The whole onboarding flow is anonymous auth, and it is **off by default**. Confirmed
against the live project:

```
POST /auth/v1/signup → 422 {"error_code":"anonymous_provider_disabled"}
```

Dashboard → **Authentication → Sign In / Providers → Anonymous Sign-Ins → enable**.
There is no API for this, so it could not be done from here.

### 2. Apple Developer portal

| Thing | Where | Notes |
|---|---|---|
| App ID `com.huydao.moodcats` with App Groups + Push Notifications | developer.apple.com → Identifiers | Also create the two extension App IDs, `.widget` and `.notificationservice` |
| App Group `group.com.huydao.moodcats` | developer.apple.com → Identifiers → App Groups | Must match `APP_GROUP_ID` in `Config/Signing.xcconfig` and `Config.appGroupID` in `Shared/Config.swift` |
| APNs auth key (`.p8`) | developer.apple.com → Keys → new key with APNs enabled | **The `.p8` downloads exactly once.** Lose it and you revoke and start over. Store it outside this repo — `.gitignore` blocks `*.p8`, but do not rely on that |

### 3. Team ID into the project

Open `Config/Signing.xcconfig` and set `DEVELOPMENT_TEAM` to your 10 character Team ID.
That one file drives signing for all three targets. If you want a different bundle
prefix, change `BUNDLE_ID_PREFIX` there **and** the matching literals in
`Shared/Config.swift` — the App Group id in particular must match exactly, or the widget
renders empty and Xcode will not warn you.

### 4. Edge Function secrets (Supabase)

Dashboard → **Edge Functions → Secrets**:

```
APNS_KEY_ID       ABC1234567                    # from the .p8 filename
APNS_TEAM_ID      DEF7654321
APNS_PRIVATE_KEY  -----BEGIN PRIVATE KEY-----   # full .p8 contents, BEGIN/END lines included
APNS_BUNDLE_ID    com.huydao.moodcats           # the MAIN app id, NOT the widget's
```

Until these are set the function still works — it writes the mood and returns the roster,
so the caller's own widgets update — but it skips the fanout and reports
`x-moodcats-push-note: apns_not_configured`. That is deliberate, so the app is testable
before the APNs key exists.

The service role key belongs *only* here. It must never appear in the iOS project;
`Tools/verify_project.rb` fails the build if it does.

### 5. Open the project

```bash
open MoodCats.xcodeproj
```

Xcode resolves `supabase-swift` on first open.

---

## Then: Phase 0

**Do not skip it, and do not build on top of a broken update path.** The whole product
rests on one question: with the app force quit and the phone locked, does a push repaint
the right cat on the right widget within 5 seconds?

`Scripts/push_spike.sh` answers it without Supabase, auth or app logic in the way. Full
procedure and acceptance criteria in **[docs/PHASE0.md](docs/PHASE0.md)**.

```bash
cp Scripts/.env.example Scripts/.env    # then fill it in
./Scripts/push_spike.sh <device-token> 2 Kim
```

Phase 0 also has to answer one open question that no amount of reading resolves:
**does provisional authorization actually fire the Notification Service Extension?**
If it does not, switch to full `[.alert, .badge, .sound]` and keep
`interruption-level: passive` to stay quiet. `NotificationManager` already has both
paths.

---

## Layout

```
Shared/                     compiled into ALL THREE targets
  Config.swift              project url, anon key, App Group id, widget kind
  Mood.swift                the 8 moods; ids are stable forever
  RosterContract.swift      the shared data contract (spec section 9)
  RosterStore.swift         App Group read/write, monotonic write rule
  CatFaceView.swift         app + widget only (the NSE renders nothing)

MoodCats/                   the app
  AppModel.swift            the whole state machine
  Services/                 Supabase boundary, notifications, error mapping
  Views/                    the 7 screens from spec section 12.1

MoodCatsWidget/             AppIntentConfiguration, EntityQuery, all 5 states
MoodCatsNotificationService/  the part that runs when the app is force quit

supabase/
  migrations/               10 migrations, applied to the live project
  functions/set-mood/       the only metered code path

Tools/                      project generation, asset catalogs, verification
Scripts/                    Phase 0 spike, demo group seed
docs/                       setup walkthrough, Phase 0 procedure, test matrix
```

### The three files that must agree

The mood table lives in `Shared/Mood.swift` **and**
`supabase/functions/set-mood/moods.ts`. Ids are array indices and are stable forever —
append only, never reorder. `Tools/verify_project.rb` diffs them.

The roster shape is defined once, in SQL, by `public.roster_for()`. `get_roster`, the
`set-mood` response and the APNs payload all come out of that one function, so there is a
single clock and a single definition. `Roster` in `RosterContract.swift` is the Swift
mirror.

---

## How an update travels

```
User A taps "sleepy"
  └─> POST /functions/v1/set-mood            (JWT authed, one invocation, fans out in a loop)
        ├─ apply_mood()  — rate limit, mood write, roster read, recipient tokens: ONE round trip
        ├─ sign APNs JWT (ES256, cached 50 min in module scope)
        ├─ POST to APNs per token, routed by the stored environment column
        ├─ DELETE tokens that come back 410 Unregistered
        └─ return the roster to the caller
  ├─> A writes the returned roster to the App Group and reloads its own widgets
  │     (instant; there is deliberately no self push)
  └─> B..H receive the push
        └─ Notification Service Extension fires BEFORE the banner
             ├─ validate v, decode roster
             ├─ write to App Group only if incoming t > stored t
             ├─ reloadTimelines(ofKind: "MoodWidget")
             └─ deliver the notification, passively
```

The widget never makes a network request. Its only data source is App Group storage.
That is why the **full roster** ships in every push: a missed push is repaired by the next
one, and new members show up in the widget's friend picker without an app launch.

---

## Things that will silently break this

Spec section 16, plus what testing actually found. Most are enforced by
`ruby Tools/verify_project.rb` (68 checks) — run it after touching the project.

1. The App Group entitlement must be on **all three** targets. Xcode will not warn you.
2. No RLS policy on `profiles` may subquery `profiles`. Use `current_group_id()`.
   Recursion presents as a hang, not an error.
3. The widget must never touch the network — not in the timeline provider, not in the
   entity query.
4. Never `reloadAllTimelines()`. Always `reloadTimelines(ofKind: Config.widgetKind)`.
5. Never assume a device token's APNs environment. It is a column; route by it. A sandbox
   token sent to the production host returns `400 BadDeviceToken` and the feature dies
   silently.
6. Every path in the NSE must call `contentHandler`. A missed call means the notification
   never arrives.
7. No widget state may render blank. All five have designed views.
8. Never regenerate the APNs provider token per send. Cache it 50 minutes.
9. The service role key must never enter the iOS project.

Three more that this build hit, and fixed:

10. **Postgres caps regex repetition counts at 255.** `'^[0-9a-f]{32,256}$'` raises
    `2201B` at *runtime*, not at migration time, so `register_device_token` applied
    cleanly and would have failed every single call. No device would ever have received a
    push. Fixed in `20260727033137`.
11. **`revoke all ... from public` also strips `service_role`.** Locking down `apply_mood`
    silently removed the Edge Function's own access. Fixed in `20260727032850`.
12. **A brand new profile's first mood tap was rate limited.** `mood_updated_at` defaults
    to `now()` and `apply_mood` rejects changes inside 3 seconds, so a fast onboard got a
    429 on its very first tap with nothing to retry against but a stopwatch.
    `bootstrap_profile` now backdates the column on insert. Fixed in `20260727033302`.

---

## Backend

Project `moodcats`, ref `zewojsliyfgmraoxgndc`, region `us-east-1`, free tier.

```bash
# Structural checks over the Xcode project and the source rules above
ruby Tools/verify_project.rb

# Regenerate the project after adding a source file
ruby Tools/generate_xcodeproj.rb

# Regenerate the asset catalogs and the app icon (drawn from the happy face)
python3 Tools/make_catalogs.py

# Typecheck the Edge Function
cd supabase/functions/set-mood && deno check index.ts
```

Advisors are clean apart from `authenticated_security_definer_function_executable`, which
fires once per client-callable RPC. That is the architecture the spec mandates — every
mutation goes through a `security definer` function precisely so `groups` can have no
insert/update/delete policy at all. Each one validates `auth.uid()` before doing anything.
The `anon`-reachable variant of that lint *was* real and is fixed.

Invocation budget: 8 users × 10 mood changes/day ≈ 2,400 Edge Function calls a month
against a 500,000 limit. It stays that way because one invocation fans out to every
recipient in a loop. Never invoke it once per recipient.

---

## Still open

From spec section 21 — these were built to the stated defaults, and each is cheap to
change now and expensive later:

1. **App name.** "MoodCats" is used throughout as a placeholder.
2. **Bundle prefix.** `com.huydao` assumed. One line in `Config/Signing.xcconfig`, plus
   the literals in `Shared/Config.swift`.
3. **Mood set.** The 8 from spec section 11. **Confirm before commissioning art** — mood
   ids are stable forever once shipped.
4. **Notification copy.** Currently title = the mover's name, body =
   `is feeling {mood} {emoji}`, matching the spec's own payload example.

And two things deliberately left for a human:

- **The cats are kaomoji, not art.** `(=^ω^=)`, `(=TωT=)`, and so on — the `(=` `=)`
  frame and the `ω` muzzle are constant, only the eyes change. Changing one is a one-line
  edit in `Shared/Mood.swift`; `Tools/verify_project.rb` then enforces that all nine stay
  distinct, keep the shared frame, and use only characters guaranteed to render.
  Deliberately avoided, despite being common in cat kaomoji: `ﻌ` (U+FECC) is an **Arabic**
  letter and would drag bidirectional text resolution into a Lock Screen widget, and `ฅ`
  / `ᴥ` depend on fonts that are not guaranteed and degrade to tofu boxes.
- **The app icon is a placeholder**, drawn from the happy face. 1024×1024, RGB, no alpha,
  so it will pass validation, but it is not a designed icon.
