// Supabase Edge Function: analyze-project
//
// Called from the app's admin-only "🤖 تحلیل هوشمند" button. Fetches every
// organization's latest check-in for a project, asks Claude for a short
// analytical report, and returns it. The Anthropic API key stays server-side
// (in this function's secrets) and is never exposed to the browser.
//
// Deploy: paste this file's content into a new Edge Function named
// "analyze-project" in the Supabase dashboard (or `supabase functions deploy
// analyze-project` if using the CLI), then set the ANTHROPIC_API_KEY secret.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Unauthorized" }, 401);

    // Client scoped to the caller's own JWT: identifies who is asking and
    // lets Postgres RLS decide what they're allowed to read.
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return jsonResponse({ error: "Unauthorized" }, 401);

    const { data: profile } = await supabase
      .from("app_users")
      .select("role")
      .eq("user_id", user.id)
      .maybeSingle();

    if (!profile || profile.role !== "admin") {
      return jsonResponse({ error: "این تحلیل فقط برای ادمین سامانه در دسترس است." }, 403);
    }

    const { project_name } = await req.json();
    if (!project_name) return jsonResponse({ error: "project_name الزامی است." }, 400);

    const { data: checkins } = await supabase
      .from("check_ins")
      .select("*")
      .eq("project_name", project_name)
      .order("created_at", { ascending: true });

    if (!checkins || checkins.length === 0) {
      return jsonResponse({ error: "برای این پروژه هنوز گزارشی ثبت نشده است." }, 404);
    }

    const { data: decision } = await supabase
      .from("quick_win_decisions")
      .select("*")
      .eq("project_name", project_name)
      .maybeSingle();

    const { data: progress } = await supabase
      .from("quick_win_progress")
      .select("*")
      .eq("project_name", project_name)
      .order("created_at", { ascending: true });

    // Keep only the latest check-in per organization (the current perspective).
    // deno-lint-ignore no-explicit-any
    const latestByOrg: Record<string, any> = {};
    for (const c of checkins) latestByOrg[c.organization] = c;

    const perspectiveText = Object.entries(latestByOrg)
      .map(([org, c]: [string, any]) => `
### دیدگاه ${org}
- پاسخ‌دهنده: ${c.respondent || "-"}
- وضعیت‌ها: ROW=${c.status_row}, تدارکات=${c.status_procurement}, اجرا=${c.status_construction}, مالی=${c.status_finance}
- پیشرفت برنامه‌ای: ${c.planned_progress ?? "-"}% | پیشرفت فیزیکی واقعی: ${c.physical_progress}% | پیشرفت مالی: ${c.financial_progress}%
- تاریخ پیش‌بینی فعلی تکمیل: ${c.forecast_completion_date}
- نیروی انسانی مستقر: ${c.manpower_count ?? "-"} | نرخ ردی جوش: ${c.weld_reject_rate ?? "-"}%
- رویداد HSE: ${c.hse_incident ? "بله - " + c.hse_incident_note : "خیر"}
- گلوگاه فعلی: ${c.main_bottleneck}
- ریسک پیش‌رو (شدت ${c.risk_severity ?? "-"}/۵): ${c.top_risk}
- پیشنهاد Quick Win: ${c.quick_win_title} — اقدام: ${c.action_details} — نتیجه ۳۰ روزه: ${c.tangible_result} — حمایت لازم: ${c.support_needed}`)
      .join("\n");

    const decisionText = decision
      ? `\nQuick Win برگزیده فعلی: ${decision.selected_title} (${decision.selected_organization}) — دلیل: ${decision.rationale || "-"} — مهلت: ${decision.target_date}`
      : "\nهنوز Quick Win‌ی برای این پروژه انتخاب نشده است.";

    const progressText = progress && progress.length > 0
      // deno-lint-ignore no-explicit-any
      ? "\nتاریخچه پایش:\n" + progress.map((p: any) => `- ${String(p.created_at).slice(0, 10)}: ${p.status}, ${p.progress_percent}% — ${p.note || ""}`).join("\n")
      : "";

    const prompt = `شما یک متخصص مدیریت پورتفولیوی پروژه‌های خط انتقال گاز هستید. اطلاعات زیر گزارش‌های دوره‌ای پروژه «${project_name}» است که توسط کارفرما، مشاور و پیمانکار به‌طور مستقل ثبت شده است:
${perspectiveText}
${decisionText}
${progressText}

یک گزارش تحلیلی مختصر و کاربردی به فارسی، دقیقاً با این ساختار تولید کن:
۱. **تناقض‌های کلیدی بین دیدگاه‌ها** — اگر عددی یا توصیفی بین ۳ طرف مغایرت دارد، دقیقاً نام ببر.
۲. **مهم‌ترین ریسک/گلوگاه پروژه در حال حاضر** — با توجیه کوتاه.
۳. **پیشنهاد اقدام اولویت‌دار برای ۳۰ روز آینده** — مشخص و عملیاتی.
۴. **جمع‌بندی وضعیت کلی در یک جمله** — سبز/زرد/قرمز و چرا.

خروجی باید مختصر، دقیق، و قابل ارائه مستقیم به مدیر اجرایی طرح باشد.`;

    const aiRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-5",
        max_tokens: 2000,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    if (!aiRes.ok) {
      const errText = await aiRes.text();
      return jsonResponse({ error: "خطا در فراخوانی سرویس هوش مصنوعی: " + errText }, 502);
    }

    const aiData = await aiRes.json();
    const analysisText = aiData.content?.[0]?.text || "پاسخی دریافت نشد.";

    return jsonResponse({ analysis: analysisText });
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500);
  }
});
