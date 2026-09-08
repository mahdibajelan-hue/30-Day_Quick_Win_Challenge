// Supabase Edge Function: suggest-root-cause
//
// «تحلیل و آنالیز مشکلات پروژه» — AI Root Cause Analysis method. Given the
// project's main bottleneck (plus its impact/status/criticality, and the
// caller's own visible history), returns several ranked root-cause
// CANDIDATES — never a single verdict — for the respondent to confirm, edit
// or discard. Same analysis engine (providers, retry logic) analyze-project
// already uses, extended for this narrower, per-bottleneck use.
//
// Deliberately NOT admin-only, unlike analyze-project: this only ever reads
// through the CALLER'S OWN JWT (never service-role), so Postgres RLS scopes
// the "similar past cases" corpus to exactly what that user could already
// see in the app themselves (their own project/org's proposals, plus any
// already-decided, project-wide ones) — a regular manager gets a genuinely
// useful "have we seen this before" signal without this function ever
// becoming a way to peek at another organization's still-private proposals.
//
// Deploy: paste into the "suggest-root-cause" Edge Function in the Supabase
// dashboard (or `supabase functions deploy suggest-root-cause`). Reuses the
// same GEMINI_API_KEY / OPENAI_API_KEY secrets as analyze-project — no new
// secret to configure if that function is already set up.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json" },
  });
}

// Same reasoning as analyze-project's fetchWithRetry: only 503 (transient
// overload) is worth retrying — anything else retrying won't fix.
async function fetchWithRetry(url: string, options: RequestInit, maxRetries = 2): Promise<Response> {
  let res: Response;
  for (let attempt = 0; ; attempt++) {
    res = await fetch(url, options);
    if (res.ok || res.status !== 503 || attempt >= maxRetries) return res;
    await new Promise((r) => setTimeout(r, 800 * 2 ** attempt));
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Unauthorized" }, 401);

    // The caller's own JWT — never service-role. RLS on check_ins/cases
    // below does the privacy scoping for us; this function adds no
    // additional access beyond what the caller's own client already has.
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return jsonResponse({ error: "Unauthorized" }, 401);

    const { problem_text, impact, status, criticality, provider } = await req.json();
    if (!problem_text || typeof problem_text !== "string" || !problem_text.trim()) {
      return jsonResponse({ error: "problem_text الزامی است." }, 400);
    }
    const chosenProvider = provider === "openai" ? "openai" : "gemini";

    // A small, recent corpus — RLS-scoped to whatever this caller can
    // already see — kept short so the prompt (and the cost of the call)
    // stays small; this is a quick suggestion, not a deep analysis.
    const { data: pastCheckins } = await supabase
      .from("check_ins")
      .select("project_name, main_bottleneck, bottleneck_root_cause")
      .not("main_bottleneck", "is", null)
      .order("created_at", { ascending: false })
      .limit(20);

    const { data: pastCases } = await supabase
      .from("cases")
      .select("project_name, title, action_details, actual_result, status")
      .order("proposed_at", { ascending: false })
      .limit(20);

    const corpusLines: string[] = [];
    // deno-lint-ignore no-explicit-any
    (pastCheckins || []).forEach((c: any) => {
      if (!c.bottleneck_root_cause) return;
      corpusLines.push(`[گلوگاه] پروژه ${c.project_name}: «${c.main_bottleneck}» — علت ثبت‌شده: ${c.bottleneck_root_cause}`);
    });
    // deno-lint-ignore no-explicit-any
    (pastCases || []).forEach((c: any) => {
      corpusLines.push(`[Case] پروژه ${c.project_name}: «${c.title}» — اقدام: ${c.action_details || "-"}${c.actual_result ? ` — نتیجه واقعی: ${c.actual_result}` : ""}`);
    });

    if (corpusLines.length === 0) {
      // Nothing to compare against yet (e.g. a brand-new project/user) —
      // still worth plain root-cause candidates from the text alone.
      corpusLines.push("(هنوز سابقه‌ای برای مقایسه در دسترس این کاربر نیست.)");
    }

    const contextLines: string[] = [];
    if (impact) contextLines.push(`Impact: ${impact}`);
    if (status) contextLines.push(`وضعیت فعلی: ${status}`);
    if (criticality) contextLines.push(`میزان اهمیت/Criticality: ${criticality}`);

    const prompt = `شما یک متخصص ریشه‌یابی مسائل (Root Cause Analysis) در پروژه‌های خط انتقال گاز هستید. یک کاربر مسئله زیر را به‌عنوان مهم‌ترین گلوگاه فعلی پروژه ثبت کرده:
«${problem_text}»
${contextLines.length ? contextLines.join(" — ") : ""}

سابقه مسائل و Caseهای قبلی که این کاربر به آن‌ها دسترسی دارد:
${corpusLines.join("\n")}

بر اساس این اطلاعات، ۲ تا ۴ علت ریشه‌ای «محتمل» (نه قطعی) تولید کن و بر اساس Confidence از زیاد به کم مرتب کن. خروجی را دقیقاً و فقط به‌صورت یک شیء JSON معتبر برگردان، بدون Markdown و بدون متن اضافه، دقیقاً با این ساختار:
{
  "candidates": [
    {
      "cause": "عنوان کوتاه علت ریشه‌ای پیشنهادی",
      "explanation": "توضیح یکی‌دو جمله‌ای چرا این علت محتمل است",
      "evidence": "شواهدی از متن مسئله یا سابقه بالا که از این علت پشتیبانی می‌کند",
      "probability": "کم" یا "متوسط" یا "زیاد",
      "impact": "کم" یا "متوسط" یا "زیاد",
      "confidence": عددی بین ۰ تا ۱۰۰ (میزان اطمینان مدل به این علت),
      "suggested_action": "یک پیشنهاد کوتاه برای اقدام اصلاحی مرتبط با همین علت"
    }
  ],
  "similar_cases": [
    { "project_name": "نام پروژه از سابقه بالا", "reference": "عنوان Case یا شرح گلوگاه مشابه از سابقه بالا", "why_similar": "چرا این مورد شبیه مسئله فعلی است" }
  ]
}
اگر هیچ مورد مشابهی در سابقه بالا نبود، آرایه similar_cases را خالی [] بگذار — هرگز مورد نامرتبط اختراع نکن. هرگز از عبارت «علت قطعی» استفاده نکن — این‌ها همگی «علل ریشه‌ای پیشنهادی» هستند که کاربر باید تأیید یا اصلاح کند.`;

    // deno-lint-ignore no-explicit-any
    let resultJson: any;

    if (chosenProvider === "openai") {
      const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
      if (!OPENAI_API_KEY) {
        return jsonResponse({ error: "کلید OpenAI هنوز در تنظیمات Supabase (Secrets) ثبت نشده است." }, 500);
      }
      const aiRes = await fetchWithRetry("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: { "content-type": "application/json", "Authorization": `Bearer ${OPENAI_API_KEY}` },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          max_tokens: 1200,
          response_format: { type: "json_object" },
          messages: [{ role: "user", content: prompt }],
        }),
      });
      if (!aiRes.ok) {
        if (aiRes.status === 503) return jsonResponse({ error: "سرویس ChatGPT در حال حاضر پرترافیک است — لطفاً دوباره تلاش کنید." }, 503);
        return jsonResponse({ error: "خطا در فراخوانی ChatGPT: " + await aiRes.text() }, 502);
      }
      const aiData = await aiRes.json();
      const content = aiData.choices?.[0]?.message?.content;
      if (typeof content !== "string" || !content.trim()) return jsonResponse({ error: "پاسخی از ChatGPT دریافت نشد." }, 502);
      try {
        resultJson = JSON.parse(content);
      } catch (_e) {
        return jsonResponse({ error: "پاسخ ChatGPT به‌صورت JSON معتبر نبود." }, 502);
      }
    } else {
      const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
      if (!GEMINI_API_KEY) {
        return jsonResponse({ error: "کلید Gemini هنوز در تنظیمات Supabase (Secrets) ثبت نشده است." }, 500);
      }
      const aiRes = await fetchWithRetry(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=${GEMINI_API_KEY}`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: { responseMimeType: "application/json" },
          }),
        },
      );
      if (!aiRes.ok) {
        if (aiRes.status === 503) return jsonResponse({ error: "سرویس Gemini در حال حاضر پرترافیک است — لطفاً دوباره تلاش کنید." }, 503);
        return jsonResponse({ error: "خطا در فراخوانی Gemini: " + await aiRes.text() }, 502);
      }
      const aiData = await aiRes.json();
      const parts = aiData.candidates?.[0]?.content?.parts;
      // deno-lint-ignore no-explicit-any
      const joinedText = Array.isArray(parts) ? parts.map((p: any) => (typeof p?.text === "string" ? p.text : "")).join("") : "";
      if (!joinedText.trim()) return jsonResponse({ error: "پاسخی از Gemini دریافت نشد یا توسط فیلتر محتوا مسدود شد." }, 502);
      try {
        resultJson = JSON.parse(joinedText);
      } catch (_e) {
        return jsonResponse({ error: "پاسخ Gemini به‌صورت JSON معتبر نبود." }, 502);
      }
    }

    // deno-lint-ignore no-explicit-any
    const candidates = Array.isArray(resultJson?.candidates) ? resultJson.candidates : [];
    // deno-lint-ignore no-explicit-any
    const similarCases = Array.isArray(resultJson?.similar_cases) ? resultJson.similar_cases : [];

    return jsonResponse({ suggestion: { candidates, similar_cases: similarCases }, provider: chosenProvider });
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500);
  }
});
