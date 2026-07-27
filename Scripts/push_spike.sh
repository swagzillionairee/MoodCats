#!/usr/bin/env bash
#
# Phase 0 push spike. Fires one MoodCats-shaped alert push straight at APNs, with no
# Supabase, no auth and no app involvement.
#
# This is the tool that answers the only question that matters before anything else is
# built: with the app force quit and the phone locked, does the Notification Service
# Extension fire, write the roster, and repaint the right cat on the right pinned widget
# within 5 seconds?
#
# It sends the exact payload the Edge Function sends, so a pass here means the whole
# update path is sound.
#
#   ./Scripts/push_spike.sh <device-token> [mood-id] [name]
#
# Configure once, either as environment variables or in a .env file beside this script:
#
#   APNS_P8_PATH=/secure/path/AuthKey_ABC1234567.p8   # NEVER inside this repo
#   APNS_KEY_ID=ABC1234567
#   APNS_TEAM_ID=DEF7654321
#   APNS_BUNDLE_ID=com.huydao.moodcats                # the MAIN app id, not the widget's
#   APNS_ENV=sandbox                                  # sandbox | production
#
# Get the device token from the Xcode console: AppDelegate logs it on every launch.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$HERE/.env" ]] && set -a && source "$HERE/.env" && set +a

DEVICE_TOKEN="${1:-}"
MOOD_ID="${2:-2}"
FRIEND_NAME="${3:-Kim}"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -n "$DEVICE_TOKEN" ]] || die "usage: $0 <device-token> [mood-id 0-7] [name]"
[[ "$DEVICE_TOKEN" =~ ^[0-9a-fA-F]{32,}$ ]] || die "device token must be hex (copy it from the Xcode console, not the debugger's <> form)"
[[ "$MOOD_ID" =~ ^[0-7]$ ]] || die "mood id must be 0-7"

for required in APNS_P8_PATH APNS_KEY_ID APNS_TEAM_ID APNS_BUNDLE_ID; do
  [[ -n "${!required:-}" ]] || die "$required is not set (see the header of this script)"
done
[[ -f "$APNS_P8_PATH" ]] || die "no .p8 at $APNS_P8_PATH"

APNS_ENV="${APNS_ENV:-sandbox}"
case "$APNS_ENV" in
  sandbox) HOST="https://api.sandbox.push.apple.com" ;;
  production) HOST="https://api.push.apple.com" ;;
  *) die "APNS_ENV must be sandbox or production, got '$APNS_ENV'" ;;
esac

# ---------------------------------------------------------------------------------------
# Provider token, cached for 50 minutes.
#
# APNs rejects tokens regenerated more often than once per 20 minutes and expires each one
# after an hour. 50 minutes sits safely inside both bounds -- the same window the Edge
# Function uses.
# ---------------------------------------------------------------------------------------
JWT_CACHE="${TMPDIR:-/tmp}/moodcats_apns_jwt_${APNS_KEY_ID}"
if [[ -f "$JWT_CACHE" ]] && [[ $(( $(date +%s) - $(stat -f %m "$JWT_CACHE" 2>/dev/null || stat -c %Y "$JWT_CACHE") )) -lt 3000 ]]; then
  JWT="$(cat "$JWT_CACHE")"
  printf 'provider token: cached\n'
else
  JWT="$(node "$HERE/apns_jwt.js" "$APNS_P8_PATH" "$APNS_KEY_ID" "$APNS_TEAM_ID")"
  printf '%s' "$JWT" > "$JWT_CACHE"
  chmod 600 "$JWT_CACHE"
  printf 'provider token: freshly signed\n'
fi

# ---------------------------------------------------------------------------------------
# Payload -- byte for byte the shape supabase/functions/set-mood/index.ts produces.
#
# Note what is NOT here: `me`. It identifies the RECEIVING user, so each device fills in
# its own. A push is broadcast to a whole group; shipping one user's id would overwrite
# every recipient's identity.
#
# `t` is unix MILLISECONDS and is the sequence number behind "only write if incoming t >
# stored t". Send an older `t` to verify test matrix row 7 (out of order pushes).
# ---------------------------------------------------------------------------------------
NOW_MS="${MOODCATS_T:-$(( $(date +%s) * 1000 ))}"
MOOD_KEYS=(happy sad sleepy angry anxious chill excited hungry)
MOOD_EMOJI=("😊" "😢" "😴" "😠" "😰" "😎" "🤩" "🍜")

PAYLOAD=$(cat <<JSON
{
  "aps": {
    "alert": { "title": "$FRIEND_NAME", "body": "is feeling ${MOOD_KEYS[$MOOD_ID]} ${MOOD_EMOJI[$MOOD_ID]}" },
    "mutable-content": 1,
    "interruption-level": "passive",
    "thread-id": "moodcats"
  },
  "v": 1,
  "t": $NOW_MS,
  "groupId": "00000000-0000-0000-0000-0000000000aa",
  "members": [
    { "id": "00000000-0000-0000-0000-0000000000b1", "n": "$FRIEND_NAME", "m": $MOOD_ID, "at": $NOW_MS },
    { "id": "00000000-0000-0000-0000-0000000000b2", "n": "Sam", "m": 5, "at": $(( NOW_MS - 600000 )) }
  ]
}
JSON
)

BYTES=$(printf '%s' "$PAYLOAD" | wc -c | tr -d ' ')
printf 'payload:        %s bytes (APNs hard limit is 4096)\n' "$BYTES"
[[ "$BYTES" -le 4096 ]] || die "payload exceeds the 4 KB APNs limit"

printf 'host:           %s (%s)\n' "$HOST" "$APNS_ENV"
printf 'topic:          %s\n' "$APNS_BUNDLE_ID"
printf 'sending "%s is feeling %s"...\n\n' "$FRIEND_NAME" "${MOOD_KEYS[$MOOD_ID]}"

RESPONSE=$(curl --http2 -sS -D - -o /dev/stdout -w '\nHTTP %{http_code}\n' \
  --request POST \
  --header "authorization: bearer $JWT" \
  --header "apns-topic: $APNS_BUNDLE_ID" \
  --header "apns-push-type: alert" \
  --header "apns-priority: 10" \
  --header "apns-expiration: $(( $(date +%s) + 3600 ))" \
  --header "content-type: application/json" \
  --data "$PAYLOAD" \
  "$HOST/3/device/$DEVICE_TOKEN" 2>&1) || die "curl failed: $RESPONSE"

printf '%s\n' "$RESPONSE"

if grep -q 'HTTP 200' <<<"$RESPONSE"; then
  printf '\n\033[32mAccepted by APNs.\033[0m Watch the widget -- it should repaint within 5 seconds.\n'
  printf 'If nothing happens, the push was delivered but the NSE did not run or could not\n'
  printf 'write. Open Console.app, filter by "%s.notificationservice", and look for the\n' "$APNS_BUNDLE_ID"
  printf 'App Group fault line from RosterStore.\n'
else
  printf '\n\033[31mAPNs rejected it.\033[0m Common reasons:\n'
  printf '  BadDeviceToken     the token is from the other environment. Flip APNS_ENV.\n'
  printf '  TopicDisallowed    apns-topic must be the MAIN app bundle id, not the widget.\n'
  printf '  ExpiredProviderToken  delete %s and rerun.\n' "$JWT_CACHE"
  printf '  Unregistered       the app was deleted from that device.\n'
  exit 1
fi
