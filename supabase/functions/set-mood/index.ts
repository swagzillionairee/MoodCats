/**
 * POST /functions/v1/set-mood
 *   Authorization: Bearer <supabase user JWT>
 *   { "mood_id": 4 }
 *
 * Writes the caller's mood, fans out one push to every OTHER member of their group,
 * and returns the full roster blob to the caller.
 *
 * ONE invocation fans out to ALL recipients in a loop. Never invoke this function once
 * per recipient -- that is what keeps ~2,400 invocations/month against a 500,000 limit.
 *
 * The caller is deliberately not pushed to. They get the roster back synchronously in
 * the response body and write it to the App Group themselves, which is instant and
 * costs nothing.
 */
import { type ApnsTarget, readApnsConfig, sendAll } from "./apns.ts";
import { MOOD_COUNT, notificationBody } from "./moods.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/** Must match PAYLOAD_VERSION in Shared/RosterContract.swift. */
const PAYLOAD_VERSION = 1;
const RATE_LIMIT_MS = 3000;

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

interface RosterMember {
  id: string;
  n: string;
  m: number;
  at: number;
}

interface Roster {
  v: number;
  t: number;
  groupId: string | null;
  me: string;
  members: RosterMember[];
}

interface ApplyMoodResult {
  ok: boolean;
  reason?: string;
  retry_after_ms?: number;
  roster?: Roster;
  tokens?: { t: string; e: "sandbox" | "production" }[];
}

function json(body: unknown, status: number, extraHeaders: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...CORS_HEADERS, ...extraHeaders },
  });
}

/**
 * The function is deployed with verify_jwt enabled, so the Edge Runtime has already
 * rejected anything whose signature does not check out against the project secret
 * before this code runs. What is left to do here is read `sub` out of the verified
 * token and refuse an expired or malformed one.
 */
function callerId(authHeader: string | null): string | null {
  if (!authHeader?.toLowerCase().startsWith("bearer ")) return null;
  const parts = authHeader.slice(7).trim().split(".");
  if (parts.length !== 3) return null;
  try {
    const padded = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(atob(padded + "=".repeat((4 - (padded.length % 4)) % 4)));
    if (typeof claims.sub !== "string" || claims.sub.length === 0) return null;
    if (typeof claims.exp === "number" && claims.exp * 1000 <= Date.now()) return null;
    return claims.sub;
  } catch {
    return null;
  }
}

async function postgrest(path: string, init: RequestInit): Promise<Response> {
  return await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_ROLE_KEY,
      authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "content-type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // 1. Identify the caller.
  const userId = callerId(req.headers.get("authorization"));
  if (!userId) return json({ error: "unauthorized" }, 401);

  // 2. Validate the mood id.
  let moodId: unknown;
  try {
    moodId = (await req.json())?.mood_id;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (typeof moodId !== "number" || !Number.isInteger(moodId) || moodId < 0 || moodId >= MOOD_COUNT) {
    return json({ error: "invalid_mood_id", expected: `integer 0..${MOOD_COUNT - 1}` }, 400);
  }

  // 3-6. Rate limit, mood write, roster read and recipient token read, in a single
  // database round trip. apply_mood is service_role only and compares against
  // mood_updated_at, so the rate limit needs no extra table.
  const rpc = await postgrest("rpc/apply_mood", {
    method: "POST",
    body: JSON.stringify({
      p_user_id: userId,
      p_mood_id: moodId,
      p_min_interval_ms: RATE_LIMIT_MS,
    }),
  });

  if (!rpc.ok) {
    console.error("apply_mood failed", rpc.status, await rpc.text());
    return json({ error: "database_error" }, 502);
  }

  const result = (await rpc.json()) as ApplyMoodResult;

  if (!result.ok) {
    if (result.reason === "rate_limited") {
      const retryMs = result.retry_after_ms ?? RATE_LIMIT_MS;
      return json({ error: "rate_limited", retry_after_ms: retryMs }, 429, {
        "retry-after": String(Math.ceil(retryMs / 1000)),
      });
    }
    if (result.reason === "profile_missing") return json({ error: "profile_missing" }, 404);
    return json({ error: result.reason ?? "unknown_error" }, 400);
  }

  const roster = result.roster!;
  const targets: ApnsTarget[] = (result.tokens ?? []).map((row) => ({
    token: row.t,
    environment: row.e,
  }));

  // 7-10. Fan out. Push is best effort: the mood is already committed and the caller's
  // own widgets update from the response body, so a push failure must never fail the
  // request. Anyone who misses a push is repaired by the next one or by the foreground
  // get_roster call, because every payload carries the FULL roster.
  const stats = { attempted: targets.length, delivered: 0, unregistered: 0, failed: 0 };
  let pushNote = "";

  const apns = readApnsConfig();
  if (!apns) {
    pushNote = "apns_not_configured";
    if (targets.length > 0) {
      console.warn("APNS_* secrets are unset; skipping fanout to", targets.length, "device(s)");
    }
  } else if (targets.length > 0) {
    const mover = roster.members.find((m) => m.id === userId);
    const payload = {
      aps: {
        alert: {
          title: mover?.n ?? "MoodCats",
          body: notificationBody(moodId),
        },
        "mutable-content": 1,
        // Delivers quietly to Notification Center without lighting the screen or
        // buzzing. The Notification Service Extension still fires, which is the whole
        // point -- this is what stops notification fatigue from killing the update path.
        "interruption-level": "passive",
        "thread-id": "moodcats",
      },
      v: PAYLOAD_VERSION,
      t: roster.t,
      groupId: roster.groupId,
      // NOTE: `me` is deliberately absent. It identifies the RECEIVING user, so each
      // device fills in its own when it merges this payload into App Group storage.
      // Shipping the sender's id here would overwrite every recipient's identity.
      members: roster.members,
    };

    try {
      const outcomes = await sendAll(apns, targets, payload);
      const dead: string[] = [];
      for (const outcome of outcomes) {
        if (outcome.status === "delivered") stats.delivered++;
        else if (outcome.status === "unregistered") {
          stats.unregistered++;
          dead.push(outcome.token);
        } else {
          stats.failed++;
          console.error("apns send failed", outcome.httpStatus, outcome.reason);
          if (outcome.reason === "BadDeviceToken") {
            // Almost always an environment mismatch. The row is left alone on purpose:
            // the client re-registers with the right environment on its next launch.
            console.error("BadDeviceToken -- check the device_tokens.environment column");
          }
        }
      }

      if (dead.length > 0) {
        const list = dead.map((t) => `"${t}"`).join(",");
        const del = await postgrest(`device_tokens?token=in.(${list})`, { method: "DELETE" });
        if (!del.ok) console.error("failed to prune unregistered tokens", await del.text());
      }
    } catch (error) {
      pushNote = "apns_error";
      stats.failed = targets.length;
      console.error("apns fanout threw", error);
    }
  }

  // 11. The caller gets the roster blob back verbatim, in exactly the shape that goes
  // into App Group storage (section 9). Push diagnostics ride in headers so the body
  // stays a clean, directly-writable roster. `tokens` is stripped -- device tokens must
  // never reach a client.
  return json(roster, 200, {
    "x-moodcats-push-attempted": String(stats.attempted),
    "x-moodcats-push-delivered": String(stats.delivered),
    "x-moodcats-push-unregistered": String(stats.unregistered),
    "x-moodcats-push-failed": String(stats.failed),
    ...(pushNote ? { "x-moodcats-push-note": pushNote } : {}),
  });
});
