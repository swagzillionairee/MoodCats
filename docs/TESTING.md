# Test matrix

Spec section 18, ordered by how likely each is to break. **Number 1 is the case that
actually matters** — everything else is a variation on it.

Nothing in this table has been run. All of it needs two physical devices on iOS 18+.

| # | Scenario | Expected | Result |
|---|---|---|---|
| 1 | **App force quit, device locked** | Widget updates within 5s | |
| 2 | App force quit, device unlocked | Widget updates within 5s | |
| 3 | Low Power Mode enabled | Updates, possibly delayed | |
| 4 | Notifications denied | App still works; widget updates only on app foreground | |
| 5 | Airplane mode, then reconnect | Queued push lands and applies | |
| 6 | App in foreground | Widget updates, no duplicate render | |
| 7 | Two pushes arrive out of order | Older `t` is ignored | |
| 8 | Pinned friend kicked or leaves | Widget shows the "left the group" state | |
| 9 | New member joins | Appears in the widget picker after the next mood change, no app launch | |
| 10 | Group deleted by owner | All members drop to no group cleanly | |
| 11 | Fresh install, widget added before joining a group | "Open MoodCats" state, no crash | |
| 12 | All three widget families on the Lock Screen | Legible in vibrant mode | |
| 13 | Delete My Data | Row gone, tokens gone, App Group cleared, signed out | |

## Tooling

Widget extension logs do not reliably reach the Xcode console. Use **Console.app**
filtered by bundle id:

- `com.huydao.moodcats` — the app
- `com.huydao.moodcats.widget` — the widget
- `com.huydao.moodcats.notificationservice` — the NSE

For NSE breakpoints: Xcode → Debug → **Attach to Process by PID**. Breakpoints do not hit
by default.

Every subsystem in this project logs under its own bundle id with `os_log`, so
`RosterStore`'s App Group fault, the NSE's apply/reject decisions and the app's Supabase
errors are all visible without a debugger attached.

## How to drive each row

**7 — out of order pushes.** The clean way is `Scripts/push_spike.sh` with a forced
timestamp, which bypasses the server entirely:

```bash
./Scripts/push_spike.sh <token> 6 Kim                         # excited, now
MOODCATS_T=1600000000000 ./Scripts/push_spike.sh <token> 1 Kim  # sad, ancient
```

The widget must still show excited. `RosterStore.apply` logs
`Ignoring stale roster t=…` when it rejects.

**8 — friend gone.** Device A pins a widget to B. B leaves the group (or A's owner kicks
B). Then **A changes their own mood** — that push is what carries the new roster. The
widget should read "{name} left the group", using the name remembered in the App Group
rather than the roster, because B is no longer in it.

**9 — new member.** With the app on device A force quit, have C join the group, then have
B change mood. That push carries the full roster including C. Long press A's widget → Edit
Widget → C should be in the picker, with A never having been launched. This is the payoff
for shipping the whole roster in every push.

**11 — widget before group.** Fresh install, add the widget, never onboard. Must render
"Open MoodCats", not blank and not a crash. The `EntityQuery` returns an empty list here,
which is the case most likely to have been left unhandled.

**12 — vibrant mode.** Add the circular and rectangular widgets to the Lock Screen, then
look at them on a *photo* wallpaper, not a solid colour — vibrant mode only fully kicks in
against a busy background.

**13 — Delete My Data.** After it completes, check all four:
- `select * from profiles where id = '…'` → empty
- `select * from device_tokens where user_id = '…'` → empty
- the widget shows "Open MoodCats"
- the app returns to name entry

## Backend regression

The backend has been verified against the live project and does not need a device:

- 44 SQL-level assertions covering every RPC, RLS scoping, the group cap, owner-only
  actions, cascade behaviour, and the rate limiter.
- 14 HTTP-level assertions covering the full `set-mood` path, PostgREST grants, and the
  column-level guard that blocks a direct `mood_id` PATCH.

Both were run ad hoc during the build rather than committed as a suite. If the schema
changes, re-run the important ones — especially:

```sql
-- The one that has bitten twice: RLS on profiles must not recurse.
-- If this hangs rather than erroring, current_group_id() has been broken.
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"<a real uuid>","role":"authenticated"}', false);
select count(*) from public.profiles;
reset role;
```
