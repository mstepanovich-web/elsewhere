// supabase/functions/send-push-notification/index.ts
//
// Edge Function: send-push-notification
//
// Sends APNs push notifications to a user's registered devices for the
// karaoke session "you're up — take the stage" use case (Session 5 Part 2e.0).
//
// Request:
//   POST /functions/v1/send-push-notification
//   Authorization: Bearer <user_jwt>
//   Content-Type: application/json
//   {
//     "user_id": "<target user uuid>",
//     "title":   "<notification title>",
//     "body":    "<notification body>",
//     "data":    { ... optional metadata ... }
//   }
//
// Response:
//   { "sent": N, "failed": M, "details": [ ... per-token results ... ] }
//
// Auth model (2e.0):
//   - Caller must be authenticated (any logged-in user).
//   - TODO 2e.3: Verify caller is Session Manager of an active session
//     containing the target user, and that the push corresponds to a
//     legitimate state transition (e.g., promotion to active singer).
//
// Spec source: docs/SESSION-5-PART-2E-AUDIT.md (locked decisions appendix).

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── CORS ─────────────────────────────────────────────────────────────────────

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ── APNs JWT signing ─────────────────────────────────────────────────────────

let cachedPrivateKey: CryptoKey | null = null;

async function getPrivateKey(): Promise<CryptoKey> {
  if (cachedPrivateKey) return cachedPrivateKey;

  const pem = Deno.env.get("APNS_PRIVATE_KEY");
  if (!pem) throw new Error("APNS_PRIVATE_KEY env var not set");

  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));

  cachedPrivateKey = await crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  return cachedPrivateKey;
}

function base64UrlEncode(bytes: Uint8Array): string {
  let str = "";
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlEncodeJson(obj: unknown): string {
  return base64UrlEncode(new TextEncoder().encode(JSON.stringify(obj)));
}

async function signApnsJwt(): Promise<string> {
  const teamId = Deno.env.get("APNS_TEAM_ID")!;
  const keyId = Deno.env.get("APNS_KEY_ID")!;

  const header = { alg: "ES256", kid: keyId };
  const payload = {
    iss: teamId,
    iat: Math.floor(Date.now() / 1000),
  };

  const headerB64 = base64UrlEncodeJson(header);
  const payloadB64 = base64UrlEncodeJson(payload);
  const signingInput = `${headerB64}.${payloadB64}`;

  const key = await getPrivateKey();
  const sigBuf = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  const sigB64 = base64UrlEncode(new Uint8Array(sigBuf));

  return `${signingInput}.${sigB64}`;
}

// ── APNs send ────────────────────────────────────────────────────────────────

interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

interface PushResult {
  device_token: string;
  status: number;
  apns_id?: string;
  reason?: string;
}

async function sendApnsPush(
  deviceToken: string,
  payload: PushPayload,
  jwt: string,
): Promise<PushResult> {
  const host = Deno.env.get("APNS_HOST")!;
  const bundleId = Deno.env.get("APNS_BUNDLE_ID")!;

  const apsPayload = {
    aps: {
      alert: {
        title: payload.title,
        body: payload.body,
      },
      sound: "default",
    },
    ...(payload.data ?? {}),
  };

  const url = `https://${host}/3/device/${deviceToken}`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "content-type": "application/json",
    },
    body: JSON.stringify(apsPayload),
  });

  const result: PushResult = {
    device_token: deviceToken.slice(0, 8) + "...",
    status: res.status,
    apns_id: res.headers.get("apns-id") ?? undefined,
  };

  if (!res.ok) {
    try {
      const errBody = await res.json();
      result.reason = errBody.reason;
    } catch (_) {
      result.reason = "unknown";
    }
  }

  return result;
}

// ── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "method not allowed" }),
      {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "missing authorization" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const userJwt = authHeader.replace("Bearer ", "");
    const { data: userData, error: userError } = await supabase.auth.getUser(
      userJwt,
    );
    if (userError || !userData?.user) {
      return new Response(
        JSON.stringify({ error: "invalid token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const callerId = userData.user.id;
    console.log(`[send-push] caller=${callerId}`);

    const body = await req.json();
    const { user_id, title, body: pushBody, data } = body;
    if (!user_id || !title || !pushBody) {
      return new Response(
        JSON.stringify({
          error: "missing required fields: user_id, title, body",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { data: subs, error: subsError } = await supabase
      .from("push_subscriptions")
      .select("device_token, apns_environment")
      .eq("user_id", user_id);

    if (subsError) {
      console.error("[send-push] db error:", subsError);
      return new Response(
        JSON.stringify({ error: "database error" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!subs || subs.length === 0) {
      console.log(`[send-push] no tokens for user=${user_id}`);
      return new Response(
        JSON.stringify({ sent: 0, failed: 0, details: [] }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    console.log(`[send-push] target=${user_id} tokens=${subs.length}`);

    const jwt = await signApnsJwt();

    const results = await Promise.all(
      subs.map((s) =>
        sendApnsPush(s.device_token, { title, body: pushBody, data }, jwt)
      ),
    );

    const sent = results.filter((r) => r.status === 200).length;
    const failed = results.length - sent;

    console.log(`[send-push] sent=${sent} failed=${failed}`);

    return new Response(
      JSON.stringify({ sent, failed, details: results }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    console.error("[send-push] error:", err);
    return new Response(
      JSON.stringify({ error: String(err) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

// TODO 2e.0: failed-token cleanup. When APNs returns 410 BadDeviceToken,
// delete that row from push_subscriptions to prevent future failed sends.
// TODO 2e.3: Session-manager authorization. Before sending, verify caller is
// the Session Manager of an active session containing user_id, and that the
// push corresponds to a legitimate state transition.
