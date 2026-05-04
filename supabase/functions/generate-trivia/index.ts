// supabase/functions/generate-trivia/index.ts
//
// Edge Function: generate-trivia
//
// Phase 2 of Trivia: premium AI-generated questions via Anthropic API.
// Trust boundary — browser never touches Anthropic API directly. This
// function holds the server-side ANTHROPIC_API_KEY, validates the
// caller's user JWT, enforces a per-user per-UTC-day rate limit, calls
// Anthropic, transforms the response to the OpenTDB-shaped output that
// the existing browser-side Trivia render layer consumes (one shape
// across both default-OpenTDB and premium-Anthropic paths).
//
// Phase 1 (v2.109) shipped the OpenTDB default path. Phase 2 ships this
// Edge Function (Commit A) plus a hidden manager-side opt-in toggle in
// games/player.html (Commit B). The browser falls back to OpenTDB if
// this function returns any error.
//
// This commit also doubles as the Sonnet model bump: the previous
// browser-direct triviaGenerate (preserved as a // PHASE 2 REFERENCE
// comment block in games/player.html) used `claude-sonnet-4-20250514`,
// which is deprecated and retiring 2026-06-15. This function uses
// `claude-sonnet-4-6` per https://platform.claude.com/docs/en/docs/about-claude/models/overview
// (no dated snapshot suffix exists for Sonnet 4.6 as of 2026-05-04;
// the alias and the API ID are identical).
//
// ── DEPLOY DOCTRINE ─────────────────────────────────────────────────────────
//
// MUST deploy WITHOUT the --no-verify-jwt flag. The Supabase gateway should
// verify the caller's JWT before this function runs. This is the OPPOSITE
// of send-push-notification's deploy pattern (which uses --no-verify-jwt to
// allow a non-JWT shared secret from the Postgres trigger).
//
//   ✅  supabase functions deploy generate-trivia --project-ref gbrnuxyzrlzbybvcvyzm
//   ❌  supabase functions deploy generate-trivia --no-verify-jwt    ← WRONG
//
// generate-trivia callers always have user JWTs (from the browser via
// supabase-js auto-attachment). There is no trigger / service-role caller
// path. Verifying at the gateway saves a round trip on bad-JWT requests.
//
// ── REQUEST / RESPONSE CONTRACTS ────────────────────────────────────────────
//
// Request:
//   POST /functions/v1/generate-trivia
//   Authorization: Bearer <user_jwt>
//   Content-Type: application/json
//   {
//     "categoryLabel": "Movies",   // matches GAME_INFO Trivia label vocabulary
//     "difficulty":    "Medium",    // 'Easy' | 'Medium' | 'Hard'
//     "amount":        10           // currently always 10 from the browser; clamped to [1, MAX_AMOUNT]
//   }
//
// Response (success, OpenTDB-shaped — same shape browser already consumes):
//   {
//     "questions": [
//       { "question": "...?", "options": ["plain1","plain2","plain3","plain4"], "correct": "B" },
//       ...
//     ]
//   }
//
// Response (error): { "error": "<message>" } with appropriate HTTP status.
// HTTP status codes:
//   400  invalid difficulty / bad input
//   401  missing or invalid Authorization header
//   429  daily limit reached (body includes used + limit)
//   500  ANTHROPIC_API_KEY not set (service misconfigured) OR uncaught exception
//   502  Anthropic returned non-2xx, OR malformed JSON, OR fewer than MIN_VALID
//        valid questions after filtering malformed ones
//
// ── AUTH MODEL ──────────────────────────────────────────────────────────────
//
// Caller is always a logged-in user (browser sending Bearer = user JWT).
// No service-role / trigger caller path exists. JWT extracted from the
// Authorization header, validated via supabase.auth.getUser() using the
// service-role client. user_id from the validated user is used as the
// rate-limit key.
//
// ── RATE LIMIT ──────────────────────────────────────────────────────────────
//
// Per-user per-UTC-day counter in public.trivia_premium_usage (db/019).
// DAILY_LIMIT = 20 generations per user per day. Counter increments AFTER
// a successful Anthropic call so failed upstream calls don't burn quota.
// RLS denies all client-side access to the table; service-role bypass
// gives this function read/write capability.

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── Constants ────────────────────────────────────────────────────────────────

const ANTHROPIC_MODEL = "claude-sonnet-4-6";   // alias == API ID (no dated snapshot)
const ANTHROPIC_VERSION = "2023-06-01";
const DAILY_LIMIT = 20;                         // per-user per UTC day
const MAX_AMOUNT = 20;                          // sanity cap on browser-requested count
const MIN_VALID = 5;                            // floor for filter-pattern: ship if >= this many valid

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ── Response helper ──────────────────────────────────────────────────────────

function jsonRes(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── Question shape validation ────────────────────────────────────────────────

interface RawQuestion {
  question?: unknown;
  options?: unknown;
  correct?: unknown;
}

interface ValidQuestion {
  question: string;
  options: [string, string, string, string];
  correct: "A" | "B" | "C" | "D";
}

function isValidQuestion(q: RawQuestion): q is ValidQuestion {
  return (
    typeof q.question === "string" &&
    q.question.length > 0 &&
    Array.isArray(q.options) &&
    q.options.length === 4 &&
    q.options.every((o) => typeof o === "string" && o.length > 0) &&
    typeof q.correct === "string" &&
    ["A", "B", "C", "D"].includes(q.correct)
  );
}

// ── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonRes(405, { error: "method not allowed" });
  }

  try {
    // ── 1. Auth ─────────────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return jsonRes(401, { error: "missing authorization" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const userJwt = authHeader.replace("Bearer ", "");
    const { data: userData, error: userError } = await supabase.auth.getUser(userJwt);
    if (userError || !userData?.user) {
      return jsonRes(401, { error: "invalid token" });
    }
    const userId = userData.user.id;

    // ── 2. Body validation ──────────────────────────────────────────
    const body = await req.json().catch(() => ({}));
    const categoryLabel = String(body?.categoryLabel || "General");
    const difficulty = String(body?.difficulty || "Medium");
    const amount = Math.min(MAX_AMOUNT, Math.max(1, Number(body?.amount) || 10));

    if (!["Easy", "Medium", "Hard"].includes(difficulty)) {
      return jsonRes(400, { error: "invalid difficulty" });
    }

    // ── 3. Rate limit check ─────────────────────────────────────────
    const today = new Date().toISOString().slice(0, 10);   // 'YYYY-MM-DD' UTC
    const { data: usage, error: usageError } = await supabase
      .from("trivia_premium_usage")
      .select("count")
      .eq("user_id", userId)
      .eq("day", today)
      .maybeSingle();

    if (usageError) {
      console.error("[generate-trivia] usage query failed:", usageError);
      return jsonRes(500, { error: "rate-limit lookup failed" });
    }

    const usedToday = usage?.count ?? 0;
    if (usedToday >= DAILY_LIMIT) {
      return jsonRes(429, {
        error: "daily limit reached",
        used: usedToday,
        limit: DAILY_LIMIT,
      });
    }

    // ── 4. Anthropic call ───────────────────────────────────────────
    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) {
      console.error("[generate-trivia] ANTHROPIC_API_KEY not set");
      return jsonRes(500, { error: "service misconfigured" });
    }

    // Prompt lifted from PHASE 2 REFERENCE comment block in games/player.html
    // with three changes vs the original:
    //   (a) explicit "no A) B) C) D) prefixes" — render layer adds letters
    //   (b) `correct` field is one of A|B|C|D matching position in options
    //   (c) drop the `id` and `fun_fact` fields from the requested shape
    //       (both were dead in the consumer code; OpenTDB transform also omits)
    const prompt =
      `Generate ${amount} trivia questions. Category: ${categoryLabel}. ` +
      `Difficulty: ${difficulty}. Return ONLY valid JSON in this exact shape:\n` +
      `{"questions":[{"question":"...?","options":["plain answer 1","plain answer 2","plain answer 3","plain answer 4"],"correct":"A"}]}\n` +
      `Notes: options must be 4 plain answer strings (NO "A) " / "B) " / "C) " / "D) " prefixes — letters are added by the renderer). ` +
      `correct must be one of A, B, C, D matching the position in the options array (A = options[0], B = options[1], etc.). ` +
      `Do not include any markdown, code fences, prose, or fields beyond question/options/correct.`;

    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": anthropicKey,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body: JSON.stringify({
        model: ANTHROPIC_MODEL,
        max_tokens: 3000,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    if (!anthropicRes.ok) {
      const errBody = await anthropicRes.text().catch(() => "");
      console.error(`[generate-trivia] Anthropic ${anthropicRes.status}:`, errBody.slice(0, 500));
      return jsonRes(502, { error: "upstream API error" });
    }

    const anthropicData = await anthropicRes.json();
    const rawText: string = anthropicData?.content?.[0]?.text || "";

    // ── 5. Response parse ──────────────────────────────────────────
    let parsed: { questions?: unknown };
    try {
      parsed = JSON.parse(rawText.replace(/```json|```/g, "").trim());
    } catch (e) {
      console.error("[generate-trivia] JSON parse failed. Raw:", rawText.slice(0, 500));
      return jsonRes(502, { error: "model returned invalid JSON" });
    }

    if (!Array.isArray(parsed?.questions) || parsed.questions.length === 0) {
      console.error("[generate-trivia] no questions in response");
      return jsonRes(502, { error: "no questions returned" });
    }

    // ── 6. Filter pattern: drop malformed, ship if >= MIN_VALID ─────
    const valid = (parsed.questions as RawQuestion[]).filter(isValidQuestion);
    const dropped = parsed.questions.length - valid.length;
    if (valid.length < MIN_VALID) {
      console.error(`[generate-trivia] only ${valid.length} valid questions after filter (raw=${parsed.questions.length}, dropped=${dropped})`);
      return jsonRes(502, { error: "too few valid questions returned" });
    }

    // ── 7. Rate limit increment (after success, before return) ──────
    if (usage) {
      const { error: updErr } = await supabase
        .from("trivia_premium_usage")
        .update({ count: usedToday + 1 })
        .eq("user_id", userId)
        .eq("day", today);
      if (updErr) console.error("[generate-trivia] usage update failed:", updErr);
    } else {
      const { error: insErr } = await supabase
        .from("trivia_premium_usage")
        .insert({ user_id: userId, day: today, count: 1 });
      if (insErr) console.error("[generate-trivia] usage insert failed:", insErr);
    }

    console.log(
      `[generate-trivia] user=${userId} cat=${categoryLabel} diff=${difficulty} ` +
      `count=${parsed.questions.length} valid=${valid.length} usedToday=${usedToday + 1}`
    );

    // ── 8. Return success ──────────────────────────────────────────
    return jsonRes(200, { questions: valid });

  } catch (err) {
    console.error("[generate-trivia] uncaught:", err);
    return jsonRes(500, { error: String(err) });
  }
});
