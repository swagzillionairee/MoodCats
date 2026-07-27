/**
 * APNs transport for MoodCats.
 *
 * The only metered code path in the system, and the only place a push is ever sent.
 * One invocation of set-mood fans out to every recipient from here -- never invoke the
 * function once per recipient.
 */
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

const SANDBOX_HOST = "https://api.sandbox.push.apple.com";
const PRODUCTION_HOST = "https://api.push.apple.com";

/**
 * APNs rejects provider tokens regenerated more often than once per 20 minutes, and
 * each token is valid for 1 hour. 50 minutes sits safely inside both bounds.
 *
 * Module scope, so the cache survives for the lifetime of the isolate. A cold start
 * re-signs once; that is fine and unavoidable.
 */
const TOKEN_TTL_MS = 50 * 60 * 1000;
let cachedToken: { jwt: string; expiresAt: number } | null = null;

export interface ApnsConfig {
  keyId: string;
  teamId: string;
  privateKey: string;
  bundleId: string;
}

export interface ApnsTarget {
  token: string;
  environment: "sandbox" | "production";
}

export type ApnsOutcome =
  | { token: string; status: "delivered" }
  | { token: string; status: "unregistered" }
  | { token: string; status: "failed"; httpStatus: number; reason: string };

export function readApnsConfig(): ApnsConfig | null {
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
  const bundleId = Deno.env.get("APNS_BUNDLE_ID");
  if (!keyId || !teamId || !privateKey || !bundleId) return null;
  // Secrets pasted through a dashboard field routinely arrive with literal "\n"
  // instead of real newlines, which importPKCS8 rejects with an opaque error.
  return { keyId, teamId, bundleId, privateKey: privateKey.replace(/\\n/g, "\n") };
}

async function providerToken(config: ApnsConfig): Promise<string> {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt > now) return cachedToken.jwt;

  const key = await importPKCS8(config.privateKey, "ES256");
  const jwt = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: config.keyId })
    .setIssuedAt()
    .setIssuer(config.teamId)
    .sign(key);

  cachedToken = { jwt, expiresAt: now + TOKEN_TTL_MS };
  return jwt;
}

/** Exposed for tests and for the "APNs key rotated" case. */
export function invalidateProviderToken(): void {
  cachedToken = null;
}

function hostFor(environment: string): string {
  // Never guess an environment. A sandbox token sent to the production host comes back
  // 400 BadDeviceToken and the feature dies silently, which is why the environment is
  // a column on device_tokens rather than a build-time constant.
  return environment === "production" ? PRODUCTION_HOST : SANDBOX_HOST;
}

/**
 * Sends one payload to every target concurrently. Deno's fetch speaks HTTP/2 natively,
 * which APNs requires; no special client is needed.
 */
export async function sendAll(
  config: ApnsConfig,
  targets: readonly ApnsTarget[],
  payload: unknown,
): Promise<ApnsOutcome[]> {
  if (targets.length === 0) return [];

  const jwt = await providerToken(config);
  const body = JSON.stringify(payload);
  const expiration = Math.floor(Date.now() / 1000) + 3600;

  // 4 KB is a hard APNs limit. At 8 members the roster lands around 400 bytes, so this
  // only trips if the member cap is raised far past its design point (~40).
  const size = new TextEncoder().encode(body).length;
  if (size > 4096) {
    throw new Error(`apns payload ${size} bytes exceeds the 4096 byte limit`);
  }

  const results = await Promise.allSettled(
    targets.map(async (target): Promise<ApnsOutcome> => {
      const response = await fetch(`${hostFor(target.environment)}/3/device/${target.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": config.bundleId, // the MAIN app bundle id, not the widget's
          "apns-push-type": "alert",
          "apns-priority": "10",
          "apns-expiration": String(expiration),
          "content-type": "application/json",
        },
        body,
      });

      if (response.ok) {
        await response.body?.cancel();
        return { token: target.token, status: "delivered" };
      }

      const text = await response.text();
      let reason = text;
      try {
        reason = JSON.parse(text).reason ?? text;
      } catch {
        // APNs returns an empty body on some statuses; keep the raw text.
      }

      if (response.status === 410 || reason === "Unregistered") {
        return { token: target.token, status: "unregistered" };
      }
      return { token: target.token, status: "failed", httpStatus: response.status, reason };
    }),
  );

  return results.map((result, index): ApnsOutcome => {
    if (result.status === "fulfilled") return result.value;
    return {
      token: targets[index].token,
      status: "failed",
      httpStatus: 0,
      reason: String(result.reason),
    };
  });
}
